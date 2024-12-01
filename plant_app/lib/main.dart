import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';

import 'add_device_dialog.dart';
import 'device_plants_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Senior Design',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> devices = [];
  Map<String, Map<String, dynamic>> deviceData = {};
  Timer? periodicTimer;

  // Stream controller to broadcast device updates
  final StreamController<Map<String, Map<String, dynamic>>> deviceDataStreamController = StreamController<Map<String, Map<String, dynamic>>>.broadcast();

  @override
  void initState() {
    super.initState();
    _loadDevices().then((_) {
      _checkPermissions(); // Check permissions on startup
    });
  }

  Future<void> _checkPermissions() async {
    // Request the necessary permissions for BLE and location services.
    // Permission.bluetooth in this array?
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      // If any permission is denied, show a message or retry asking for permission
      _showPermissionError();
      print('Missing Permissions: $statuses');
    } else {
      // Load devices after permissions are granted
      _loadDevices();
    }
  }

  void _showPermissionError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permissions required'),
        content: Text(
            'The app needs Bluetooth and location permissions to scan for devices.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('OK'),
          )
        ],
      ),
    );
  }

  Future<void> _loadDevices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedDevices = prefs.getStringList('devices');
    if (savedDevices != null) {
      devices = savedDevices
          .map((d) => json.decode(d))
          .toList()
          .cast<Map<String, dynamic>>();
    }

    // Load device data
    for (var device in devices) {
      String? savedData = prefs.getString('deviceData_${device['name']}');
      if (savedData != null) {
        Map<String, dynamic> decodedData = json.decode(savedData);
        deviceData[device['name']] = decodedData;
      } else {
        deviceData[device['name']] = {
          "plants": [],
          "data": {},
          "plantNames": {}
        };
      }
    }

    if (devices.isNotEmpty) {
      _startPeriodicRequests();
    }

    setState(() {});
  }

  Future<void> _saveDeviceData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Save devices list
    List<String> savedDevices = devices.map((d) => json.encode(d)).toList();
    prefs.setStringList('devices', savedDevices);

    // Save device data
    for (var entry in deviceData.entries) {
      String deviceName = entry.key;
      Map<String, dynamic> data = entry.value;

      await prefs.setString('deviceData_${deviceName}', json.encode(data));
    }
  }

  void _cleanOldData(String deviceName) {
    DateTime now = DateTime.now();

    if (deviceData[deviceName]?["data"] != null) {
      // Safely cast the data map
      Map<String, dynamic> plantsData = 
        Map<String, dynamic>.from(deviceData[deviceName]!["data"] as Map);

      plantsData.forEach((macAddress, plantData) {
        // Cast each plant's data map
        Map<String, dynamic> typedPlantData = 
          Map<String, dynamic>.from(plantData as Map);

        typedPlantData.forEach((key, valuesList) {
          if (valuesList is List) {
            List<Map<String, dynamic>> typedList = 
              (valuesList as List).map((entry) {
                return Map<String, dynamic>.from(entry as Map);
              }).toList();

            typedList = typedList.where((entry) {
              DateTime entryTime = DateTime.parse(entry['timestamp'].toString());
              return now.difference(entryTime).inHours < 24;
            }).toList();

            deviceData[deviceName]!["data"][macAddress][key] = typedList;
          }
        });
      });
    }
  }

  void _startPeriodicRequests() {
    if (periodicTimer == null && devices.isNotEmpty) {
      periodicTimer = Timer.periodic(Duration(seconds: 30), (timer) {
        for (var device in devices) {
          _sendHttpRequest(device['name'], device['identifier']);
        }
      });
    }
  }

  void _stopPeriodicRequests() {
    periodicTimer?.cancel();
    periodicTimer = null;
  }

  Future<void> _sendHttpRequest(String deviceName, String identifier) async {
    try {
      final url = Uri.parse('http://10.0.2.2:5000/data/$identifier');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        DateTime now = DateTime.now();

        var rawData = json.decode(response.body);
        Map<String, dynamic> responseData = {};

        if (rawData is Map) {
          responseData['plants'] = rawData['plants'];
          responseData['data'] = {};
          responseData['water'] = rawData['water']; // Add water level

          if (rawData['data'] is Map) {
            (rawData['data'] as Map).forEach((key, value) {
              if (key is String) {
                responseData['data'][key] = value;
              }
            });
          }
        }

        setState(() {
          deviceData.putIfAbsent(deviceName, () => {
            "plants": [],
            "data": {},
            "water": 0, // Initialize water level
          });

          // Update water level
          deviceData[deviceName]!["water"] = responseData['water'] ?? 0;

          // Rest of the existing code remains the same
          if (responseData['plants'] is List) {
            deviceData[deviceName]!["plants"] = 
                (responseData['plants'] as List).map((e) => e.toString()).toList();
          }

          if (responseData['data'] is Map) {
            (responseData['data'] as Map).forEach((macAddress, plantData) {
              String mac = macAddress.toString();
              if (!deviceData[deviceName]!["data"].containsKey(mac)) {
                deviceData[deviceName]!["data"][mac] = {};
              }

              if (plantData is Map) {
                plantData.forEach((key, value) {
                  String dataKey = key.toString();
                  deviceData[deviceName]!["data"][mac].putIfAbsent(dataKey, () => []);
                  deviceData[deviceName]!["data"][mac][dataKey].add({
                    'value': value,
                    'timestamp': now.toIso8601String()
                  });
                });
              }
            });
          }
        });

        deviceDataStreamController.add(deviceData);
        _cleanOldData(deviceName);
        _saveDeviceData();
      }
    } catch (e, stackTrace) {
      print('Error fetching device data: $e');
      print('Stack trace: $stackTrace');
    }
  }


  void _handlePlantDisconnection(String deviceName, String macAddress) {
    if (deviceData[deviceName]?["data"]?[macAddress] != null) {
      setState(() {
        // Remove plant data
        deviceData[deviceName]!["data"].remove(macAddress);
        // Remove from plants list
        List<String> plants = List<String>.from(deviceData[deviceName]!["plants"]);
        plants.remove(macAddress);
        deviceData[deviceName]!["plants"] = plants;
      });
      _saveDeviceData();
    }
  }

  void _addDevice(Map<String, dynamic> newDevice) {
    setState(() {
      devices.insert(0, newDevice);
      deviceData[newDevice['name']] = {
        "plants": [],
        "data": {}
      };
      _saveDeviceData();
    });

    if (devices.isNotEmpty) {
      _startPeriodicRequests();
    }
  }

  void _removeDevice(Map<String, dynamic> device) {
    setState(() {
      devices.remove(device);
      deviceData.remove(device['name']);
      _saveDeviceData();

      if (devices.isEmpty) {
        _stopPeriodicRequests();
      }
    });
  }

  void _showAddDeviceDialog() {
    AddDeviceDialog(onDeviceAdded: _addDevice).show(context);
  }

  @override
  void dispose() {
    periodicTimer?.cancel();
    deviceDataStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Devices'),
        centerTitle: true,
      ),
      body: ListView.builder(
        itemCount: devices.length,
        itemBuilder: (context, index) {
          final device = devices[index];
          final deviceName = device['name'];

          int plantCount = 0;
          int waterLevel = 0;
          if (deviceData.containsKey(deviceName)) {
            if (deviceData[deviceName]!.containsKey("plants")) {
              plantCount = (deviceData[deviceName]!["plants"] as List).length;
            }
            if (deviceData[deviceName]!.containsKey("water")) {
              waterLevel = (deviceData[deviceName]!["water"] as num).toInt();
            }
          }

          return Card(
            child: ListTile(
              title: Text(deviceName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connected Plants: $plantCount'),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.water_drop,
                        size: 16,
                        color: Colors.blue,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Water Level: $waterLevel%',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DevicePlantsPage(
                      device: device,
                      initialDeviceData: deviceData[deviceName] ?? 
                          {"plants": [], "data": {}, "water": 0},
                      deviceDataStream: deviceDataStreamController.stream,
                    ),
                  ),
                );
              },
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () => _removeDevice(device),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDeviceDialog,
        child: Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}


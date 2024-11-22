import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

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
  //final flutterReactiveBle = FlutterReactiveBle(); // Do I need this?
  List<Map<String, dynamic>> devices = [];
  Map<String, Map<String, dynamic>> deviceData = {};
  // "Device Name": {
    //   "plants": ["MAC1", "MAC2", "MAC3"], // List of MAC addresses
    //   "data": {
    //     "MAC1": {
    //       "temperature": [{"value": x, "timestamp": y}],
    //       "moisture": [{"value": x, "timestamp": y}],
    //       "uv": [{"value": x, "timestamp": y}]
    //     },
    //     "MAC2": { ... }
    //   }
    // }
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

    // Load device data with new structure
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

class AddDeviceDialog {
  final Function(Map<String, dynamic>) onDeviceAdded;
  final _deviceNameController = TextEditingController();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  //final flutterReactiveBle = FlutterReactiveBle();
  bool searching = false;
  String? errorMessage;

  AddDeviceDialog({required this.onDeviceAdded});

  Future<void> _searchForDevice(BuildContext context, setState) async {
    // Check if all fields are filled
    if (_deviceNameController.text.isEmpty ||
        _ssidController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() {
        errorMessage = 'All fields are required';
      });
      return;
    }

    setState(() {
      searching = true;
      errorMessage = null;
    });

    // Simulate bluetooth device search
    await Future.delayed(Duration(seconds: 2));

    // Create a completer to handle the timeout
    //Completer<DiscoveredDevice?> completer = Completer<DiscoveredDevice?>();

    //final List<String> devicesFound = [];
    // Start the device scan
    //StreamSubscription<DiscoveredDevice>? subscription;
    //subscription = flutterReactiveBle.scanForDevices(
    //  withServices: [],
    //  scanMode: ScanMode.lowLatency,
    //).listen((device) {
    //  if (!completer.isCompleted && device.name == 'Team22_nimBLE') {
    //    completer.complete(device);
    //    subscription?.cancel();
    //  } else if (!devicesFound.contains(device.name)) {
    //    devicesFound.add(device.name);
    //  }
    //});

    // Set up a timeout
    //Timer(Duration(seconds: 10), () {
    //  if (!completer.isCompleted) {
    //    completer.complete(null);
    //    subscription?.cancel();
    //  }
    //});

    // Wait for the result
    //DiscoveredDevice? result = await completer.future;
    //print('Devices Found: $devicesFound');

    // Simulate finding a device
    bool deviceFound = true;

    if (!deviceFound) {
      setState(() {
        errorMessage = 'No device found!';
        searching = false;
      });
      return;
    }

    // Generate hash identifier
    final deviceName = _deviceNameController.text;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final identifier = 'device123';

    // Send SSID, password, and identifier over BLE to the device
    //await _sendDataOverBLE(
    //    result.id, _ssidController.text, _passwordController.text, identifier);
    await _simulateSendDataOverBLE(_ssidController.text, _passwordController.text, identifier);

    // Add the device
    onDeviceAdded({
      'name': deviceName,
      'ssid': _ssidController.text,
      'password': _passwordController.text,
      'identifier': identifier
    });

    Navigator.of(context).pop();
  }

  Future<void> _simulateSendDataOverBLE(String ssid, String password, String identifier) async {
    // Simulate a delay for send data over BLE
    await Future.delayed(Duration(seconds: 1));
    print('Simulated BLE data sent: SSID=$ssid, Password=$password, Identifier=$identifier');
  }

  //String _generateHash(String input) {
  //  final bytes = utf8.encode(input);
  //  return sha256.convert(bytes).toString();
  //}

  //Future<void> _sendDataOverBLE(
  //    String deviceId, String ssid, String password, String identifier) async {
    // Define the service and characteristic UUIDs.
  //  final serviceUUID = Uuid.parse('78563412000000000000000000000000');
  //  final characteristicUUID = Uuid.parse('21436587000000000000000000000000');

    // Connect to the device.
  //  final connection = flutterReactiveBle
  //      .connectToDevice(id: deviceId)
  //      .listen((connectionState) {
  //    if (connectionState.connectionState == DeviceConnectionState.connected) {
        // Connected to the device, now write the data.
  //      _writeData(deviceId, ssid, password, identifier, serviceUUID,
  //          characteristicUUID);
  //    } else if (connectionState.connectionState ==
  //        DeviceConnectionState.disconnected) {
        // Handle disconnection if needed
  //      print('Disconnected from device $deviceId');
  //    }
  //  });

    // Cancel the connection listener after use.
  //  Future.delayed(Duration(seconds: 5), () {
  //    connection.cancel();
  //  });
  //}

  //Future<void> _writeData(String deviceId, String ssid, String password,
  //    String identifier, Uuid serviceUUID, Uuid characteristicUUID) async {
  //  final data = utf8.encode('$ssid,$password,$identifier');
  //  try {
  //    await flutterReactiveBle.writeCharacteristicWithoutResponse(
  //        QualifiedCharacteristic(
  //          serviceId: serviceUUID,
  //          characteristicId: characteristicUUID,
  //          deviceId: deviceId,
  //        ),
  //        value: data);
  //    print('Data written over BLE with response');
  //  } catch (e) {
  //    print('BLE write failed with error ${e}');
  //  }
  //}

  void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Add Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _deviceNameController,
                    decoration: InputDecoration(labelText: 'Device Name'),
                  ),
                  TextField(
                    controller: _ssidController,
                    decoration: InputDecoration(labelText: 'WiFi SSID'),
                  ),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(labelText: 'WiFi Password'),
                    obscureText: true,
                  ),
                  if (searching) CircularProgressIndicator(),
                  if (errorMessage != null)
                    Text(errorMessage!, style: TextStyle(color: Colors.red)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: searching
                      ? null
                      : () => _searchForDevice(context, setState),
                  child: Text('Add Device'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class DevicePlantsPage extends StatefulWidget {
  final Map<String, dynamic> device;
  final Map<String, dynamic> initialDeviceData;
  final Stream<Map<String, Map<String, dynamic>>> deviceDataStream;

  DevicePlantsPage({
    required this.device,
    required this.initialDeviceData,
    required this.deviceDataStream,
  });

  @override
  _DevicePlantsPageState createState() => _DevicePlantsPageState();
}

class _DevicePlantsPageState extends State<DevicePlantsPage> {
  late Map<String, dynamic> deviceData;
  final List<String> keysToShow = ['temperature', 'moisture', 'uv']; // Added keysToShow list

  @override
  void initState() {
    super.initState();
    deviceData = Map<String, dynamic>.from(widget.initialDeviceData);
    if (!deviceData.containsKey('plantNames')) {
      deviceData['plantNames'] = {};
    }

    widget.deviceDataStream.listen((updatedData) {
      if (mounted) {
        setState(() {
          var newData = updatedData[widget.device['name']] ?? {"plants": [], "data": {}};
          // Preserve plant names
          newData['plantNames'] = deviceData['plantNames'];
          deviceData = newData;
        });
      }
    });
  }

  Future<void> _renamePlant(String macAddress) async {
    String currentName = deviceData['plantNames'][macAddress] ?? 'Plant ${deviceData["plants"].indexOf(macAddress) + 1}';

    String? newName = await showDialog<String>(
      context: context,
      builder: (context) => RenameDialog(initialName: currentName),
    );

    if (newName != null && newName.trim().isNotEmpty) {
      setState(() {
        deviceData['plantNames'][macAddress] = newName.trim();
      });

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'deviceData_${widget.device['name']}',
        json.encode(deviceData)
      );
    }
  }

  String _getPlantName(String macAddress, int index) {
    return deviceData['plantNames'][macAddress] ?? 'Plant ${index + 1}';
  }

  // Helper method to build sensor data widgets
  List<Widget> _buildSensorDataWidgets(Map<String, dynamic> plantData) {
    List<Widget> widgets = [];
    
    for (String key in keysToShow) {
      if (plantData.containsKey(key) && 
          plantData[key] is List && 
          plantData[key].isNotEmpty) {
        
        var lastEntry = plantData[key].last;
        if (lastEntry is Map && lastEntry.containsKey('value')) {
          String value = lastEntry['value'].toString();
          widgets.add(
            Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                '$key: $value',
                style: TextStyle(fontSize: 14.0),
              ),
            )
          );
        }
      }
    }
    
    return widgets.isEmpty ? [Text('No data yet')] : widgets;
  }

  @override
  Widget build(BuildContext context) {
    List<String> plants = List<String>.from(deviceData["plants"] ?? []);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device['name']} Plants'),
      ),
      body: plants.isEmpty
          ? Center(
              child: Text('No plants connected to this device'),
            )
          : ListView.builder(
              itemCount: plants.length,
              itemBuilder: (context, index) {
                String macAddress = plants[index];
                Map<String, dynamic> plantData = 
                    Map<String, dynamic>.from(deviceData["data"][macAddress] ?? {});
                
                return Card(
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(_getPlantName(macAddress, index)),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _renamePlant(macAddress),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildSensorDataWidgets(plantData),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DeviceDetailPage(
                            device: widget.device,
                            macAddress: macAddress,
                            initialDeviceData: deviceData,
                            deviceDataStream: widget.deviceDataStream,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class RenameDialog extends StatefulWidget {
  final String initialName;

  RenameDialog({required this.initialName});

  @override
  _RenameDialogState createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rename Plant'),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: 'Plant name',
          hintText: 'Enter new name',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text('Save'),
        ),
      ],
    );
  }
}

class DeviceDetailPage extends StatefulWidget {
  final Map<String, dynamic> device;
  final String macAddress;
  final Map<String, dynamic> initialDeviceData;
  final Stream<Map<String, Map<String, dynamic>>> deviceDataStream;

  DeviceDetailPage({
      required this.device,
      required this.macAddress,
      required this.initialDeviceData,
      required this.deviceDataStream,
  });

  @override
  _DeviceDetailPageState createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  late Map<String, dynamic> deviceData;
  final List<String> keysToShow = ['temperature', 'moisture', 'uv'];

  String get plantName {
    String? customName = deviceData['plantNames']?[widget.macAddress];
    if (customName != null) {
      return customName;
    }

    // If no custom name, saffely get the index
    List<dynamic>? plants = deviceData['plants'] as List<dynamic>?;
    if (plants != null) {
      int index = plants.indexOf(widget.macAddress);
      if (index != -1) {
        return 'Plant ${index + 1}';
      }
    }

    return 'Plant';
  }

  @override
  void initState() {
    super.initState();
    deviceData = widget.initialDeviceData;
    // Ensure plantNames exists
    if (!deviceData.containsKey('plantNames')) {
      deviceData['plantNames'] = {};
    }

    // Listen to the stream for updates
    widget.deviceDataStream.listen((updatedData) {
      if (mounted) {
        setState(() {
          var newData = updatedData[widget.device['name']] ?? {};
          // Preserve plant names
          newData['plantNames'] = deviceData['plantNames'];
          deviceData = newData;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(plantName),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          // Existing code for displaying graphs
          ...keysToShow.map((key) => _buildGraphCard(key)).toList(),

          // Card for Scheduled Waterings
          _buildScheduledWateringsCard(),

          // Buttons for "Water" and "Schedule Watering"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _confirmWaterNow,
                child: Text('Water'),
              ),
              ElevatedButton(
                onPressed: _scheduleWatering,
                child: Text('Schedule Watering'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  double getRoundedMaxY(double actualMaxY) {
    return (actualMaxY / 5).ceil() * 5;
  }

  // Method to build the graph cards
  Widget _buildGraphCard(String key) {
    // Safely cast the nested maps
    Map<String, dynamic>? plantData;
    if (deviceData["data"] is Map) {
      var data = deviceData["data"] as Map;
      if (data[widget.macAddress] is Map) {
        plantData = Map<String, dynamic>.from(data[widget.macAddress]);
      }
    }

    // Check for null or missing data
    if (plantData == null || !plantData.containsKey(key) || plantData[key] == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No data available for $key'),
        ),
      );
    }

    // Safely cast the data points
    List<Map<String, dynamic>> dataPoints = [];
    var rawDataPoints = plantData[key];
    if (rawDataPoints is List) {
      dataPoints = rawDataPoints.map((point) {
        if (point is Map) {
          return Map<String, dynamic>.from(point);
        }
        return <String, dynamic>{};
      }).toList();
    }

    if (dataPoints.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No data available for $key'),
        ),
      );
    }

    // Safely access the last value
    String mostRecentValue = '';
    if (dataPoints.last.containsKey('value')) {
      mostRecentValue = dataPoints.last['value'].toString();
    }

    // Create the chart spots
    List<FlSpot> spots = [];
    try {
      spots = dataPoints.map((entry) {
        return FlSpot(
          DateTime.parse(entry['timestamp'] as String).millisecondsSinceEpoch.toDouble(),
          (entry['value'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      print('Error creating spots: $e');
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Error processing data for $key'),
        ),
      );
    }

    if (spots.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No valid data points for $key'),
        ),
      );
    }

    double maxY = spots.map((spot) => spot.y).reduce((a,b) => a > b ? a : b);
    maxY = getRoundedMaxY(maxY);

    return Card(
      child: Padding(
        padding: const EdgeInsets.only(left: 14.0, right: 0.0, top: 8.0, bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$key - Latest Value: $mostRecentValue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Container(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: spots.first.x,
                  maxX: spots.last.x,
                  minY: 0,
                  maxY: maxY,
                  titlesData: FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: (spots.length == 1) ? 1 : (spots.last.x - spots.first.x),
                        getTitlesWidget: (value, meta) {
                          if (value == spots.first.x || value == spots.last.x) {
                            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                            return Text(DateFormat('HH:mm').format(date));
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  gridData: FlGridData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: _getColorForKey(key),
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get different colors for different metrics
  Color _getColorForKey(String key) {
    switch (key) {
      case 'temperature':
        return Colors.red;
      case 'moisture':
        return Colors.blue;
      case 'uv':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // Method to build the Scheduled Waterings card
  Widget _buildScheduledWateringsCard() {
    final schedules = deviceData['schedules']?.where((schedule) =>
            schedule['macAddress'] == widget.macAddress)?.toList() ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scheduled Waterings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            if (schedules.isEmpty)
              Text('No scheduled waterings')
            else
              ...schedules.map((schedule) {
                final timestamp = schedule['time'] as int;
                return ListTile(
                  title: Text(
                    'Water at ${DateFormat('MM/dd/yyyy HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(timestamp),
                    )}'
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _confirmRemoveSchedule(schedule),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveSchedule(Map<String, dynamic> schedule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Schedule'),
        content: Text('Are you sure you want to remove this watering schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeSchedule(schedule);
            },
            child: Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSchedule(Map<String, dynamic> schedule) async {
    // Create a copy of the schedule with the action type
    Map<String, dynamic> removeRequest = Map.from(schedule);
    removeRequest['action'] = 'remove';  // Add action type

    final url = Uri.parse('http://10.0.2.2:5000/command/${widget.device['identifier']}');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(removeRequest),
    );

    if (response.statusCode == 200) {
      setState(() {
        deviceData['schedules'].removeWhere((s) => 
          s['time'] == schedule['time'] && 
          s['macAddress'] == schedule['macAddress']);
      });
    } else {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove schedule'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Confirm Water Now button press
  void _confirmWaterNow() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Watering'),
        content: Text('Are you sure you want to water now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _waterNow();
            },
            child: Text('Yes'),
          ),
        ],
      ),
    );
  }

  // Method to send water-now request
  Future<void> _waterNow() async {
    final identifier = widget.device['identifier'];
    final url = Uri.parse('http://10.0.2.2:5000/command/$identifier');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "type": "water-now",
        "macAddress": widget.macAddress,  // Add MAC address to request
      }),
    );
    if (response.statusCode == 200) {
      print('Watering request sent successfully');
    }
  }

  // Method to open the Schedule Watering dialog
  void _scheduleWatering() {
    showDialog(
      context: context,
      builder: (context) => ScheduleWateringDialog(
        deviceIdentifier: widget.device['identifier'],
        macAddress: widget.macAddress,  // Pass MAC address to dialog
        onScheduleAdded: _addSchedule,
      ),
    );
  }

  void _addSchedule(Map<String, dynamic> schedule) {
    setState(() {
      if (deviceData['schedules'] == null) {
        deviceData['schedules'] = [];
      }
      deviceData['schedules'].add(schedule);
    });
  }
}

class ScheduleWateringDialog extends StatefulWidget {
  final String deviceIdentifier;
  final String macAddress;  // Add MAC address parameter
  final Function(Map<String, dynamic>) onScheduleAdded;

  ScheduleWateringDialog({
    required this.deviceIdentifier,
    required this.macAddress,
    required this.onScheduleAdded,
  });

  @override
  _ScheduleWateringDialogState createState() => _ScheduleWateringDialogState();
}

class _ScheduleWateringDialogState extends State<ScheduleWateringDialog> {
  TimeOfDay? selectedTime;
  bool isRepeating = false;
  List<String> selectedDays = [];
  DateTime? endDate;

  final List<String> allDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Schedule Watering'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time picker for selecting a time
          ListTile(
            title: Text(selectedTime != null
                ? 'Time: ${selectedTime!.format(context)}'
                : 'Select Time'),
            onTap: _pickTime,
          ),
          // Checkbox for repeating option
          CheckboxListTile(
            title: Text('Repeat'),
            value: isRepeating,
            onChanged: (value) {
              setState(() {
                isRepeating = value ?? false;
              });
            },
          ),
          if (isRepeating) ...[
            // Dropdown to select repeating days
            Wrap(
              spacing: 10,
              children: allDays.map((day) {
                return FilterChip(
                  label: Text(day),
                  selected: selectedDays.contains(day),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        selectedDays.add(day);
                      } else {
                        selectedDays.remove(day);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            // Date picker to select an end date
            ListTile(
              title: Text(endDate != null
                  ? 'End Date: ${endDate!.toLocal()}'
                  : 'Select End Date'),
              onTap: _pickEndDate,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: _schedule,
          child: Text('Schedule'),
        ),
      ],
    );
  }

  // Time picker for selecting time
  Future<void> _pickTime() async {
    TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  // Date picker for selecting end date
  Future<void> _pickEndDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      setState(() {
        endDate = picked;
      });
    }
  }

  // Method to schedule watering
  Future<void> _schedule() async {
    if (selectedTime == null) {
      // Show an error message or warning that time is not selected
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Error'),
          content: Text('Please select a time for the watering schedule'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    DateTime now = DateTime.now();
    DateTime scheduleTime = DateTime(
      now.year,
      now.month,
      now.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );

    Map<String, dynamic> schedule = {
      "type": "water-schedule",
      "action": "add",
      "macAddress": widget.macAddress,
      "repeating": isRepeating,
      "time": scheduleTime.millisecondsSinceEpoch,
    };

    if (isRepeating) {
      schedule["days"] = selectedDays;
      schedule["end-date"] = endDate?.millisecondsSinceEpoch;
    }

    // Send POST request to schedule watering
    final identifier = widget.deviceIdentifier; // Get device UID
    final url = Uri.parse('http://10.0.2.2:5000/command/$identifier');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(schedule),
    );

    if (response.statusCode == 200) {
      widget.onScheduleAdded(schedule); // Update parent with new schedule
      Navigator.pop(context); // Close the dialog
    } else {
      // Error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add schedule'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

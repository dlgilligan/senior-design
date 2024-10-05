import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final flutterReactiveBle = FlutterReactiveBle();
  List<Map<String, dynamic>> devices = [];
  Map<String, Map<String, List<Map<String, dynamic>>>> deviceData = {};
  Timer? periodicTimer;

  // Keys to display on the home-page card
  final List<String> keysToShow = ['temperature', 'moisture'];

  @override
  void initState() {
    super.initState();
    _checkPermissions(); // Check permissions on startup
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

    if (devices.isNotEmpty) {
      _startPeriodicRequests();
    }

    setState(() {});
  }

  Future<void> _saveDevices() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedDevices = devices.map((d) => json.encode(d)).toList();
    prefs.setStringList('devices', savedDevices);
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
    final url = Uri.parse('http://example.com/?UID=$identifier');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      DateTime now = DateTime.now();

      // Decode the response body as key-value pairs
      Map<String, dynamic> responseData = json.decode(response.body);

      // Update the deviceData map with new data
      setState(() {
        deviceData.putIfAbsent(deviceName, () => {});

        responseData.forEach((key, value) {
          deviceData[deviceName]!.putIfAbsent(key, () => []);
          // Add new response to the list
          deviceData[deviceName]![key]!
              .add({'value': value, 'timestamp': now.toIso8601String()});

          // Remove responses older than 24 hours
          deviceData[deviceName]![key] =
              deviceData[deviceName]![key]!.where((entry) {
            DateTime entryTime = DateTime.parse(entry['timestamp']);
            return now.difference(entryTime).inHours < 24;
          }).toList();
        });
      });
    }
  }

  void _addDevice(Map<String, dynamic> newDevice) {
    setState(() {
      devices.insert(0, newDevice);
      _saveDevices();
    });

    if (devices.isNotEmpty) {
      _startPeriodicRequests();
    }
  }

  void _removeDevice(Map<String, dynamic> device) {
    setState(() {
      devices.remove(device);
      _saveDevices();

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
          // Get the latest key-value pair for display
          String latestValue = '';
          if (deviceData.containsKey(device['name'])) {
            deviceData[device['name']]!.forEach((key, values) {
              if (values.isNotEmpty) {
                latestValue = values.last['value'].toString();
              }
            });
          }

          return Card(
            child: ListTile(
              title: Text(device['name']),
              subtitle:
                  Text(latestValue.isNotEmpty ? latestValue : 'No data yet'),
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => DeviceDetailPage(
                              device: device,
                              deviceData: deviceData[device['name']] ?? {},
                            )));
              },
              trailing: IconButton(
                icon: Icon(Icons.delete),
                onPressed: () {
                  _removeDevice(device);
                },
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
  final flutterReactiveBle = FlutterReactiveBle();
  bool searching = false;
  String? errorMessage;

  AddDeviceDialog({required this.onDeviceAdded});

  Future<void> _searchForDevice(BuildContext context, setState) async {
    setState(() {
      searching = true;
      errorMessage = null;
    });

    final result = await flutterReactiveBle.scanForDevices(
        withServices: [Uuid.parse('PLACEHOLDER')],
        scanMode: ScanMode.lowLatency).first;

    if (result == null) {
      setState(() {
        errorMessage = 'No device found!';
        searching = false;
      });
      return;
    }

    // Generate hash identifier
    final deviceName = _deviceNameController.text;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final identifier = _generateHash(deviceName + timestamp);

    // Send SSID, password, and identifier over BLE to the device
    await _sendDataOverBLE(
        result.id, _ssidController.text, _passwordController.text, identifier);

    // Add the device
    onDeviceAdded({
      'name': deviceName,
      'ssid': _ssidController.text,
      'password': _passwordController.text,
      'identifier': identifier
    });

    Navigator.of(context).pop();
  }

  String _generateHash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  Future<void> _sendDataOverBLE(
      String deviceId, String ssid, String password, String identifier) async {
    // Define the service and characteristic UUIDs.
    final serviceUUID = Uuid.parse('PLACEHOLDER');
    final characteristicUUID = Uuid.parse('PLACEHOLDER');

    // Connect to the device.
    final connection = flutterReactiveBle
        .connectToDevice(id: deviceId)
        .listen((connectionState) {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        // Connected to the device, now write the data.
        _writeData(deviceId, ssid, password, identifier, serviceUUID,
            characteristicUUID);
      } else if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        // Handle disconnection if needed
        print('Disconnected from device $deviceId');
      }
    });

    // Cancel the connection listener after use.
    Future.delayed(Duration(seconds: 5), () {
      connection.cancel();
    });
  }

  Future<void> _writeData(String deviceId, String ssid, String password,
      String identifier, Uuid serviceUUID, Uuid characteristicUUID) async {
    final data = utf8.encode('$ssid,$password,$identifier');
    await flutterReactiveBle.writeCharacteristicWithoutResponse(
        QualifiedCharacteristic(
          serviceId: serviceUUID,
          characteristicId: characteristicUUID,
          deviceId: deviceId,
        ),
        value: data);
  }

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

class DeviceDetailPage extends StatelessWidget {
  final Map<String, dynamic> device;
  final Map<String, List<Map<String, dynamic>>> deviceData;

  DeviceDetailPage({required this.device, required this.deviceData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device['name']),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        itemCount: deviceData.keys.length,
        itemBuilder: (context, index) {
          String key = deviceData.keys.elementAt(index);
          List<Map<String, dynamic>> dataPoints = deviceData[key]!;

          // Prepare data for the graph
          List<FlSpot> spots = dataPoints.map((entry) {
            return FlSpot(
              DateTime.parse(entry['timestamp']).millisecondsSinceEpoch.toDouble(),
              entry['value'].toDouble(),
            );
          }).toList();

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(key, style: TextStyle(fontSize: 20)),
                  Container(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true),
                          ),
                        ),
                        borderData: FlBorderData(show: true),
                        gridData: FlGridData(show: true),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            gradient: LinearGradient(
                              colors: [Colors.blue],  // Use gradient instead of colors
                            ),
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
        },
      ),
    );
  }
}

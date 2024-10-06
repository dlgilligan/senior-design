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
  final List<String> keysToShow = ['temperature', 'moisture', 'uv'];

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
          final deviceName = device['name'];

          // Get the filtered latest values for the keys we want to show
          List<Widget> keyValueWidgets = [];
          if (deviceData.containsKey(deviceName)) {
            deviceData[deviceName]!.forEach((key, values) {
              if (keysToShow.contains(key) && values.isNotEmpty) {
                String latestValue = values.last['value'].toString();
                keyValueWidgets.add(Text('$key: $latestValue'));
              }
            });
          }

          return Card(
            child: ListTile(
              title: Text(deviceName),
              // Display filtered key-value pairs as the subtitle
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: keyValueWidgets.isNotEmpty ? keyValueWidgets : [Text('No data yet')],
              ),
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => DeviceDetailPage(
                              device: device,
                              deviceData: deviceData[deviceName] ?? {},
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


class DeviceDetailPage extends StatefulWidget {
  final Map<String, dynamic> device;
  final Map<String, List<Map<String, dynamic>>> deviceData;

  DeviceDetailPage({required this.device, required this.deviceData});

  @override
  _DeviceDetailPageState createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  final List<String> keysToShow = ['temperature', 'moisture', 'uv'];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device['name']),
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

  // Method to build the graph cards
  Widget _buildGraphCard(String key) {
    if (!widget.deviceData.containsKey(key) || widget.deviceData[key]!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No data available for $key'),
        ),
      );
    }

    List<Map<String, dynamic>> dataPoints = widget.deviceData[key]!;
    String mostRecentValue = dataPoints.last['value'].toString();
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
                      gradient: LinearGradient(colors: [Colors.blue]),
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

  // Method to build the Scheduled Waterings card
  Widget _buildScheduledWateringsCard() {
    List<Map<String, dynamic>>? schedules = widget.deviceData['schedules'];

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
            if (schedules == null || schedules.isEmpty)
              Text('No scheduled waterings')
            else
              ...schedules.map((schedule) => Text(
                  'Water at ${DateTime.fromMillisecondsSinceEpoch(schedule['time']).toLocal()}')),
          ],
        ),
      ),
    );
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
              Navigator.pop(context); // Close the dialog
              _waterNow(); // Call water now method
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
    final url = Uri.parse('http://example.com/water');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "type": "water-now",
        "identifier": identifier,
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
        onScheduleAdded: _addSchedule,
      ),
    );
  }

  // Callback for when a new schedule is added
  void _addSchedule(Map<String, dynamic> schedule) {
    setState(() {
      if (!widget.deviceData.containsKey('schedules')) {
        widget.deviceData['schedules'] = [];
      }
      widget.deviceData['schedules']!.add(schedule);
    });
  }
}

class ScheduleWateringDialog extends StatefulWidget {
  final String deviceIdentifier;
  final Function(Map<String, dynamic>) onScheduleAdded;

  ScheduleWateringDialog({required this.deviceIdentifier, required this.onScheduleAdded});

  @override
  _ScheduleWateringDialogState createState() => _ScheduleWateringDialogState();
}

class _ScheduleWateringDialogState extends State<ScheduleWateringDialog> {
  TimeOfDay? selectedTime;
  bool isRepeating = false;
  List<String> selectedDays = [];
  DateTime? endDate;

  final List<String> allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Schedule Watering'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time picker for selecting a time
          ListTile(
            title: Text(selectedTime != null ? 'Time: ${selectedTime!.format(context)}' : 'Select Time'),
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
              title: Text(endDate != null ? 'End Date: ${endDate!.toLocal()}' : 'Select End Date'),
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
    TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
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
      "repeating": isRepeating,
      "time": scheduleTime.millisecondsSinceEpoch,
    };

    if (isRepeating) {
      schedule["days"] = selectedDays;
      schedule["end-date"] = endDate?.millisecondsSinceEpoch;
    }

    // Send POST request to schedule watering
    final url = Uri.parse('http://example.com/schedule');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(schedule),
    );

    if (response.statusCode == 200) {
      widget.onScheduleAdded(schedule); // Update parent with new schedule
      Navigator.pop(context); // Close the dialog
    }
  }
}

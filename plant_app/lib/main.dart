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
  Map<String, Map<String, List<Map<String, dynamic>>>> deviceData = {};
  Timer? periodicTimer;

  // Keys to display on the home-page card
  final List<String> keysToShow = ['temperature', 'moisture', 'uv'];

  // Stream controller to broadcast device updates
  final StreamController<Map<String, Map<String, List<Map<String, dynamic>>>>>
      deviceDataStreamController = StreamController<
          Map<String, Map<String, List<Map<String, dynamic>>>>>.broadcast();

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
        deviceData[device['name']] = {};

        decodedData.forEach((key, value) {
          List<dynamic> dataList = value as List<dynamic>;
          deviceData[device['name']]![key] = dataList
              .map((item) => {
                    'value': item['value'], 
                    'timestamp': item['timestamp'],
                  })
              .toList()
              .cast<Map<String, dynamic>>();
        });

        // Clean up old data on load
        _cleanOldData(device['name']);
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
      Map<String, List<Map<String, dynamic>>> data = entry.value;

      await prefs.setString('deviceData_${deviceName}', json.encode(data));
    }
  }

  void _cleanOldData(String deviceName) {
    DateTime now = DateTime.now();

    deviceData[deviceName]?.forEach((key, valuesList) {
      deviceData[deviceName]![key] = valuesList.where((entry) {
        DateTime entryTime = DateTime.parse(entry['timestamp']);
        return now.difference(entryTime).inHours < 24;
      }).toList();
    });
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
    final url = Uri.parse('http://10.0.2.2:5000/data/$identifier');
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
          deviceData[deviceName]![key]!.add({
            'value': value,
            'timestamp': now.toIso8601String()
          });
        });

        // Clean up old data and save
        _cleanOldData(deviceName);
        _saveDeviceData();
      });

      // Send updated data through the stream
      deviceDataStreamController.add(deviceData);
    }
  }

  void _addDevice(Map<String, dynamic> newDevice) {
    setState(() {
      devices.insert(0, newDevice);
      _saveDeviceData();
    });

    if (devices.isNotEmpty) {
      _startPeriodicRequests();
    }
  }

  void _removeDevice(Map<String, dynamic> device) {
    setState(() {
      devices.remove(device);
      deviceData.remove(device['name']); // Also remove the device's data
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
                children: keyValueWidgets.isNotEmpty
                    ? keyValueWidgets
                    : [Text('No data yet')],
              ),
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => DeviceDetailPage(
                              device: device,
                              initialDeviceData: deviceData[deviceName] ?? {},
                              deviceDataStream:
                                  deviceDataStreamController.stream,
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

class DeviceDetailPage extends StatefulWidget {
  final Map<String, dynamic> device;
  final Map<String, List<Map<String, dynamic>>> initialDeviceData;
  final Stream<Map<String, Map<String, List<Map<String, dynamic>>>>>
      deviceDataStream;

  DeviceDetailPage(
      {required this.device,
      required this.initialDeviceData,
      required this.deviceDataStream});

  @override
  _DeviceDetailPageState createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  late Map<String, List<Map<String, dynamic>>> deviceData;
  final List<String> keysToShow = ['temperature', 'moisture', 'uv'];

  @override
  void initState() {
    super.initState();
    deviceData = widget.initialDeviceData;
    // Listen to the stream for updates
    widget.deviceDataStream.listen((updatedData) {
      if (mounted) {
        setState(() {
          deviceData = updatedData[widget.device['name']] ?? {};
        });
      }
    });
  }

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
  
  double getRoundedMaxY(double actualMaxY) {
    return (actualMaxY / 5).ceil() * 5;
  }

  // Method to build the graph cards
  Widget _buildGraphCard(String key) {
    print('=== Debug: Building graph card for key: $key ===');
    print('1. Current deviceData: $deviceData');
    print('2. Keys in deviceData: ${deviceData.keys.toList()}');

    // First check if the key doesn't exist or if the data is null
    if (!deviceData.containsKey(key) || deviceData[key] == null) {
      print('3. Early return: key missing or null');
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No data available for $key'),
        ),
      );
    }

    print('4. Retrieved data for key: ${deviceData[key]}');
    List<Map<String, dynamic>> dataPoints = deviceData[key]!;
    print('5. DataPoints length: ${dataPoints.length}');

    // just in case check if the data points list is empty, previously had an error here
    // Check if the change earlier in the code is enough.
    if (dataPoints.isEmpty) {
      print('6. Early return: dataPoints is empty');
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('No data available for $key'),
        ),
      );
    }

    print('7. Last dataPoint: ${dataPoints.last}');
    String mostRecentValue = dataPoints.last['value'].toString();
    print('8. mostRecentValue: $mostRecentValue');

    print('9. Creating FlSpots...');
    List<FlSpot> spots = dataPoints.map((entry) {
      print('10. Processing entry: $entry');
      return FlSpot(
        DateTime.parse(entry['timestamp']).millisecondsSinceEpoch.toDouble(),
        entry['value'].toDouble(),
      );
    }).toList();
    print('11. FlSpots created: ${spots.length} spots');

    // Calculate maxY
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
                        interval: (spots.length == 1) ? 1 : (spots.last.x - spots.first.x), // Show only first and last labels
                        getTitlesWidget: (value, meta) {
                          if (value == spots.first.x || value == spots.last.x) {
                            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                            return Text(DateFormat('HH:mm').format(date)); // formats as "00:00" time
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
                      isCurved: false, // Straight lines between points
                      color: Colors.blue,
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
    // Get schedules from deviceData if it exists, otherwise empty list
    final schedules = deviceData['schedules'] ?? [];

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
                return Text(
                  'Water at ${DateFormat('MM/dd/yyyy HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(timestamp)
                  )}'
                );
              }),
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
    final url = Uri.parse('http://10.0.2.2:5000/command/$identifier');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "type": "water-now",
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
      deviceData.putIfAbsent('schedules', () => []);
      deviceData['schedules']!.add(schedule);
    });
  }
}

class ScheduleWateringDialog extends StatefulWidget {
  final String deviceIdentifier;
  final Function(Map<String, dynamic>) onScheduleAdded;

  ScheduleWateringDialog(
      {required this.deviceIdentifier, required this.onScheduleAdded});

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
    }
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

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

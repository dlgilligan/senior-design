import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

import 'device_detail_page.dart';

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

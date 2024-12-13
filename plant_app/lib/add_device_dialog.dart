import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';

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

    // Create a completer to handle the timeout
    Completer<DiscoveredDevice?> completer = Completer<DiscoveredDevice?>();

    final List<String> devicesFound = [];
    // Start the device scan
    StreamSubscription<DiscoveredDevice>? subscription;
    subscription = flutterReactiveBle.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (!completer.isCompleted && device.name == 'Team22_nimBLE') {
        completer.complete(device);
        subscription?.cancel();
      } else if (!devicesFound.contains(device.name)) {
        devicesFound.add(device.name);
      }
    });

    // Set up a timeout
    Timer(Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription?.cancel();
      }
    });

    // Wait for the result
    DiscoveredDevice? result = await completer.future;
    print('Devices Found: $devicesFound');

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
    final serviceUUID = Uuid.parse('78563412000000000000000000000000');
    final characteristicUUID = Uuid.parse('21436587000000000000000000000000');

    // Connect to the device.
    final connection = flutterReactiveBle
        .connectToDevice(id: deviceId)
        .listen((connectionState) async {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        // Connected to the device, now write the data.
        try {
          await flutterReactiveBle.requestMtu(deviceId: deviceId, mtu: 247);
          print('MTU size set to 247');
        } catch (e) {
          print('Failed to set MTU: $e');
        }
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
    print('Identifier: ${identifier}');
    final data = utf8.encode('$ssid,$password,$identifier');
    try {
      await flutterReactiveBle.writeCharacteristicWithoutResponse(
          QualifiedCharacteristic(
            serviceId: serviceUUID,
            characteristicId: characteristicUUID,
            deviceId: deviceId,
          ),
          value: data);
      print('Data written over BLE with response');
    } catch (e) {
      print('BLE write failed with error ${e}');
    }
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

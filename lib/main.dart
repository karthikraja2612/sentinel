import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sentinel',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? mapController;
  Position? _currentPosition;
  bool _mapCreated = false;
  
  // BLE Variables
  bool _isScanning = false;
  final List<BluetoothDevice> _discoveredDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Map<String, String> _deviceLocations = {}; // deviceId -> location data
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initBluetooth();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  void _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _currentPosition = await Geolocator.getCurrentPosition();
    setState(() {});

    Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });

        if (_mapCreated && mapController != null) {
          mapController?.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude)
            ),
          );
        }
      }
    });
  }

  void _initBluetooth() async {
    // Check if Bluetooth is supported
    bool isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      return;
    }

    // Request permissions
    await FlutterBluePlus.turnOn();
  }

  void _startScanning() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    // Listen for scan results
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Add new devices to the list
          for (var result in results) {
            if (!_discoveredDevices.contains(result.device)) {
              _discoveredDevices.add(result.device);
            }
          }
        });
      }
    });

    // Start scanning
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      continuousUpdates: true,
    );

    // Auto-stop after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      _stopScanning();
    });
  }

  void _stopScanning() {
    if (!_isScanning) return;

    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    
    setState(() {
      _isScanning = false;
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      // Connect to the device
      await device.connect();
      
      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _sendLocationToDevice(device);
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.platformName}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _sendLocationToDevice(BluetoothDevice device) {
    if (_currentPosition == null) return;
    
    // Create location data to send
    String locationData = 'SENTINEL_LOCATION:${_currentPosition!.latitude},${_currentPosition!.longitude},${DateTime.now().millisecondsSinceEpoch}';
    
    // In a real app, we'd use GATT characteristics to send this data
    // For now, we'll simulate it by storing in our state
    setState(() {
      _deviceLocations[device.remoteId.str] = '${device.platformName}: $locationData';
    });
  }

  void _shareMyLocation() {
    if (_discoveredDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No devices found to share with'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Share location with all discovered Sentinel devices
    for (var device in _discoveredDevices) {
      if (device.platformName.toLowerCase().contains('sentinel')) {
        _connectToDevice(device);
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sharing location with nearby Sentinel users'),
      ),
    );
  }

  void _onMapCreated(MapLibreMapController controller) {
    setState(() {
      mapController = controller;
      _mapCreated = true;
    });

    if (_currentPosition != null) {
      controller.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        ),
      );
    }
  }

  void _showEmergencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Emergency Mode'),
            ],
          ),
          content: const Text(
            'This will broadcast your location to nearby helpers and send emergency alerts. '
            'Only use in actual emergencies.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _activateEmergencyMode();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('ACTIVATE SOS', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _activateEmergencyMode() {
    // Start broadcasting via BLE
    _startScanning();
    
    // Auto-share location when devices are found
    Future.delayed(const Duration(seconds: 3), () {
      _shareMyLocation();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text('🆘 EMERGENCY MODE - Sharing location with all nearby Sentinel users'),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _refreshLocation() {
    _initLocation();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.gps_fixed, color: Colors.white),
            SizedBox(width: 8),
            Text('Refreshing location...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sentinel'),
        backgroundColor: Colors.green[700],
      ),
      body: Stack(
        children: [
          // Basic map
          MapLibreMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: LatLng(
                _currentPosition?.latitude ?? 37.7749, 
                _currentPosition?.longitude ?? -122.4194
              ),
              zoom: 14.0,
            ),
            myLocationEnabled: true,
          ),
          
          // BLE Device List - Enhanced with location sharing
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with share button
                  Row(
                    children: [
                      Icon(
                        Icons.bluetooth,
                        color: _isScanning ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isScanning ? 'Scanning...' : 'Nearby Devices (${_discoveredDevices.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_discoveredDevices.isNotEmpty && !_isScanning)
                        IconButton(
                          icon: const Icon(Icons.share_location, color: Colors.blue),
                          onPressed: _shareMyLocation,
                          tooltip: 'Share my location with all Sentinel users',
                        ),
                      if (!_isScanning)
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _startScanning,
                          tooltip: 'Scan for devices',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  if (_discoveredDevices.isEmpty)
                    const Text(
                      'No devices found\nTap refresh to scan for Sentinel users',
                      style: TextStyle(color: Colors.grey),
                    ),
                  
                  // Device list
                  if (_discoveredDevices.isNotEmpty)
                    Column(
                      children: _discoveredDevices.map((device) {
                        bool isSentinel = device.platformName.toLowerCase().contains('sentinel');
                        String? deviceLocation = _deviceLocations[device.remoteId.str];
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              isSentinel ? Icons.emergency : Icons.phone_android,
                              color: isSentinel ? Colors.green : Colors.grey,
                            ),
                            title: Text(
                              device.platformName.isEmpty 
                                  ? 'Unknown Device' 
                                  : device.platformName,
                              style: TextStyle(
                                fontWeight: isSentinel ? FontWeight.bold : FontWeight.normal,
                                color: isSentinel ? Colors.green : Colors.black,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSentinel ? 'Sentinel User' : 'Nearby Device',
                                  style: TextStyle(
                                    color: isSentinel ? Colors.green : Colors.grey,
                                  ),
                                ),
                                if (deviceLocation != null)
                                  Text(
                                    '📍 Location shared',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: isSentinel 
                                ? IconButton(
                                    icon: const Icon(Icons.near_me, color: Colors.blue),
                                    onPressed: () => _connectToDevice(device),
                                    tooltip: 'Share location with this user',
                                  )
                                : const Icon(Icons.signal_wifi_4_bar, color: Colors.grey),
                          ),
                        );
                      }).toList(),
                    ),
                  
                  // Shared locations summary
                  if (_deviceLocations.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const Text(
                      'Shared Locations:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._deviceLocations.entries.map((entry) => 
                      Text(
                        '• ${entry.value}',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      )
                    ).toList(),
                  ],
                ],
              ),
            ),
          ),
          
          // Coordinates display
          Positioned(
            top: 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _currentPosition != null 
                  ? '📍 Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\nLng: ${_currentPosition!.longitude.toStringAsFixed(6)}'
                  : '📍 Getting location...',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
      
      // Emergency and location buttons
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () => _showEmergencyDialog(context),
            backgroundColor: Colors.red,
            child: const Icon(Icons.warning, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _refreshLocation,
            backgroundColor: Colors.blue,
            mini: true,
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
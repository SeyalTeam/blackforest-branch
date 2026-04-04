import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothPrinterSettingsPage extends StatefulWidget {
  const BluetoothPrinterSettingsPage({super.key});

  @override
  State<BluetoothPrinterSettingsPage> createState() =>
      _BluetoothPrinterSettingsPageState();
}

class _BluetoothPrinterSettingsPageState
    extends State<BluetoothPrinterSettingsPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _isBluetoothOn = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _connected = false;
  String _message = '';
  String? _savedMacAddress;
  List<BluetoothInfo> _devices = [];

  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _scaleAnimation =
        Tween<double>(begin: 0.8, end: 1.2).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _animationController.reverse();
          } else if (status == AnimationStatus.dismissed) {
            _animationController.forward();
          }
        });

    _initBluetooth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initBluetooth();
    }
  }

  Future<void> _turnOnBluetooth() async {
    try {
      const channel = MethodChannel('blackforest.app/bluetooth');
      await channel.invokeMethod('turnOnBluetooth');

      for (var index = 0; index < 5; index++) {
        await Future.delayed(const Duration(seconds: 1));
        final state = await PrintBluetoothThermal.bluetoothEnabled;
        if (state) {
          if (!mounted) return;
          setState(() => _isBluetoothOn = true);
          await _getDevices();
          return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Unable to open Bluetooth settings: $error';
      });
    }
  }

  Future<void> _initBluetooth() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _savedMacAddress = prefs.getString('bt_printer_mac');
      });
    }

    if (await Permission.bluetoothConnect.isDenied ||
        await Permission.bluetoothScan.isDenied ||
        await Permission.location.isDenied) {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }

    final state = await PrintBluetoothThermal.bluetoothEnabled;
    if (!mounted) return;

    setState(() => _isBluetoothOn = state);
    if (state) {
      await _getDevices();
    }
  }

  Future<void> _getDevices() async {
    if (!mounted) return;

    setState(() {
      _isScanning = true;
      _message = 'Scanning...';
    });
    _animationController.forward();

    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;

      setState(() {
        _devices = devices;
        _message = _devices.isEmpty
            ? 'No paired devices found. Pair the printer in phone settings first.'
            : 'Found ${_devices.length} devices. Tap one to connect.';
      });
      await _checkConnectionState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Error scanning devices: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
        _animationController.reset();
      }
    }
  }

  Future<void> _checkConnectionState() async {
    final isConnected = await PrintBluetoothThermal.connectionStatus;
    if (!mounted) return;

    setState(() => _connected = isConnected);

    if (!isConnected && _savedMacAddress != null && !_isConnecting) {
      final savedDevice = _devices.firstWhere(
        (device) => device.macAdress == _savedMacAddress,
        orElse: () => BluetoothInfo(name: '', macAdress: ''),
      );
      if (savedDevice.macAdress.isNotEmpty) {
        unawaited(_connect(savedDevice, isAutoConnect: true));
      }
    }
  }

  Future<void> _connect(
    BluetoothInfo selectedDevice, {
    bool isAutoConnect = false,
  }) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _message = isAutoConnect ? 'Auto-connecting...' : 'Connecting...';
    });

    try {
      await PrintBluetoothThermal.disconnect;
      await Future.delayed(const Duration(milliseconds: 600));

      var connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: selectedDevice.macAdress,
      );

      if (!connected) {
        await Future.delayed(const Duration(seconds: 1));
        connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: selectedDevice.macAdress,
        );
      }

      if (!mounted) return;

      if (connected) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bt_printer_mac', selectedDevice.macAdress);
        await prefs.setString('bt_printer_name', selectedDevice.name);
        setState(() {
          _connected = true;
          _savedMacAddress = selectedDevice.macAdress;
          _message = 'Connected';
        });
      } else {
        setState(() {
          _message =
              'Failed to connect. Make sure the printer is turned on and paired.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Connection error. Try restarting the printer.';
      });
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _disconnect() async {
    final disconnected = await PrintBluetoothThermal.disconnect;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bt_printer_mac');
    await prefs.remove('bt_printer_name');

    if (!mounted) return;
    setState(() {
      _connected = false;
      _savedMacAddress = null;
      _message = disconnected ? 'Disconnected' : 'Failed to disconnect';
    });
  }

  @override
  Widget build(BuildContext context) {
    BluetoothInfo? connectedDevice;
    if (_savedMacAddress != null && _devices.isNotEmpty) {
      try {
        connectedDevice = _devices.firstWhere(
          (device) => device.macAdress == _savedMacAddress,
        );
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Printer'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value != 'reset') return;

              final messenger = ScaffoldMessenger.of(context);
              await _disconnect();
              await _getDevices();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Printer settings reset')),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Hard Reset Connection'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        color: const Color(0xFFF8F9FA),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (!_isBluetoothOn) ...[
              const SizedBox(height: 20),
              const Text(
                'Bluetooth is off',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 60,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF16A34A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.bluetooth,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Bluetooth',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              width: 44,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _turnOnBluetooth,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Open Bluetooth',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else if (_connected && connectedDevice != null) ...[
              const SizedBox(height: 40),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.print, size: 60, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              Text(
                connectedDevice.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check, color: Color(0xFF16A34A), size: 18),
                  SizedBox(width: 4),
                  Text(
                    'Connected',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.bluetooth, color: Color(0xFF16A34A), size: 16),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _disconnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  final scale = _isScanning ? _scaleAnimation.value : 1.0;
                  return Container(
                    width: 160 * scale,
                    height: 160 * scale,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEAF7F1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 100 * scale,
                        height: 100 * scale,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD4EFE3),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.search,
                              color: Color(0xFF16A34A),
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Please make sure the printer is turned on',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: const Icon(
                          Icons.print,
                          size: 32,
                          color: Colors.black87,
                        ),
                        title: Text(
                          device.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              Icons.bluetooth,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Disconnected',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _connect(device),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEAF7F1),
                            foregroundColor: const Color(0xFF16A34A),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: const Text('Connect'),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _getDevices,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Refresh Devices',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

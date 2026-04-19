import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'printer/bluetooth_printer_settings_page.dart';
import 'printer/wifi_printer_settings_page.dart';
import 'profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _username = 'User';
  String _branchName = '';

  bool _isCheckingBluetooth = true;
  bool _isBluetoothConnected = false;

  bool _isCheckingWifiPrinter = true;
  bool _isWifiPrinterConnected = false;

  bool _isCheckingLocation = true;
  bool _isLocationEnabled = false;
  bool _hasLocationPermission = false;

  String? _branchIpRange;
  String? _deviceWifiIp;
  String? _printerName;
  String? _wifiPrinterIp;

  @override
  void initState() {
    super.initState();
    _loadSettingsSummary();
  }

  Future<void> _loadSettingsSummary() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _username =
          prefs.getString('employee_name') ??
          prefs.getString('username') ??
          'User';
      _branchName = prefs.getString('branchName') ?? '';
      _branchIpRange = prefs.getString('branchIp');
      _printerName = prefs.getString('bt_printer_name');
      _wifiPrinterIp = prefs.getString('printerIp');
    });

    await Future.wait<void>([
      _refreshBluetoothStatus(prefs: prefs),
      _refreshWifiPrinterStatus(prefs: prefs),
      _refreshLocationStatus(),
    ]);
  }

  void _openWifiPrinterSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WifiPrinterSettingsPage()),
    ).then((_) => _loadSettingsSummary());
  }

  Future<void> _refreshBluetoothStatus({SharedPreferences? prefs}) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    bool connected = false;
    try {
      final isEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (isEnabled) {
        connected = await PrintBluetoothThermal.connectionStatus.timeout(
          const Duration(seconds: 2),
          onTimeout: () => false,
        );
      }
    } catch (_) {
      connected = false;
    }

    if (!mounted) return;
    setState(() {
      _printerName = resolvedPrefs.getString('bt_printer_name');
      _isBluetoothConnected = connected;
      _isCheckingBluetooth = false;
    });
  }

  Future<void> _refreshWifiPrinterStatus({SharedPreferences? prefs}) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    String? deviceWifiIp;
    try {
      deviceWifiIp = await NetworkInfo().getWifiIP().timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
    } catch (_) {
      deviceWifiIp = null;
    }

    final savedPrinterIp = (resolvedPrefs.getString('printerIp') ?? '').trim();
    final savedBranchIpRange = (resolvedPrefs.getString('branchIp') ?? '').trim();
    final currentWifiIp = (deviceWifiIp ?? '').trim();

    final connectedByRange =
        savedBranchIpRange.isNotEmpty &&
        currentWifiIp.isNotEmpty &&
        _isIpInRange(currentWifiIp, savedBranchIpRange);
    final connectedBySubnet =
        savedPrinterIp.isNotEmpty &&
        currentWifiIp.isNotEmpty &&
        _isSameSubnet(currentWifiIp, savedPrinterIp);

    if (!mounted) return;
    setState(() {
      _wifiPrinterIp = savedPrinterIp.isNotEmpty ? savedPrinterIp : null;
      _branchIpRange = savedBranchIpRange.isNotEmpty ? savedBranchIpRange : null;
      _deviceWifiIp = currentWifiIp.isNotEmpty ? currentWifiIp : null;
      _isWifiPrinterConnected = connectedByRange || connectedBySubnet;
      _isCheckingWifiPrinter = false;
    });
  }

  Future<void> _refreshLocationStatus() async {
    bool serviceEnabled = false;
    bool hasPermission = false;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      hasPermission =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      serviceEnabled = false;
      hasPermission = false;
    }

    if (!mounted) return;
    setState(() {
      _isLocationEnabled = serviceEnabled;
      _hasLocationPermission = hasPermission;
      _isCheckingLocation = false;
    });
  }

  Future<void> _openPrinterSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BluetoothPrinterSettingsPage(),
      ),
    );
    await _loadSettingsSummary();
  }

  Future<void> _handleLocationCardTap() async {
    if (_isCheckingLocation) return;

    try {
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      }

      if (!serviceEnabled) {
        await _refreshLocationStatus();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}

    await _refreshLocationStatus();
  }

  Future<void> _logout() async {
    await AuthService.logout();
  }

  bool _isSameSubnet(String ip1, String ip2) {
    final a = ip1.split('.');
    final b = ip2.split('.');
    if (a.length != 4 || b.length != 4) return false;
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  bool _isIpInRange(String ip, String range) {
    final parts = range.split('/').first.trim().split('.');
    final ipParts = ip.split('.');
    if (parts.length != 4 || ipParts.length != 4) return false;
    return parts[0] == ipParts[0] &&
        parts[1] == ipParts[1] &&
        parts[2] == ipParts[2];
  }

  Widget _statusCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLoading,
    required bool isConnected,
    VoidCallback? onTap,
  }) {
    final color = isConnected ? const Color(0xFF16A34A) : Colors.red;
    final statusText = isConnected ? 'Connected' : 'Not connected';

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 4),
            isLoading
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    statusText,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
          ],
        ),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationConnected = _isLocationEnabled && _hasLocationPermission;
    final locationSubtitle = _isLocationEnabled
        ? (_hasLocationPermission
              ? 'Location service and permission enabled'
              : 'Location is on, permission needed')
        : 'Location service is disabled';

    final wifiSubtitle = (_wifiPrinterIp != null)
        ? 'Connected: $_wifiPrinterIp'
        : 'No Wi-Fi printer configured';

    final btSubtitle = (_printerName != null && _printerName!.isNotEmpty)
        ? 'Saved: $_printerName'
        : 'No Bluetooth printer configured';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSettingsSummary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: Text(_username),
                subtitle: _branchName.isNotEmpty ? Text(_branchName) : null,
              ),
            ),
            const SizedBox(height: 12),
            _statusCard(
              title: 'Bluetooth Printer',
              subtitle: btSubtitle,
              icon: Icons.bluetooth,
              isLoading: _isCheckingBluetooth,
              isConnected: _isBluetoothConnected,
              onTap: _openPrinterSettings,
            ),
            _statusCard(
              title: 'Wi-Fi Printer',
              subtitle: wifiSubtitle,
              icon: Icons.wifi,
              isLoading: _isCheckingWifiPrinter,
              isConnected: _isWifiPrinterConnected,
              onTap: _openWifiPrinterSettings,
            ),
            _statusCard(
              title: 'Location',
              subtitle: locationSubtitle,
              icon: Icons.location_on_outlined,
              isLoading: _isCheckingLocation,
              isConnected: locationConnected,
              onTap: _handleLocationCardTap,
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout_outlined, color: Colors.red),
                title: const Text('Logout'),
                onTap: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WifiPrinterSettingsPage extends StatefulWidget {
  const WifiPrinterSettingsPage({super.key});

  @override
  State<WifiPrinterSettingsPage> createState() => _WifiPrinterSettingsPageState();
}

class _WifiPrinterSettingsPageState extends State<WifiPrinterSettingsPage> {
  bool _isChecking = true;
  bool _isWifiPrintingEnabled = true;
  bool _isBillingEnabled = true;
  bool _isKotEnabled = true;

  String? _deviceIp;
  String? _printerIp;
  String? _branchIpRange;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final info = NetworkInfo();
    
    String? deviceIp;
    try {
      deviceIp = await info.getWifiIP().timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}

    final printerIp = prefs.getString('printerIp');
    final branchIpRange = prefs.getString('branchIp');

    bool isConnected = false;
    if (deviceIp != null && deviceIp.isNotEmpty) {
      if (printerIp != null && printerIp.isNotEmpty && _isSameSubnet(deviceIp, printerIp)) {
        isConnected = true;
      } else if (branchIpRange != null && branchIpRange.isNotEmpty && _isIpInRange(deviceIp, branchIpRange)) {
        isConnected = true;
      }
    }

    if (!mounted) return;
    setState(() {
      _deviceIp = deviceIp;
      _printerIp = printerIp;
      _branchIpRange = branchIpRange;
      _isConnected = isConnected;
      _isWifiPrintingEnabled = prefs.getBool('wifi_printing_enabled') ?? true;
      _isBillingEnabled = prefs.getBool('wifi_billing_enabled') ?? true;
      _isKotEnabled = prefs.getBool('wifi_kot_enabled') ?? true;
      _isChecking = false;
    });
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
    return parts[0] == ipParts[0] && parts[1] == ipParts[1] && parts[2] == ipParts[2];
  }

  Future<void> _updateSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      if (key == 'wifi_printing_enabled') _isWifiPrintingEnabled = value;
      if (key == 'wifi_billing_enabled') _isBillingEnabled = value;
      if (key == 'wifi_kot_enabled') _isKotEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Wi-Fi Printer Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Master Status Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isConnected ? primaryColor.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isConnected ? Icons.wifi : Icons.wifi_off,
                              color: _isConnected ? primaryColor : Colors.red,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isConnected ? 'Connected' : 'Not Connected',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  _isConnected ? 'Printer is reachable' : 'Printer not found in network',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wi-Fi Printing',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              Text('Master control for all Wi-Fi printers', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          Switch(
                            value: _isWifiPrintingEnabled,
                            onChanged: (val) => _updateSetting('wifi_printing_enabled', val),
                            activeColor: primaryColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // IP Configuration Details
                const Text(
                  'NETWORK CONFIGURATION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow(Icons.phone_android, 'Device IP', _deviceIp ?? 'Disconnected'),
                      const Divider(height: 32),
                      _buildInfoRow(Icons.print, 'Printer IP', _printerIp ?? 'Not Configured'),
                      if (_branchIpRange != null) ...[
                        const Divider(height: 32),
                        _buildInfoRow(Icons.lan, 'Branch Range', _branchIpRange!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Controls
                if (_isWifiPrintingEnabled) ...[
                  const Text(
                    'PRINT CONTROLS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Billing Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Automatic printing for completed bills'),
                          value: _isBillingEnabled,
                          onChanged: (val) => _updateSetting('wifi_billing_enabled', val),
                          activeColor: primaryColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text('KOT Printing', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Send orders to kitchen printer'),
                          value: _isKotEnabled,
                          onChanged: (val) => _updateSetting('wifi_kot_enabled', val),
                          activeColor: primaryColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                Center(
                  child: TextButton.icon(
                    onPressed: _loadSettings,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Network Status'),
                    style: TextButton.styleFrom(foregroundColor: primaryColor),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[400]),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}

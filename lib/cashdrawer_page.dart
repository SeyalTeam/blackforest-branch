import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'printer/unified_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

class CashDrawerPage extends StatefulWidget {
  final String? printerIp;

  const CashDrawerPage({Key? key, this.printerIp}) : super(key: key);

  @override
  _CashDrawerPageState createState() => _CashDrawerPageState();
}

class _CashDrawerPageState extends State<CashDrawerPage> {
  bool _isLoading = true;
  bool _isAuthorized = false;

  @override
  void initState() {
    super.initState();
    _checkAuthorization();
  }

  Future<void> _checkAuthorization() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString('branchId');
      final token = prefs.getString('token');

      if (branchId == null || token == null) {
        throw Exception("Not logged in properly.");
      }

      final url = '${ApiConfig.baseUrl}/branches/$branchId';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isAuthorized = data['isCashDrawerEnabled'] == true;
        });
      } else {
        throw Exception("Failed to fetch branch data.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openCashDrawer() async {
    setState(() => _isLoading = true);
    try {
      final profile = await CapabilityProfile.load();
      final prefs = await SharedPreferences.getInstance();
      final pIp = widget.printerIp ?? prefs.getString('printer_ip');

      final printer = await UnifiedPrinter.connect(
        printerIp: pIp,
        candidatePorts: [9100],
        paperSize: PaperSize.mm80,
        profile: profile,
      );

      if (printer != null) {
        // Command to open cash drawer
        printer.rawBytes([27, 112, 0, 25, 250]);
        await printer.disconnectAndPrint();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cash drawer open command sent!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to connect to printer')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cash Drawer')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isAuthorized
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'Access Denied. Manager approval required to open cash drawer.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Center(
              child: ElevatedButton.icon(
                onPressed: _openCashDrawer,
                icon: const Icon(Icons.account_balance_wallet, size: 48),
                label: const Text(
                  'OPEN CASHDRAWER',
                  style: TextStyle(fontSize: 24),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 24,
                  ),
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
    );
  }
}

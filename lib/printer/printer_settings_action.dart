import 'package:branch/printer/bluetooth_printer_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterSettingsAction extends StatefulWidget {
  const PrinterSettingsAction({super.key});

  @override
  State<PrinterSettingsAction> createState() => _PrinterSettingsActionState();
}

class _PrinterSettingsActionState extends State<PrinterSettingsAction> {
  String? _printerName;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerName = (prefs.getString('bt_printer_name') ?? '').trim();
    if (!mounted) return;
    setState(() {
      _printerName = printerName.isEmpty ? null : printerName;
    });
  }

  Future<void> _openPrinterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BluetoothPrinterSettingsPage()),
    );
    await _loadSavedPrinter();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _printerName == null
          ? 'Connect printer'
          : 'Printer: $_printerName',
      child: Stack(
        children: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: _openPrinterSettings,
          ),
          if (_printerName != null)
            Positioned(
              right: 11,
              top: 11,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

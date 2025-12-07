import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart'; // Added for camera permission handling

import 'package:branch/categories_page.dart';
import 'package:branch/cart_page.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/return_provider.dart'; // Re-adding ReturnProvider import
import 'package:branch/home.dart';
import 'package:branch/billsheet.dart';
import 'package:branch/editbill.dart';

/// ✅ UPDATED ENUM — added stock & returnorder
enum PageType {
  home,
  billing,
  cart,
  billsheet,
  editbill,
  stock,
  returnorder,
  expense, // NEW
}

class CommonScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final Function(String)? onScanCallback;
  final PageType pageType;

  const CommonScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onScanCallback,
    required this.pageType,
  });

  @override
  _CommonScaffoldState createState() => _CommonScaffoldState();
}

class _CommonScaffoldState extends State<CommonScaffold> {
  Timer? _inactivityTimer;
  String _username = 'Menu';

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _resetTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? 'Menu';
    });
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(hours: 7), _logout);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.grey[800]),
    );
  }

  Future<void> _scanBarcode() async {
    _resetTimer();
    if (!io.Platform.isAndroid && !io.Platform.isIOS) {
      _showMessage("Scanner not supported");
      return;
    }

    // Check and request camera permission
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (status.isGranted) {
      final result = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => const ScannerDialog(),
        barrierLabel: "Dismiss",
        transitionBuilder: (context, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );

      if (result != null) {
        if (widget.onScanCallback != null) {
          widget.onScanCallback!(result);
        } else {
          _showMessage("Scanned: $result"); // Default feedback if no callback
        }
      } else {
        _showMessage("Scan cancelled");
      }
    } else {
      _showMessage("Camera permission denied. Please enable it in settings.");
      openAppSettings(); // Prompt user to open settings if denied
    }
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) => child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _resetTimer,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
          ),
          iconTheme: const IconThemeData(color: Colors.black),
          actionsIconTheme: const IconThemeData(color: Colors.black),
          actions: [
            if (widget.pageType == PageType.stock)
              Consumer<StockProvider>(
                builder: (_, sp, __) {
                  final int count = sp.selected.values.where((v) => v == true).length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {
                          _resetTimer();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChangeNotifierProvider.value(
                                value: sp,
                                child: const CartPage(isStockOrder: true),
                              ),
                            ),
                          );
                        },
                      ),
                      if (count > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                                color: Colors.blue, borderRadius: BorderRadius.circular(10)), // Blue badge for stock? Or Keep Red. Let's keep Red but maybe distinct.
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            else if (widget.pageType == PageType.returnorder)
              Consumer<ReturnProvider>(
                builder: (_, rp, __) {
                  final int count = rp.returnItems.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {
                          _resetTimer();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CartPage(isReturnOrder: true),
                            ),
                          );
                        },
                      ),
                      if (count > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            else
              Consumer<CartProvider>(
                builder: (_, cartProvider, __) {
                  final int count = cartProvider.cartItems.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {
                          _resetTimer();
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const CartPage()));
                        },
                      ),
                      if (count > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                                color: Colors.red, borderRadius: BorderRadius.circular(10)),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),

        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.black),
                child: Text(_username,
                    style: const TextStyle(color: Colors.white, fontSize: 24)),
              ),
              ListTile(
                leading: const Icon(Icons.receipt, color: Colors.black),
                title: const Text("Billing"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const CategoriesPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.black),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
            ],
          ),
        ),

        body: widget.body,

        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey, width: 1))),
          child: BottomAppBar(
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                /// HOME
                _buildNavItem(
                  icon: Icons.home_outlined,
                  label: "Home",
                  page: const HomePage(),
                  type: PageType.home,
                ),

                /// BILLING
                _buildNavItem(
                  icon: Icons.receipt_long_outlined,
                  label: "Billing",
                  page: const CategoriesPage(),
                  type: PageType.billing,
                ),

                /// SCAN
                GestureDetector(
                  onTap: _scanBarcode,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.qr_code_scanner_outlined,
                          color: Colors.black, size: 32),
                      Text("Scan", style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),

                /// BILLSHEET
                _buildNavItem(
                  icon: Icons.description_outlined,
                  label: "BillSheet",
                  page: const BillSheetPage(),
                  type: PageType.billsheet,
                ),

                /// EDIT BILL
                _buildNavItem(
                  icon: Icons.edit_outlined,
                  label: "Edit Bill",
                  page: const EditBillPage(),
                  type: PageType.editbill,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required Widget page,
    required PageType type,
  }) {
    return GestureDetector(
      onTap: () {
        _resetTimer();
        Navigator.pushAndRemoveUntil(
          context,
          _createRoute(page),
              (route) => false,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 32,
              color: widget.pageType == type ? Colors.blue : Colors.black),
          Text(
            label,
            style: TextStyle(
              color: widget.pageType == type ? Colors.blue : Colors.black,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}


/// =========================
/// BARCODE SCANNER DIALOG
/// =========================
class ScannerDialog extends StatefulWidget {
  const ScannerDialog({super.key});
  @override
  _ScannerDialogState createState() => _ScannerDialogState();
}

class _ScannerDialogState extends State<ScannerDialog> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates, // Added to prevent duplicate scans
    // You can add torchEnabled: true if needed for low light
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR/Barcode")), // Updated title to reflect both
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              return;
            }
          }
        },
      ),
    );
  }
}
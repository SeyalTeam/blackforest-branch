import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart'; // Added for camera permission handling

import 'package:branch/api_config.dart';
import 'package:branch/categories_page.dart';
import 'package:branch/cart_page.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/instock_provider.dart';
import 'package:branch/return_provider.dart'; // Re-adding ReturnProvider import
import 'package:branch/home.dart';
import 'package:branch/profile_page.dart';
import 'package:branch/billsheet.dart';
import 'package:branch/chat_page.dart';
import 'package:branch/auth_service.dart'; // ADDED
import 'package:branch/stock_alert_helper.dart';
import 'package:branch/printer/bluetooth_printer_settings_page.dart';

/// ✅ UPDATED ENUM — added stock & returnorder
enum PageType {
  home,
  billing,
  cart,
  billsheet,
  editbill,
  stock,
  stockstatus,
  returnorder,
  expense,
  instock, // NEW
  table, // NEW
  dealerBilling, // NEW
  cake, // NEW
  employee,
  profile,
  chat,
}

enum _StockAlertDialogAction { acknowledge, updateOutOfStock }

class CommonScaffold extends StatefulWidget {
  static final ValueNotifier<int> unreadChatNotifier = ValueNotifier<int>(0);

  static void setUnreadChatCount(int count) {
    unreadChatNotifier.value = count;
  }

  final String title;
  final Widget body;
  final Function(String)? onScanCallback;
  final PageType pageType;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom; // NEW
  final bool showAppBar;
  final bool hideBottomNavigationBar;

  const CommonScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onScanCallback,
    required this.pageType,
    this.actions,
    this.bottom, // NEW
    this.showAppBar = true,
    this.hideBottomNavigationBar = false,
  });

  @override
  _CommonScaffoldState createState() => _CommonScaffoldState();
}

class _CommonScaffoldState extends State<CommonScaffold> {
  Timer? _inactivityTimer;
  Timer? _stockAlertTimer;
  Timer? _chatUnreadTimer;
  static String? _cachedChatThreadId;
  String _username = 'User';
  String? _photoUrl;
  String _role = '';
  String _branchName = '';
  String? _stockAlertToken;
  String? _stockAlertBranchId;
  bool _isCheckingStockAlerts = false;
  bool _isStockAlertDialogOpen = false;
  final Set<String> _seenStockAlertIds = {};

  bool _cashDrawerEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _resetTimer();
    _initStockAlerts();
    _initChatUnreadCheck();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _stockAlertTimer?.cancel();
    _chatUnreadTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ??
        prefs.getString('employee_name') ??
        prefs.getString('username') ??
        prefs.getString('email')?.split('@').first ??
        'User';
    final role = prefs.getString('role') ?? '';
    final branchName = prefs.getString('branchName') ?? '';
    final cashDrawerEnabled = prefs.getBool('cash_drawer_enabled') ?? true;
    final photoUrl = prefs.getString('employee_photo_url');
    if (mounted) {
      setState(() {
        _username = (name.isEmpty || name == 'Menu') ? 'User' : name;
        _role = role;
        _branchName = branchName;
        _cashDrawerEnabled = cashDrawerEnabled;
        _photoUrl = photoUrl;
      });
    }

  }

  Future<void> _initStockAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    _stockAlertToken = prefs.getString('token');
    _stockAlertBranchId = prefs.getString('branchId');

    if ((_stockAlertToken?.isEmpty ?? true) ||
        (_stockAlertBranchId?.isEmpty ?? true)) {
      return;
    }

    await _checkStockAlerts();
    _stockAlertTimer?.cancel();
    _stockAlertTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStockAlerts();
    });
  }

  Future<void> _initChatUnreadCheck() async {
    if (widget.pageType == PageType.chat) {
      CommonScaffold.setUnreadChatCount(0);
      return;
    }
    await _checkUnreadChatMessages();
    _chatUnreadTimer?.cancel();
    _chatUnreadTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && widget.pageType != PageType.chat) {
        _checkUnreadChatMessages();
      }
    });
  }

  Future<void> _checkUnreadChatMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token')?.trim();
      if (token == null || token.isEmpty) return;

      var userId = prefs.getString('user_id')?.trim();
      if (userId == null || userId.isEmpty) {
        final meRes = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/users/me?depth=0'),
          headers: ApiConfig.getHeaders(token),
        );
        if (meRes.statusCode == 200) {
          final decoded = jsonDecode(meRes.body);
          final rawUser = decoded is Map ? (decoded['user'] ?? decoded) : null;
          if (rawUser is Map) {
            userId = (rawUser['id'] ?? rawUser['_id'])?.toString().trim();
            if (userId != null && userId.isNotEmpty) {
              await prefs.setString('user_id', userId);
            }
          }
        }
      }

      if (userId == null || userId.isEmpty) return;

      if (_cachedChatThreadId == null || _cachedChatThreadId!.isEmpty) {
        final threadRes = await http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/message-threads?limit=1&depth=0&where[staffUser][equals]=$userId',
          ),
          headers: ApiConfig.getHeaders(token),
        );
        if (threadRes.statusCode == 200) {
          final data = jsonDecode(threadRes.body);
          final docs = data['docs'] as List?;
          if (docs != null && docs.isNotEmpty) {
            _cachedChatThreadId =
                (docs.first['id'] ?? docs.first['_id'])?.toString().trim();
          }
        }
      }

      final queryParams = <String, String>{
        'limit': '100',
        'depth': '0',
        'where[recipientAudience][equals]': 'staff',
        'where[status][not_equals]': 'read',
      };
      if (_cachedChatThreadId != null && _cachedChatThreadId!.isNotEmpty) {
        queryParams['where[thread][equals]'] = _cachedChatThreadId!;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/message-receipts').replace(
        queryParameters: queryParams,
      );

      final receiptsRes = await http.get(
        uri,
        headers: ApiConfig.getHeaders(token),
      );

      if (receiptsRes.statusCode == 200) {
        final data = jsonDecode(receiptsRes.body);
        final count =
            data['totalDocs'] as int? ?? (data['docs'] as List?)?.length ?? 0;
        if (mounted && widget.pageType != PageType.chat) {
          CommonScaffold.setUnreadChatCount(count);
        }
      }
    } catch (e) {
      debugPrint('Error checking unread chat messages: $e');
    }
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(hours: 7), _logout);
  }

  Future<void> _logout() async {
    await AuthService.logout();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.grey[800]),
    );
  }

  Future<void> _checkStockAlerts() async {
    if (!mounted || _isCheckingStockAlerts || _isStockAlertDialogOpen) return;

    final token = _stockAlertToken;
    final branchId = _stockAlertBranchId;
    if (token == null || token.isEmpty || branchId == null || branchId.isEmpty)
      return;

    _isCheckingStockAlerts = true;
    try {
      final alerts = await StockAlertHelper.fetchOpenAlerts(
        token: token,
        branchId: branchId,
      );

      Map<String, dynamic>? nextAlert;
      for (final alert in alerts) {
        final alertId = (alert['id'] ?? alert['_id'])?.toString().trim() ?? '';
        if (alertId.isEmpty || _seenStockAlertIds.contains(alertId)) continue;
        nextAlert = alert;
        _seenStockAlertIds.add(alertId);
        break;
      }

      if (nextAlert != null) {
        await _showStockAlertDialog(nextAlert);
      }
    } catch (_error) {
      // Ignore transient polling errors to avoid disrupting cashier flow.
    } finally {
      _isCheckingStockAlerts = false;
    }
  }

  Future<void> _showStockAlertDialog(Map<String, dynamic> alert) async {
    if (!mounted) return;

    final alertId = (alert['id'] ?? alert['_id'])?.toString().trim() ?? '';
    final productName = StockAlertHelper.productName(alert).toUpperCase();
    final requesterName = StockAlertHelper.requesterName(alert);

    _isStockAlertDialogOpen = true;
    try {
      final action = await showDialog<_StockAlertDialogAction>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8BDDD9).withValues(alpha: 0.35),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBE0E3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          size: 58,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Out Alert',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          color: Color(0xFF003D40),
                        ),
                      ),
                      const SizedBox(height: 20),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.45,
                            color: Color(0xFF2F6E70),
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: productName,
                              style: const TextStyle(
                                color: Color(0xFFC51E32),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const TextSpan(text: ' was reported '),
                            const TextSpan(
                              text: 'OUT OF STOCK',
                              style: TextStyle(
                                color: Color(0xFFC51E32),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const TextSpan(text: ' by '),
                            TextSpan(
                              text: requesterName,
                              style: const TextStyle(
                                color: Color(0xFF003D40),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Please check this product and update it as out of stock for your branch immediately to avoid new sales.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          color: Color(0xFF6F9898),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF006C67),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(
                              dialogContext,
                            ).pop(_StockAlertDialogAction.acknowledge);
                          },
                          child: const Text(
                            'Acknowledge',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD84315),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(
                              dialogContext,
                            ).pop(_StockAlertDialogAction.updateOutOfStock);
                          },
                          child: const Text(
                            'Update Out of Stock',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      final shouldUpdateOutOfStock =
          action == _StockAlertDialogAction.updateOutOfStock;

      if (shouldUpdateOutOfStock) {
        final token = _stockAlertToken;
        final branchId = _stockAlertBranchId;
        if (token == null ||
            token.isEmpty ||
            branchId == null ||
            branchId.isEmpty) {
          throw Exception('Unable to detect branch session for stock update.');
        }

        await StockAlertHelper.markProductOutOfStock(
          token: token,
          branchId: branchId,
          alert: alert,
        );
      }

      if (alertId.isNotEmpty && _stockAlertToken != null) {
        await StockAlertHelper.acknowledgeAlert(
          token: _stockAlertToken!,
          alertId: alertId,
        );
      }

      if (mounted) {
        _showMessage(
          shouldUpdateOutOfStock
              ? '$productName marked out of stock.'
              : '$productName alert received.',
        );
      }
    } catch (_error) {
      if (alertId.isNotEmpty) {
        _seenStockAlertIds.remove(alertId);
      }
    } finally {
      _isStockAlertDialogOpen = false;
    }
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
        transitionBuilder:
            (context, anim, __, child) =>
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
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: Colors.white,
                elevation: 1,
                title: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                iconTheme: const IconThemeData(color: Colors.black),
                actionsIconTheme: const IconThemeData(color: Colors.black),
                bottom: widget.bottom, // NEW
                actions: [
                  ...?widget.actions,
            if (widget.pageType == PageType.instock)
              Consumer<InstockProvider>(
                // NEW CONSUMER for Instock
                builder: (_, sp, __) {
                  final int count = sp.inStockQuery.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {
                          _resetTimer();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CartPage(isInstock: true),
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
                              color: const Color(0xFF11998e),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            else if (widget.pageType == PageType.stock)
              Consumer<StockProvider>(
                builder: (_, sp, __) {
                  final int count =
                      sp.selected.values.where((v) => v == true).length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {
                          _resetTimer();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => ChangeNotifierProvider.value(
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
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(10),
                            ), // Blue badge for stock? Or Keep Red. Let's keep Red but maybe distinct.
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
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
                              builder:
                                  (_) => const CartPage(isReturnOrder: true),
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
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            else if (widget.pageType == PageType.home)
              IconButton(
                icon: _photoUrl != null && _photoUrl!.isNotEmpty
                    ? CircleAvatar(
                        radius: 14,
                        backgroundImage: NetworkImage(_photoUrl!),
                      )
                    : const Icon(Icons.person_outline),
                onPressed: () {

                  _resetTimer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
              )
            else if (widget.pageType != PageType.stockstatus && widget.pageType != PageType.employee && widget.pageType != PageType.profile && widget.pageType != PageType.chat)
              Consumer<CartProvider>(
                builder: (_, cartProvider, __) {
                  final int count = cartProvider.cartItems.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {
                          _resetTimer();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CartPage()),
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
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        )
      : null,

        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 48, 18, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1C0908), Color(0xFF4A1A12)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFF8EFE6),
                      child: Text(
                        _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Color(0xFF2E170F),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (_role.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _role.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          if (_branchName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Branch: $_branchName',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              ListTile(
                leading: const Icon(Icons.print_outlined, color: Colors.black),
                title: const Text('Printer Settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BluetoothPrinterSettingsPage(),
                    ),
                  );
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.account_balance_wallet_outlined, color: Colors.black),
                title: const Text('Cash Drawer'),
                subtitle: const Text('Open automatically on print'),
                value: _cashDrawerEnabled,
                onChanged: (bool value) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('cash_drawer_enabled', value);
                  setState(() {
                    _cashDrawerEnabled = value;
                  });
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

        bottomNavigationBar:
            (widget.hideBottomNavigationBar ||
                    widget.pageType == PageType.stock ||
                    widget.pageType == PageType.chat)
                ? null
                : Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                    ),
                  ),
                  child: BottomAppBar(
                    color: Colors.white,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        /// HOME
                        _buildNavItem(
                          icon: Icons.home_rounded,
                          label: "Home",
                          page: const HomePage(),
                          type: PageType.home,
                        ),

                        /// BILLING
                        _buildNavItem(
                          icon: Icons.receipt_long_rounded,
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
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                color: Color(0xFF64748B),
                                size: 32,
                              ),
                              Text(
                                "Scan",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        /// CHAT
                        ValueListenableBuilder<int>(
                          valueListenable: CommonScaffold.unreadChatNotifier,
                          builder: (context, unreadCount, _) {
                            return _buildNavItem(
                              icon: Icons.forum_rounded,
                              label: "Chat",
                              page: const ChatPage(),
                              type: PageType.chat,
                              badgeCount: unreadCount,
                            );
                          },
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
    int badgeCount = 0,
  }) {
    final bool isSelected = widget.pageType == type;
    final Color itemColor =
        isSelected ? const Color(0xFF4A1A12) : const Color(0xFF64748B);
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
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                icon,
                size: 32,
                color: itemColor,
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -6,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            label,
            style: TextStyle(
              color: itemColor,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
    detectionSpeed:
        DetectionSpeed.noDuplicates, // Added to prevent duplicate scans
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
      appBar: AppBar(
        title: const Text("Scan QR/Barcode"),
      ), // Updated title to reflect both
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

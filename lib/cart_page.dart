import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/categories_page.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  String? _branchId;
  String? _branchName;
  String? _branchGst;
  String? _branchMobile;
  String? _companyName;
  String? _userRole;
  bool _addCustomerDetails = false;
  String? _selectedPaymentMethod;
  bool _isBillingInProgress = false; // Prevent duplicate bill taps

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // -------------------------
  // ---------- NETWORK / DATA HELPERS (UNCHANGED LOGIC) ----------
  // -------------------------

  Future<void> _fetchUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/users/me?depth=2'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final user = data['user'] ?? data;
        _userRole = user['role'];

        if (user['role'] == 'branch' && user['branch'] != null) {
          _branchId = (user['branch'] is Map) ? user['branch']['id'] : user['branch'];
          _branchName = (user['branch'] is Map) ? user['branch']['name'] : null;
          await _fetchBranchDetails(token, _branchId!);
        } else if (user['role'] == 'waiter') {
          await _fetchWaiterBranch(token);
        }

        setState(() {});
        Provider.of<CartProvider>(context, listen: false).setBranchId(_branchId);
      }
    } catch (_) {}
  }

  Future<void> _fetchBranchDetails(String token, String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches/$branchId?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final branch = jsonDecode(response.body);
        _branchName = branch['name'] ?? _branchName;
        _branchGst = branch['gst'];
        _branchMobile = branch['phone'] ?? null;

        if (branch['company'] != null && branch['company'] is Map) {
          _companyName = branch['company']['name'];
        } else if (branch['company'] != null) {
          await _fetchCompanyDetails(token, branch['company'].toString());
        }

        final cartProvider = Provider.of<CartProvider>(context, listen: false);
        cartProvider.setPrinterDetails(
          branch['printerIp'],
          branch['printerPort'],
          branch['printerProtocol'],
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchCompanyDetails(String token, String companyId) async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/companies/$companyId?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final company = jsonDecode(response.body);
        _companyName = company['name'] ?? 'Unknown Company';
      }
    } catch (_) {}
  }

  Future<String?> _fetchDeviceIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      return ip?.trim();
    } catch (_) {
      return null;
    }
  }

  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  bool _isIpInRange(String deviceIp, String range) {
    final parts = range.split('-');
    if (parts.length != 2) return false;

    final startIp = _ipToInt(parts[0].trim());
    final endIp = _ipToInt(parts[1].trim());
    final device = _ipToInt(deviceIp);
    return device >= startIp && device <= endIp;
  }

  Future<void> _fetchWaiterBranch(String token) async {
    String? deviceIp = await _fetchDeviceIp();
    if (deviceIp == null) return;

    try {
      final allBranchesResponse = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (allBranchesResponse.statusCode == 200) {
        final branchesData = jsonDecode(allBranchesResponse.body);
        if (branchesData['docs'] != null && branchesData['docs'] is List) {
          for (var branch in branchesData['docs']) {
            String? bIpRange = branch['ipAddress']?.toString().trim();
            if (bIpRange != null) {
              if (bIpRange == deviceIp || _isIpInRange(deviceIp, bIpRange)) {
                _branchId = branch['id'];
                _branchName = branch['name'];
                _branchGst = branch['gst'];
                _branchMobile = branch['phone'] ?? null;

                if (branch['company'] != null && branch['company'] is Map) {
                  _companyName = branch['company']['name'];
                } else if (branch['company'] != null) {
                  await _fetchCompanyDetails(token, branch['company'].toString());
                }

                final cartProvider = Provider.of<CartProvider>(context, listen: false);
                cartProvider.setPrinterDetails(
                  branch['printerIp'],
                  branch['printerPort'],
                  branch['printerProtocol'],
                );
                break;
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handleScan(String scanResult) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No token found. Please login again.')),
        );
        return;
      }

      final response = await http.get(
        Uri.parse(
            'https://admin.theblackforestcakes.com/api/products?where[upc][equals]=$scanResult&limit=1&depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> products = data['docs'] ?? [];
        if (products.isNotEmpty) {
          final product = products[0];
          final cartProvider = Provider.of<CartProvider>(context, listen: false);
          double price = product['defaultPriceDetails']?['price']?.toDouble() ?? 0.0;

          if (_branchId != null && product['branchOverrides'] != null) {
            for (var override in product['branchOverrides']) {
              var branch = override['branch'];
              String branchOid = branch is Map ? branch[r'$oid'] ?? branch['id'] ?? '' : branch ?? '';
              if (branchOid == _branchId) {
                price = override['price']?.toDouble() ?? price;
                break;
              }
            }
          }

          final item = CartItem.fromProduct(product, 1, branchPrice: price);
          cartProvider.addOrUpdateItem(item);
          final newQty = cartProvider.cartItems.firstWhere((i) => i.id == item.id).quantity;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${product['name']} added/updated (Qty: $newQty)')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product not found')),
          );
        }
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error: Check your internet')),
      );
    }
  }

  // -------------------------
  // ---------- BILLING FLOW (UNCHANGED LOGIC) ----------
  // -------------------------

  Future<void> _submitBilling() async {
    if (_isBillingInProgress) return; // lock
    setState(() => _isBillingInProgress = true);

    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    if (cartProvider.cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      setState(() => _isBillingInProgress = false);
      return;
    }

    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method')),
      );
      setState(() => _isBillingInProgress = false);
      return;
    }

    Map<String, dynamic>? customerDetails;
    if (_addCustomerDetails) {
      customerDetails = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final nameCtrl = TextEditingController();
          final phoneCtrl = TextEditingController();

          return Dialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TITLE
                  Center(
                    child: Text(
                      "Customer Details",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // PHONE FIELD
                  Text(
                    "Phone Number",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFF0A84FF).withOpacity(0.5)),
                    ),
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        border: InputBorder.none,
                        hintText: "Enter phone number",
                        hintStyle: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // NAME FIELD
                  Text(
                    "Customer Name",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFF0A84FF).withOpacity(0.5)),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        border: InputBorder.none,
                        hintText: "Enter customer name",
                        hintStyle: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // BUTTON ROW
                  Row(
                    children: [
                      // CANCEL
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("Cancel"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // SUBMIT
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context, {
                              'name': nameCtrl.text,
                              'phone': phoneCtrl.text,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A84FF),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            "Submit",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      );

      if (customerDetails == null) {
        setState(() => _isBillingInProgress = false);
        return;
      }
    } else {
      customerDetails = {};
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        setState(() => _isBillingInProgress = false);
        return;
      }

      final billingData = {
        'items': cartProvider.cartItems
            .map((item) => ({
          'product': item.id,
          'name': item.name,
          'quantity': item.quantity,
          'unitPrice': item.price,
          'subtotal': item.price * item.quantity,
          'branchOverride': _branchId != null,
        }))
            .toList(),
        'totalAmount': cartProvider.total,
        'branch': _branchId,
        'customerDetails': {'phone': customerDetails['phone'] ?? '', 'name': customerDetails['name'] ?? ''},
        'paymentMethod': _selectedPaymentMethod,
        'notes': '',
        'status': 'completed',
      };

      final response = await http.post(
        Uri.parse('https://admin.theblackforestcakes.com/api/billings'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(billingData),
      );

      final billingResponse = jsonDecode(response.body);
      print('📦 BILL RESPONSE: $billingResponse');

      if (response.statusCode == 201) {
        await _printReceipt(cartProvider, billingResponse, customerDetails, _selectedPaymentMethod!);
        cartProvider.clearCart();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Billing submitted successfully')));
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const CategoriesPage()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${response.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isBillingInProgress = false);
    }
  }

  Future<void> _printReceipt(
      CartProvider cartProvider,
      Map<String, dynamic> billingResponse,
      Map<String, dynamic> customerDetails,
      String paymentMethod,
      ) async {
    final printerIp = cartProvider.printerIp;
    final printerPort = cartProvider.printerPort;
    final printerProtocol = cartProvider.printerProtocol;

    if (printerIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No printer configured for this branch')),
      );
      return;
    }

    if (printerProtocol == null || printerProtocol != 'esc_pos') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unsupported printer protocol: $printerProtocol')),
      );
      return;
    }

    // Fetch waiter name
    String? waiterName;
    try {
      if (billingResponse['createdBy'] != null) {
        String userId = billingResponse['createdBy'] is Map ? billingResponse['createdBy'][r'$oid'] ?? billingResponse['createdBy']['id'] : billingResponse['createdBy'];
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null && userId.isNotEmpty) {
          final userResponse = await http.get(
            Uri.parse('https://admin.theblackforestcakes.com/api/users/$userId?depth=1'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (userResponse.statusCode == 200) {
            final user = jsonDecode(userResponse.body);
            waiterName = user['name'] ?? user['username'] ?? 'Unknown';
          }
        }
      }
    } catch (_) {
      waiterName = 'Unknown';
    }

    try {
      const PaperSize paper = PaperSize.mm80;
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(paper, profile);

      final PosPrintResult res = await printer.connect(printerIp, port: printerPort);

      if (res == PosPrintResult.success) {
        String invoiceNumber = billingResponse['invoiceNumber'] ?? billingResponse['doc']?['invoiceNumber'] ?? 'N/A';
        // Extract numeric part from invoice like CHI-YYYYMMDD-017 → 017
        final regex = RegExp(r'^[A-Z]+-\d{8}-(\d+)$');
        final match = regex.firstMatch(invoiceNumber);
        String billNo = match != null ? match.group(1)! : invoiceNumber;
        billNo = billNo.padLeft(3, '0');

        DateTime now = DateTime.now();
        String date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        int hour = now.hour;
        String ampm = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12;
        if (hour == 0) hour = 12;
        String time = '$hour:${now.minute.toString().padLeft(2, '0')}$ampm';
        String dateStr = '$date $time';

        printer.text(_companyName ?? 'BLACK FOREST CAKES', styles: const PosStyles(align: PosAlign.center, bold: true));
        printer.text('Branch: ${_branchName ?? _branchId}', styles: const PosStyles(align: PosAlign.center));
        printer.text('GST: ${_branchGst ?? 'N/A'}', styles: const PosStyles(align: PosAlign.center));
        printer.text('Mobile: ${_branchMobile ?? 'N/A'}', styles: const PosStyles(align: PosAlign.center));
        printer.hr(ch: '=');
        printer.row([
          PosColumn(
            text: 'Date: $dateStr',
            width: 6,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'BILL NO - $billNo',
            width: 6,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
        if (waiterName != null) {
          printer.text('Assigned by: $waiterName', styles: const PosStyles(align: PosAlign.center));
        }
        printer.hr(ch: '=');
        printer.row([
          PosColumn(text: 'Item', width: 5, styles: const PosStyles(bold: true)),
          PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
          PosColumn(text: 'Price', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
          PosColumn(text: 'Amount', width: 3, styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]);
        printer.hr(ch: '-');

        for (var item in cartProvider.cartItems) {
          final qtyStr = item.quantity % 1 == 0 ? item.quantity.toStringAsFixed(0) : item.quantity.toStringAsFixed(2);
          printer.row([
            PosColumn(text: item.name, width: 5),
            PosColumn(text: qtyStr, width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: item.price.toStringAsFixed(2), width: 2, styles: const PosStyles(align: PosAlign.right)),
            PosColumn(
                text: (item.price * item.quantity).toStringAsFixed(2),
                width: 3,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
        }

        printer.hr(ch: '-');
        printer.row([
          PosColumn(text: 'TOTAL RS', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(
              text: cartProvider.total.toStringAsFixed(2),
              width: 4,
              styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        printer.text('Paid by: ${paymentMethod.toUpperCase()}');

        if (customerDetails['name']?.isNotEmpty == true || customerDetails['phone']?.isNotEmpty == true) {
          printer.hr();
          printer.text('Customer: ${customerDetails['name'] ?? ''}');
          printer.text('Phone: ${customerDetails['phone'] ?? ''}');
        }

        printer.hr(ch: '=');
        printer.text('Thank you! Visit Again', styles: const PosStyles(align: PosAlign.center));
        printer.feed(2);
        printer.cut();
        printer.disconnect();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt printed successfully')),
        );
      } else {
        throw Exception(res.msg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  // -------------------------
  // ---------- UI (REDESIGNED) ----------
  // -------------------------

  // Colors for Carbon Black theme
  final Color _bg = const Color(0xFF121212);
  final Color _card = const Color(0xFF1E1E1E);
  final Color _muted = const Color(0xFF9E9E9E);
  final Color _accent = const Color(0xFF0A84FF); // electric blue accent
  final Color _chipBg = const Color(0xFF19232E);

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 110, color: Colors.grey[700]),
          const SizedBox(height: 18),
          Text(
            'Your cart is empty',
            style: TextStyle(color: Colors.grey[300], fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Add items from categories to start billing',
            style: TextStyle(color: _muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentChips() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PaymentChip(
          label: 'Cash',
          icon: Icons.money,
          selected: _selectedPaymentMethod == 'cash',
          onTap: () => setState(() => _selectedPaymentMethod = 'cash'),
          accent: _accent,
          chipBg: _chipBg,
          width: 95, // increase width
        ),
        _PaymentChip(
          label: 'UPI',
          icon: Icons.qr_code,
          selected: _selectedPaymentMethod == 'upi',
          onTap: () => setState(() => _selectedPaymentMethod = 'upi'),
          accent: _accent,
          chipBg: _chipBg,
          width: 95,
        ),
        _PaymentChip(
          label: 'Card',
          icon: Icons.credit_card,
          selected: _selectedPaymentMethod == 'card',
          onTap: () => setState(() => _selectedPaymentMethod = 'card'),
          accent: _accent,
          chipBg: _chipBg,
          width: 95,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Cart',
      pageType: PageType.cart,
      onScanCallback: _handleScan,
      body: Container(
        color: _bg,
        child: Consumer<CartProvider>(
          builder: (context, cartProvider, child) {
            final items = cartProvider.cartItems;
            // Calculate total items as sum of quantities (assuming double, but display as int if whole)
            final totalQuantity = cartProvider.cartItems.fold<double>(0, (sum, item) => sum + item.quantity);
            final totalItemsDisplay = totalQuantity % 1 == 0 ? totalQuantity.toInt().toString() : totalQuantity.toStringAsFixed(2);

            return SafeArea(
              child: Stack(
                children: [
                  // Main content
                  Column(
                    children: [
                      // If empty show empty state else list
                      Expanded(
                        child: items.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 140),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _CartItemCard(
                              key: ValueKey('${item.id}_${item.quantity}'),
                              item: item,
                              cardColor: _card,
                              accent: _accent,
                              onRemove: () => cartProvider.removeItem(item.id),
                              onQuantityChange: (q) => cartProvider.updateQuantity(item.id, q),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  // Sticky bottom bar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.6), Colors.black.withOpacity(0.85)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.04))),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // UPDATED: Total with colors, space between amount and items, toggle switch on right
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Total: ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '₹${cartProvider.total.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 12), // Space between amount and items
                                  Text(
                                    totalItemsDisplay,
                                    style: TextStyle(
                                      color: Colors.yellow,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    ' Items',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _addCustomerDetails,
                                onChanged: (v) => setState(() => _addCustomerDetails = v),
                                activeColor: _accent,
                                inactiveThumbColor: Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Payment chips row (full width)
                          _buildPaymentChips(),
                          const SizedBox(height: 16),
                          // OK BILL button on separate row
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _isBillingInProgress ? null : _submitBilling,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isBillingInProgress ? Colors.grey : const Color(0xFF2EBF3B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 4,
                              ),
                              child: _isBillingInProgress
                                  ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Processing...', style: TextStyle(fontSize: 16)),
                                ],
                              )
                                  : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.receipt_long, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'OK BILL',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white, // FORCE WHITE TEXT
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// -------------------------
// ---------- SMALL WIDGETS ----------
// -------------------------

class _CartItemCard extends StatefulWidget {
  final CartItem item;
  final VoidCallback onRemove;
  final Function(double) onQuantityChange;
  final Color cardColor;
  final Color accent;

  const _CartItemCard({
    Key? key,
    required this.item,
    required this.onRemove,
    required this.onQuantityChange,
    required this.cardColor,
    required this.accent,
  }) : super(key: key);

  @override
  _CartItemCardState createState() => _CartItemCardState();
}

class _CartItemCardState extends State<_CartItemCard> {
  late TextEditingController _qtyController;
  late double _step;

  String _qtyDisplay(double qty) {
    if (qty % 1 == 0) return qty.toInt().toString();
    return qty.toStringAsFixed(2);
  }

  double _calculateStep(double qty) {
    if (qty == 0) return 0.25; // Default step
    int a = (qty * 100).round().abs();
    int b = 100;
    int g = _gcd(a, b);
    return g / 100.0;
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      int t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: _qtyDisplay(widget.item.quantity));
    _step = _calculateStep(widget.item.quantity);
  }

  @override
  void didUpdateWidget(covariant _CartItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.quantity != widget.item.quantity) {
      _qtyController.text = _qtyDisplay(widget.item.quantity);
      _step = _calculateStep(widget.item.quantity);
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 🟦 IMAGE → Tap to REMOVE
            GestureDetector(
              onTap: widget.onRemove,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: widget.item.imageUrl != null
                    ? CachedNetworkImage(
                  imageUrl: widget.item.imageUrl!,
                  width: 68,
                  height: 68,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => SizedBox(
                    width: 68,
                    height: 68,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.accent,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 68,
                    height: 68,
                    color: Colors.grey[800],
                    child: Icon(Icons.image_not_supported, color: Colors.grey[600]),
                  ),
                )
                    : Container(
                  width: 68,
                  height: 68,
                  color: Colors.grey[800],
                  child: Icon(Icons.image_not_supported, color: Colors.grey[600]),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 🟦 Name + Price + Subtotal
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${widget.item.price.toStringAsFixed(2)} each',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Subtotal: ₹${(widget.item.price * widget.item.quantity).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // 🟦 Quantity controls with input field
            Column(
              children: [
                _QuantityButton(
                  icon: Icons.add_circle_outline,
                  onTap: () => widget.onQuantityChange((widget.item.quantity + _step).clamp(0.0, double.infinity)),
                  accent: widget.accent,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (value) {
                        double newQty = double.tryParse(value) ?? widget.item.quantity;
                        newQty = newQty.clamp(0.0, double.infinity);
                        widget.onQuantityChange(newQty);
                        // Step will be updated in didUpdateWidget
                      },
                    ),
                  ),
                ),
                _QuantityButton(
                  icon: Icons.remove_circle_outline,
                  onTap: () => widget.onQuantityChange((widget.item.quantity - _step).clamp(0.0, double.infinity)),
                  accent: widget.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  const _QuantityButton({Key? key, required this.icon, required this.onTap, required this.accent}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Icon(icon, color: accent, size: 22),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final Color chipBg;
  final double width;

  const _PaymentChip({
    Key? key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.chipBg,
    required this.width,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width, // 🔥 FIXED WIDTH
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.18) : chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? accent : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? accent : Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/return_provider.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/instock_provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/categories_page.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:branch/home.dart';
import 'package:branch/login_page.dart';
import 'package:branch/api_config.dart';
import 'package:branch/printer/printer_settings_action.dart';
import 'package:branch/printer/unified_printer.dart';

class CartPage extends StatefulWidget {
  final bool isStockOrder;
  final bool isReturnOrder;
  final bool isInstock; // NEW param
  const CartPage({
    super.key,
    this.isStockOrder = false,
    this.isReturnOrder = false,
    this.isInstock = false,
  });

  @override
  _CartPageState createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  // ... (existing params)

  // Instock Internal UI
  Widget _buildInstockInternal() {
    return CommonScaffold(
      title: 'Instock Cart',
      pageType: PageType.instock,
      body: Container(
        color: _bg,
        child: Consumer<InstockProvider>(
          builder: (context, sp, child) {
            final items = sp.inStockQuery;

            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: items.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final id = items.keys.elementAt(index);
                              final qty = items[id] ?? 0;
                              final name = sp.productNames[id] ?? 'Unknown';
                              final price = sp.prices[id] ?? 0;

                              return _InstockCartItem(
                                key: ValueKey(id),
                                id: id,
                                name: name,
                                price: price,
                                quantity: qty,
                                onRemove: () => sp.updateInStock(id, 0),
                                onUpdate: (val) => sp.updateInStock(id, val),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _bg,
                      border: Border(
                        top: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF11998e),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: sp.isSubmitting || items.isEmpty
                            ? null
                            : () async {
                                await sp.submitInstock(context);
                                // The provider clears cart on success
                                if (sp.inStockQuery.isEmpty && mounted) {
                                  Navigator.pop(context);
                                }
                              },
                        child: sp.isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Confirm Instock",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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

  String? _branchId;
  String? _branchName;
  String? _branchGst;
  String? _branchMobile;
  String? _companyName;
  bool _addCustomerDetails = false;
  String? _selectedPaymentMethod;
  bool _isBillingInProgress = false; // Prevent duplicate bill taps

  @override
  void initState() {
    super.initState();
    if (!widget.isStockOrder && !widget.isReturnOrder) {
      _fetchUserData();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Access provider after context is available, but ensure it exists.
        // Since we wrapped it in navigation, it should be there.
        try {
          final sp = Provider.of<StockProvider>(context, listen: false);
          if (sp.deliveryDate == null) {
            final now = DateTime.now();
            final tomorrow = now.add(const Duration(days: 1));
            // Default: Tomorrow 9:00 AM
            sp.deliveryDate = DateTime(
              tomorrow.year,
              tomorrow.month,
              tomorrow.day,
              9,
              0,
            );
          }
        } catch (_) {
          // Fallback or ignore if provider not found (should not happen in stock mode)
        }
      });
    }
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
        Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final user = data['user'] ?? data;

        if (user['branch'] != null) {
          _branchId = (user['branch'] is Map)
              ? user['branch']['id']
              : user['branch'];
          _branchName = (user['branch'] is Map) ? user['branch']['name'] : null;
          await _fetchBranchDetails(token, _branchId!);
        } else if (user['role'] == 'waiter' || user['role'] == 'kitchen' || user['role'] == 'chef' || user['role'] == 'manager' || user['role'] == 'cashier') {
          await _fetchWaiterBranch(token);
        }

        if (mounted) setState(() {});
        Provider.of<CartProvider>(
          context,
          listen: false,
        ).setBranchId(_branchId);
      }
    } catch (_) {}
  }

  Future<void> _fetchBranchDetails(String token, String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches/$branchId?depth=1'),
        headers: ApiConfig.getHeaders(token),
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
        Uri.parse('${ApiConfig.baseUrl}/companies/$companyId?depth=1'),
        headers: ApiConfig.getHeaders(token),
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
        Uri.parse('${ApiConfig.baseUrl}/branches?depth=1'),
        headers: ApiConfig.getHeaders(token),
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
                  await _fetchCompanyDetails(
                    token,
                    branch['company'].toString(),
                  );
                }

                final cartProvider = Provider.of<CartProvider>(
                  context,
                  listen: false,
                );
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
          '${ApiConfig.baseUrl}/products?where[upc][equals]=$scanResult&limit=1&depth=1',
        ),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> products = data['docs'] ?? [];
        if (products.isNotEmpty) {
          final product = products[0];
          final cartProvider = Provider.of<CartProvider>(
            context,
            listen: false,
          );
          double price =
              product['defaultPriceDetails']?['price']?.toDouble() ?? 0.0;

          if (_branchId != null && product['branchOverrides'] != null) {
            for (var override in product['branchOverrides']) {
              var branch = override['branch'];
              String branchOid = branch is Map
                  ? branch[r'$oid'] ?? branch['id'] ?? ''
                  : branch ?? '';
              if (branchOid == _branchId) {
                price = override['price']?.toDouble() ?? price;
                break;
              }
            }
          }

          final item = CartItem.fromProduct(product, 1, branchPrice: price);
          cartProvider.addOrUpdateItem(item);
          final newQty = cartProvider.cartItems
              .firstWhere((i) => i.id == item.id)
              .quantity;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product['name']} added/updated (Qty: $newQty)'),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Product not found')));
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

  Future<void> _submitBilling({String status = 'completed'}) async {
    if (_isBillingInProgress) return; // lock
    setState(() => _isBillingInProgress = true);

    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    if (cartProvider.cartItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      setState(() => _isBillingInProgress = false);
      return;
    }

    // Only require payment method for completed bills
    if (status == 'completed' && _selectedPaymentMethod == null) {
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                      border: Border.all(
                        color: Color(0xFF0A84FF).withOpacity(0.5),
                      ),
                    ),
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
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
                      border: Border.all(
                        color: Color(0xFF0A84FF).withOpacity(0.5),
                      ),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
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
                  ),
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
            .map(
              (item) => ({
                'product': item.id,
                'name': item.name,
                'quantity': item.quantity,
                'unitPrice': item.price,
                'subtotal': item.price * item.quantity,
                'branchOverride': _branchId != null,
              }),
            )
            .toList(),
        'totalAmount': cartProvider.total,
        'branch': _branchId,
        'customerDetails': {
          'phone': customerDetails['phone'] ?? '',
          'name': customerDetails['name'] ?? '',
        },
        'paymentMethod': status == 'pending'
            ? 'Unpaid'
            : _selectedPaymentMethod,
        'notes': '',
        'status': status,
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/billings'),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(billingData),
      );

      final billingResponse = jsonDecode(response.body);
      print('📦 BILL RESPONSE: $billingResponse');

      if (response.statusCode == 201) {
        if (status == 'completed') {
          await _printReceipt(
            cartProvider,
            billingResponse,
            customerDetails,
            _selectedPaymentMethod!,
          );
        }
        cartProvider.clearCart();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'pending' ? 'KOT submitted' : 'Billing submitted',
            ),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CategoriesPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
    final printerIp = cartProvider.printerIp?.trim();
    final printerPort = cartProvider.printerPort;
    final printerProtocol = cartProvider.printerProtocol;

    // Fetch waiter name
    String? waiterName;
    try {
      if (billingResponse['createdBy'] != null) {
        String userId = billingResponse['createdBy'] is Map
            ? billingResponse['createdBy'][r'$oid'] ??
                  billingResponse['createdBy']['id']
            : billingResponse['createdBy'];
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null && userId.isNotEmpty) {
          final userResponse = await http.get(
            Uri.parse('${ApiConfig.baseUrl}/users/$userId?depth=1'),
            headers: ApiConfig.getHeaders(token),
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
      final prefs = await SharedPreferences.getInstance();
      final hasBluetoothPrinter = (prefs.getString('bt_printer_mac') ?? '')
          .trim()
          .isNotEmpty;

      if (!hasBluetoothPrinter &&
          printerProtocol != null &&
          printerProtocol.isNotEmpty &&
          printerProtocol != 'esc_pos') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unsupported printer protocol: $printerProtocol'),
          ),
        );
        return;
      }

      final candidatePorts = <int>[
        printerPort,
        9100,
        9101,
      ].toSet().toList(growable: false);
      final printer = await UnifiedPrinter.connect(
        printerIp: printerIp,
        candidatePorts: candidatePorts,
        paperSize: paper,
        profile: profile,
      );

      if (printer != null) {
        String invoiceNumber =
            billingResponse['invoiceNumber'] ??
            billingResponse['doc']?['invoiceNumber'] ??
            'N/A';
        // Extract numeric part from invoice like CHI-YYYYMMDD-017 → 017
        final regex = RegExp(r'^[A-Z]+-\d{8}-(\d+)$');
        final match = regex.firstMatch(invoiceNumber);
        String billNo = match != null ? match.group(1)! : invoiceNumber;
        billNo = billNo.padLeft(3, '0');

        DateTime now = DateTime.now();
        String date =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        int hour = now.hour;
        String ampm = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12;
        if (hour == 0) hour = 12;
        String time = '$hour:${now.minute.toString().padLeft(2, '0')}$ampm';
        String dateStr = '$date $time';

        printer.text(
          _companyName ?? 'BLACK FOREST CAKES',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        printer.text(
          'Branch: ${_branchName ?? _branchId}',
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.text(
          'GST: ${_branchGst ?? 'N/A'}',
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.text(
          'Mobile: ${_branchMobile ?? 'N/A'}',
          styles: const PosStyles(align: PosAlign.center),
        );
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
          printer.text(
            'Assigned by: $waiterName',
            styles: const PosStyles(align: PosAlign.center),
          );
        }
        printer.hr(ch: '=');
        printer.row([
          PosColumn(
            text: 'Item',
            width: 5,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: 'Qty',
            width: 2,
            styles: const PosStyles(bold: true, align: PosAlign.center),
          ),
          PosColumn(
            text: 'Price',
            width: 2,
            styles: const PosStyles(bold: true, align: PosAlign.right),
          ),
          PosColumn(
            text: 'Amount',
            width: 3,
            styles: const PosStyles(bold: true, align: PosAlign.right),
          ),
        ]);
        printer.hr(ch: '-');

        for (var item in cartProvider.cartItems) {
          final qtyStr = item.quantity % 1 == 0
              ? item.quantity.toStringAsFixed(0)
              : item.quantity.toStringAsFixed(2);
          printer.row([
            PosColumn(text: item.name.replaceAll('₹', 'Rs. '), width: 5),
            PosColumn(
              text: qtyStr,
              width: 2,
              styles: const PosStyles(align: PosAlign.center),
            ),
            PosColumn(
              text: item.price.toStringAsFixed(2),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: (item.price * item.quantity).toStringAsFixed(2),
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }

        printer.hr(ch: '-');
        printer.row([
          PosColumn(
            text: 'TOTAL RS',
            width: 8,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: cartProvider.total.toStringAsFixed(2),
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
        printer.text('Paid by: ${paymentMethod.toUpperCase()}');

        if (customerDetails['name']?.isNotEmpty == true ||
            customerDetails['phone']?.isNotEmpty == true) {
          printer.hr();
          printer.text('Customer: ${customerDetails['name'] ?? ''}');
          printer.text('Phone: ${customerDetails['phone'] ?? ''}');
        }

        printer.hr(ch: '=');
        printer.text(
          'Thank you! Visit Again',
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.feed(2);
        printer.cut();
        await printer.disconnectAndPrint();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt printed successfully')),
        );
      } else {
        final message = hasBluetoothPrinter || (printerIp?.isNotEmpty ?? false)
            ? 'Could not connect to the printer. Check Bluetooth or network printer.'
            : 'No printer configured. Connect a Bluetooth printer or set a branch printer.';
        throw Exception(message);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
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
          Icon(
            Icons.shopping_cart_outlined,
            size: 110,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 18),
          Text(
            'Your cart is empty',
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
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
    if (widget.isStockOrder) {
      return _buildStockOrderInternal();
    }
    if (widget.isReturnOrder) {
      return _buildReturnOrderInternal();
    }
    if (widget.isInstock) {
      return _buildInstockInternal();
    }

    // Original Billing UI
    return CommonScaffold(
      title: 'Cart',
      pageType: PageType.cart,
      actions: const [PrinterSettingsAction()],
      onScanCallback: _handleScan,
      body: Container(
        color: _bg,
        child: Consumer<CartProvider>(
          builder: (context, cartProvider, child) {
            final items = cartProvider.cartItems;
            final totalQuantity = cartProvider.cartItems.fold<double>(
              0,
              (sum, item) => sum + item.quantity,
            );
            final totalItemsDisplay = totalQuantity % 1 == 0
                ? totalQuantity.toInt().toString()
                : totalQuantity.toStringAsFixed(2);

            return SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: items.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  140,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return _CartItemCard(
                                    key: ValueKey(
                                      '${item.id}_${item.quantity}',
                                    ),
                                    item: item,
                                    cardColor: _card,
                                    accent: _accent,
                                    onRemove: () =>
                                        cartProvider.removeItem(item.id),
                                    onQuantityChange: (q) =>
                                        cartProvider.updateQuantity(item.id, q),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.black.withOpacity(0.85),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withOpacity(0.04),
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                  const SizedBox(width: 12),
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
                                onChanged: (v) =>
                                    setState(() => _addCustomerDetails = v),
                                activeColor: _accent,
                                inactiveThumbColor: Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildPaymentChips(),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _isBillingInProgress
                                        ? null
                                        : () =>
                                              _submitBilling(status: 'pending'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isBillingInProgress
                                          ? Colors.grey
                                          : Colors.blue.shade700,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: const Text(
                                      "KOT",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _isBillingInProgress
                                        ? null
                                        : () => _submitBilling(
                                            status: 'completed',
                                          ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isBillingInProgress
                                          ? Colors.grey
                                          : const Color(0xFF2EBF3B),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: _isBillingInProgress
                                        ? Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: const [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              ),
                                              SizedBox(width: 10),
                                            ],
                                          )
                                        : const Text(
                                            "BILL",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
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

  // Stock Order Specific UI
  Widget _buildStockOrderInternal() {
    return CommonScaffold(
      title: 'Stock Order Cart',
      pageType: PageType.stock, // Correctly identify as Stock Page
      body: Container(
        color: _bg,
        child: Consumer<StockProvider>(
          builder: (context, sp, _) {
            final selectedEntries = sp.selected.entries
                .where((e) => e.value)
                .toList();

            if (selectedEntries.isEmpty) {
              return _buildEmptyState();
            }

            double totalAmount = 0.0;

            for (var entry in selectedEntries) {
              final pid = entry.key;
              final req = sp.quantities[pid] ?? 0;
              final price = sp.prices[pid] ?? 0.0;
              final baseQty = sp.baseQuantities[pid] ?? 1.0;
              totalAmount += ((req / baseQty) * price);
            }

            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: selectedEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final entry = selectedEntries[index];
                        final pid = entry.key;
                        final name = sp.productNames[pid] ?? "Unknown";
                        final req = sp.quantities[pid] ?? 0;
                        final price = sp.prices[pid] ?? 0.0;
                        final baseQty = sp.baseQuantities[pid] ?? 1.0;
                        final inStock = sp.inStock[pid] ?? 0; // Get In Stock
                        final lineTotal = (req / baseQty) * price;

                        final ctrl = sp.qtyCtrl[pid];
                        if (ctrl != null && ctrl.text != req.toString()) {
                          ctrl.text = req.toString();
                        }

                        return Dismissible(
                          key: Key(pid),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            padding: const EdgeInsets.only(right: 20),
                            alignment: Alignment.centerRight,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (direction) {
                            sp.toggleSelection(pid, false);
                          },
                          child: GestureDetector(
                            onDoubleTap: () {
                              sp.toggleSelection(pid, false);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: _card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.05),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              "₹ ${price.toStringAsFixed(2)} ${sp.units[pid] ?? ''}",
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 70,
                                            height: 40,
                                            child: TextField(
                                              controller: sp.stockCtrl[pid],
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'In Stock',
                                                labelStyle: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 10,
                                                ),
                                                filled: true,
                                                fillColor: Colors.black12,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  borderSide: const BorderSide(
                                                    color: Colors.white24,
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  borderSide: const BorderSide(
                                                    color: Colors.white24,
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  borderSide: BorderSide(
                                                    color: _accent,
                                                  ),
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                              ),
                                              onChanged: (val) {
                                                final newQty =
                                                    double.tryParse(val) ?? 0.0;
                                                sp.updateInStock(pid, newQty);
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 70,
                                            height: 40,
                                            child: TextField(
                                              controller: ctrl,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Req',
                                            labelStyle: const TextStyle(
                                              color: Colors.white54,
                                            ),
                                            filled: true,
                                            fillColor: Colors.black12,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: Colors.white24,
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: Colors.white24,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: _accent,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                ),
                                          ),
                                          onChanged: (val) {
                                            final newQty =
                                                double.tryParse(val) ?? 0.0;
                                            sp.updateQuantity(pid, newQty);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                      Text(
                                        "Total: ₹ ${lineTotal.toStringAsFixed(2)}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _bg,
                      border: Border(
                        top: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: GestureDetector(
                                    onTap: () async {
                                      if (sp.isSameDay) {
                                        // Same Day: Show Time Picker only, NO 2-hour restriction
                                        final selectedTime = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay.fromDateTime(
                                            sp.deliveryDate ?? DateTime.now(),
                                          ),
                                          builder: (context, child) {
                                            return Theme(
                                              data: Theme.of(context).copyWith(
                                                timePickerTheme: TimePickerThemeData(
                                                  dayPeriodTextColor:
                                                      Colors.white,
                                                  dayPeriodBorderSide:
                                                      const BorderSide(
                                                        color: Colors.white24,
                                                        width: 0.5,
                                                      ),
                                                  dayPeriodColor:
                                                      WidgetStateColor.resolveWith(
                                                        (states) =>
                                                            states.contains(
                                                              WidgetState
                                                                  .selected,
                                                            )
                                                            ? _accent
                                                            : Colors
                                                                  .transparent,
                                                      ),
                                                  dayPeriodTextStyle:
                                                      const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                  helpTextStyle:
                                                      const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white70,
                                                      ),
                                                  hourMinuteTextStyle:
                                                      const TextStyle(
                                                        fontSize: 40,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                  inputDecorationTheme:
                                                      const InputDecorationTheme(
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 2,
                                                              vertical: 2,
                                                            ),
                                                        isDense: true,
                                                      ),
                                                ),
                                                colorScheme: ColorScheme.dark(
                                                  primary: _accent,
                                                  onSurface: Colors.white,
                                                ),
                                              ),
                                              child: MediaQuery(
                                                data: MediaQuery.of(context)
                                                    .copyWith(
                                                      alwaysUse24HourFormat:
                                                          false,
                                                    ),
                                                child: child!,
                                              ),
                                            );
                                          },
                                        );
                                        if (selectedTime != null) {
                                          final now = DateTime.now();
                                          sp.deliveryDate = DateTime(
                                            now.year,
                                            now.month,
                                            now.day,
                                            selectedTime.hour,
                                            selectedTime.minute,
                                          );
                                        }
                                        return;
                                      }

                                      // Traditional Date + Time Picker
                                      final selectedDate = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            sp.deliveryDate ??
                                            DateTime.now().add(
                                              const Duration(days: 1),
                                            ),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(2030),
                                        builder: (context, child) {
                                          return Theme(
                                            data: Theme.of(context).copyWith(
                                              colorScheme: ColorScheme.dark(
                                                primary: _accent,
                                              ),
                                            ),
                                            child: child!,
                                          );
                                        },
                                      );

                                      if (selectedDate == null) return;

                                      final selectedTime = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                          sp.deliveryDate ??
                                              DateTime.now().add(
                                                const Duration(days: 1),
                                              ),
                                        ),
                                        builder: (context, child) {
                                          return Theme(
                                            data: Theme.of(context).copyWith(
                                              timePickerTheme: TimePickerThemeData(
                                                dayPeriodTextColor:
                                                    Colors.white,
                                                dayPeriodBorderSide:
                                                    const BorderSide(
                                                      color: Colors.white24,
                                                      width: 0.5,
                                                    ),
                                                dayPeriodColor:
                                                    WidgetStateColor.resolveWith(
                                                      (states) =>
                                                          states.contains(
                                                            WidgetState
                                                                .selected,
                                                          )
                                                          ? _accent
                                                          : Colors.transparent,
                                                    ),
                                                dayPeriodTextStyle:
                                                    const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                helpTextStyle: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white70,
                                                ),
                                                hourMinuteTextStyle:
                                                    const TextStyle(
                                                      fontSize: 40,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                inputDecorationTheme:
                                                    const InputDecorationTheme(
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 2,
                                                            vertical: 2,
                                                          ),
                                                      isDense: true,
                                                    ),
                                              ),
                                              colorScheme: ColorScheme.dark(
                                                primary: _accent,
                                                onSurface: Colors.white,
                                              ),
                                            ),
                                            child: MediaQuery(
                                              data: MediaQuery.of(context)
                                                  .copyWith(
                                                    alwaysUse24HourFormat:
                                                        false,
                                                  ),
                                              child: child!,
                                            ),
                                          );
                                        },
                                      );

                                      if (selectedTime == null) return;

                                      final finalDate = DateTime(
                                        selectedDate.year,
                                        selectedDate.month,
                                        selectedDate.day,
                                        selectedTime.hour,
                                        selectedTime.minute,
                                      );

                                      sp.deliveryDate = finalDate;
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _card,
                                        border: Border.all(
                                          color: Colors.white24,
                                          width: 0.5,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            sp.isSameDay
                                                ? Icons.access_time
                                                : Icons.calendar_month,
                                            color: _accent,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              sp.isSameDay
                                                  ? "Delivery: ${DateFormat.jm().format(sp.deliveryDate ?? DateTime.now())}"
                                                  : (sp.deliveryDate == null
                                                        ? "Select Date & Time"
                                                        : DateFormat(
                                                            'dd/MM/yyyy  hh:mm a',
                                                          ).format(
                                                            sp.deliveryDate!,
                                                          )),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize
                                        .min, // Ensure it doesn't take infinite height
                                    children: [
                                      Text(
                                        "Total: ${totalAmount.toStringAsFixed(2)}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${selectedEntries.length} Items",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // STOCK & LIVE BUTTONS
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => sp.setStockMode(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: !sp.isSameDay
                                          ? Colors.blue
                                          : Colors.blue.withOpacity(0.3),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      "Stock",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => sp.setLiveMode(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: sp.isSameDay
                                          ? const Color(0xFFFF0000)
                                          : const Color(
                                              0xFFFF0000,
                                            ).withOpacity(0.3),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      "Live",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(
                                      color: Colors.redAccent,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: sp.isSubmitting
                                      ? null
                                      : () => sp.clearCart(),
                                  child: const Icon(Icons.delete_outline),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 7,
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: sp.isSubmitting
                                        ? Colors.grey
                                        : Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed:
                                      (sp.isSubmitting ||
                                          (sp.deliveryDate == null &&
                                              !sp.isSameDay))
                                      ? null
                                      : () async {
                                          final orderData = await sp
                                              .submitStockOrder(context);
                                          if (orderData != null && mounted) {
                                            await _printStockOrderReceipt(
                                              orderData,
                                            );
                                            Navigator.pushAndRemoveUntil(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    IdleTimeoutWrapper(
                                                      child: const HomePage(),
                                                    ),
                                              ),
                                              (route) => false,
                                            );
                                          }
                                        },
                                  child: sp.isSubmitting
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          "Confirm Stock Order",
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Future<void> _printStockOrderReceipt(Map<String, dynamic> orderData) async {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    String? printerIp = cartProvider.printerIp?.trim();
    int printerPort = cartProvider.printerPort;
    String? printerProtocol = cartProvider.printerProtocol;

    // Retry fetching if missing (especially in Stock mode where CartProvider might be fresh)
    // Also fetch if _branchName is missing (which is just a local state var not in CartProvider)
    if (printerIp == null || _branchName == null) {
      // Determine branch ID
      String? targetBranchId = _branchId;

      // If no local branchId (or we need to rely on provider), check StockProvider
      // Usually prefs has branchId, but let's be safe.
      if (widget.isStockOrder) {
        final sp = Provider.of<StockProvider>(context, listen: false);
        if (targetBranchId == null || targetBranchId.isEmpty) {
          targetBranchId = sp.branchId;
        }
      }

      if (targetBranchId != null) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          await _fetchBranchDetails(token, targetBranchId);
          // Refetch from provider after update
          final cpUpdated = Provider.of<CartProvider>(context, listen: false);
          printerIp = cpUpdated.printerIp?.trim();
          printerPort = cpUpdated.printerPort;
          printerProtocol = cpUpdated.printerProtocol;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final hasBluetoothPrinter = (prefs.getString('bt_printer_mac') ?? '')
        .trim()
        .isNotEmpty;

    if ((printerIp == null || printerIp.isEmpty) && !hasBluetoothPrinter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No printer configured. Connect a Bluetooth printer or set a branch printer.',
          ),
        ),
      );
      return;
    }

    if (!hasBluetoothPrinter &&
        printerProtocol != null &&
        printerProtocol.isNotEmpty &&
        printerProtocol != 'esc_pos') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unsupported printer protocol: $printerProtocol'),
        ),
      );
      return;
    }

    try {
      const PaperSize paper = PaperSize.mm80;
      final profile = await CapabilityProfile.load();
      final candidatePorts = <int>[
        printerPort,
        9100,
        9101,
      ].toSet().toList(growable: false);
      final printer = await UnifiedPrinter.connect(
        printerIp: printerIp,
        candidatePorts: candidatePorts,
        paperSize: paper,
        profile: profile,
      );

      if (printer != null) {
        DateTime now = DateTime.now();
        String date =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        String time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

        // Header
        printer.text(
          _companyName ?? 'BLACK FOREST CAKES',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        printer.text(
          'Branch: ${_branchName ?? _branchId}',
          styles: const PosStyles(align: PosAlign.center),
        );

        // Use order ID or generated reference if available
        String orderRef =
            orderData['invoiceNumber'] ?? orderData['id'] ?? 'N/A';
        // Only shorten if it looks like a raw Mongo ID (24 chars hex) and NOT an invoice number
        if (orderData['invoiceNumber'] == null && orderRef.length == 24) {
          orderRef = orderRef.substring(orderRef.length - 6);
        }

        printer.hr(ch: '=');
        printer.text(
          'STOCK ORDER #$orderRef',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
          ),
        );
        printer.text(
          'Date: $date $time',
          styles: const PosStyles(align: PosAlign.center),
        );

        // Delivery Date back in Header
        if (orderData['deliveryDate'] != null) {
          DateTime dDate = DateTime.parse(orderData['deliveryDate']).toLocal();
          // Format: 10/12/2025 9:00 AM
          String day = dDate.day.toString().padLeft(2, '0');
          String month = dDate.month.toString().padLeft(2, '0');
          String year = dDate.year.toString();

          int hour = dDate.hour;
          String ampm = 'AM';
          if (hour >= 12) {
            ampm = 'PM';
            if (hour > 12) hour -= 12;
          }
          if (hour == 0) hour = 12;

          String minute = dDate.minute.toString().padLeft(2, '0');
          String dDateStr = '$day/$month/$year $hour:$minute $ampm';

          printer.text(
            'Delivery: $dDateStr',
            styles: const PosStyles(align: PosAlign.center),
          );
        }

        printer.hr(ch: '=');

        // Items Header
        printer.row([
          PosColumn(
            text: 'Item',
            width: 6,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: 'Stock',
            width: 3,
            styles: const PosStyles(bold: true, align: PosAlign.center),
          ),
          PosColumn(
            text: 'Req',
            width: 3,
            styles: const PosStyles(bold: true, align: PosAlign.center),
          ),
        ]);
        printer.hr(ch: '-');

        // Items Logic
        final List<dynamic> items = orderData['items'] ?? [];
        double totalAmountOfReq = 0.0;

        for (var item in items) {
          String name = "Item";
          if (item['product'] is Map) {
            name = item['product']['name'] ?? "Item";
          } else if (item['product'] is String) {
            name = item['name'] ?? 'Product';
          }

          final int inStock = item['inStock'] ?? 0;
          final int req = item['requiredQty'] ?? 0;

          // Calculate total amount if price is available
          // Note: item['price'] was injected in StockProvider
          final double price = (item['price'] is num)
              ? (item['price'] as num).toDouble()
              : 0.0;
          final double baseQty = (item['baseQuantity'] is num)
              ? (item['baseQuantity'] as num).toDouble()
              : 1.0;
          totalAmountOfReq += ((req / baseQty) * price);

          printer.row([
            PosColumn(
              text: name.replaceAll('₹', 'Rs. '),
              width: 6,
              styles: const PosStyles(bold: true),
            ),
            PosColumn(
              text: inStock.toString(),
              width: 3,
              styles: const PosStyles(align: PosAlign.center, bold: true),
            ),
            PosColumn(
              text: req.toString(),
              width: 3,
              styles: const PosStyles(align: PosAlign.center, bold: true),
            ),
          ]);
        }

        printer.hr(ch: '-');

        printer.hr(ch: '-');
        printer.row([
          PosColumn(
            text: 'Total Items:',
            width: 6,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
          PosColumn(
            text: items.length.toString(),
            width: 6,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
        printer.row([
          PosColumn(
            text: 'Total Amount:',
            width: 6,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
          PosColumn(
            text: 'Rs.${totalAmountOfReq.toStringAsFixed(2)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);

        // Removed Delivery Date from Footer

        printer.hr(ch: '=');
        printer.text(
          'Printed at branch: ${_branchName ?? "Unknown"}',
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.feed(2);
        printer.cut();
        await printer.disconnectAndPrint();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt printed successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasBluetoothPrinter || (printerIp?.isNotEmpty ?? false)
                  ? 'Could not connect to the printer. Check Bluetooth or network printer.'
                  : 'No printer configured for this branch.',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  // Return Order Specific UI
  Widget _buildReturnOrderInternal() {
    return CommonScaffold(
      title: 'Return Cart',
      pageType: PageType.returnorder,
      onScanCallback: _handleScan,
      body: Container(
        color: _bg,
        child: Consumer<ReturnProvider>(
          builder: (context, provider, child) {
            final items = provider.returnItems;

            return SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: items.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _ReturnCartItemCard(
                                key: ValueKey(item.id),
                                item: item,
                                cardColor: _card,
                                accent: _accent,
                                onRemove: () => provider.removeItem(item.id),
                                onQuantityChange: (q) =>
                                    provider.updateQuantity(item.id, q),
                                provider: provider,
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _bg,
                      border: Border(
                        top: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total:',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${provider.total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed:
                                (items.isNotEmpty && !provider.isSubmitting)
                                ? () =>
                                      provider.submitReturn(context, _branchId)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: provider.isSubmitting
                                  ? Colors.grey
                                  : Colors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: provider.isSubmitting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Confirm Return',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
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

class _ReturnCartItemCard extends StatelessWidget {
  final ReturnItem item;
  final Color cardColor;
  final Color accent;
  final VoidCallback onRemove;
  final Function(double) onQuantityChange;
  final ReturnProvider provider;

  const _ReturnCartItemCard({
    required Key key,
    required this.item,
    required this.cardColor,
    required this.accent,
    required this.onRemove,
    required this.onQuantityChange,
    required this.provider,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    final tempFile = provider.getTempPhoto(item.id);
    final url = provider.getPhotoUrl(item.id);

    if (tempFile != null && tempFile.existsSync()) {
      imageProvider = FileImage(tempFile);
    } else if (url != null) {
      imageProvider = CachedNetworkImageProvider(url);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onRemove,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 70,
                height: 70,
                color: Colors.white10,
                child: imageProvider != null
                    ? Image(image: imageProvider, fit: BoxFit.cover)
                    : const Icon(Icons.broken_image, color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price.toStringAsFixed(2)} each',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Subtotal: ₹${(item.price * item.quantity).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _QtyBtn(
                icon: Icons.add,
                onTap: () => onQuantityChange(item.quantity + 1),
                accent: accent,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  item.quantity % 1 == 0
                      ? item.quantity.toStringAsFixed(0)
                      : item.quantity.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              _QtyBtn(
                icon: Icons.remove,
                onTap: () => onQuantityChange(item.quantity - 1),
                accent: accent,
              ),
            ],
          ),
        ],
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
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.chipBg,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent : chipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : Colors.white12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final Color cardColor;
  final Color accent;
  final VoidCallback onRemove;
  final Function(double) onQuantityChange;

  const _CartItemCard({
    required Key key,
    required this.item,
    required this.cardColor,
    required this.accent,
    required this.onRemove,
    required this.onQuantityChange,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // IMAGE (Tap to Remove)
          GestureDetector(
            onTap: onRemove,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,

                      placeholder: (context, url) =>
                          Container(color: Colors.white10),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.white10,
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.white24,
                        ),
                      ),
                    )
                  : Container(
                      width: 70,
                      height: 70,
                      color: Colors.white10,
                      child: const Icon(Icons.fastfood, color: Colors.white24),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // INFO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price.toStringAsFixed(2)} each',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Subtotal: ₹${(item.price * item.quantity).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // QTY CONTROLS
          Column(
            children: [
              _QtyBtn(
                icon: Icons.add,
                onTap: () => onQuantityChange(item.quantity + 1),
                accent: accent,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  item.quantity % 1 == 0
                      ? item.quantity.toStringAsFixed(0)
                      : item.quantity.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              _QtyBtn(
                icon: Icons.remove,
                onTap: () => onQuantityChange(item.quantity - 1),
                accent: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  const _QtyBtn({
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}

class _InstockCartItem extends StatefulWidget {
  final String id;
  final String name;
  final double price;
  final double quantity;
  final VoidCallback onRemove;
  final Function(double) onUpdate;

  const _InstockCartItem({
    super.key,
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  State<_InstockCartItem> createState() => _InstockCartItemState();
}

class _InstockCartItemState extends State<_InstockCartItem> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatQty(widget.quantity));
  }

  @override
  void didUpdateWidget(covariant _InstockCartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quantity != oldWidget.quantity) {
      final textVal = double.tryParse(_ctrl.text) ?? 0.0;
      if (textVal != widget.quantity) {
        _ctrl.text = _formatQty(widget.quantity);
      }
    }
  }

  String _formatQty(double val) {
    if (val == val.truncateToDouble()) {
      return val.toInt().toString();
    }
    return val.toString();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: widget.key!,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${widget.price % 1 == 0 ? widget.price.toInt() : widget.price}',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 80,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.only(bottom: 8),
                ),
                onChanged: (val) {
                  final d = double.tryParse(val);
                  if (d != null) {
                    widget.onUpdate(d);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

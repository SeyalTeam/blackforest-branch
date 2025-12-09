import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

class Bill {
  final String id;
  final String invoiceNumber;
  final int totalAmount;
  final String branch;
  final String branchName;
  final DateTime createdAt;
  final List<dynamic> items;
  final String paymentMethod;
  final String createdBy;
  final String waiterName;
  final String company;
  final String companyName;
  final String customerName;
  final String notes;
  final String status;

  Bill({
    required this.id,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.branch,
    required this.branchName,
    required this.createdAt,
    required this.items,
    required this.paymentMethod,
    required this.createdBy,
    required this.waiterName,
    required this.company,
    required this.companyName,
    required this.customerName,
    required this.notes,
    required this.status,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    String getId(dynamic obj) {
      if (obj is Map<String, dynamic>) {
        return obj['\$oid'] as String? ?? obj['id'] as String? ?? '';
      } else if (obj is String) {
        return obj;
      } else {
        return '';
      }
    }

    String getCreatedAtStr(dynamic createdJson) {
      if (createdJson is Map<String, dynamic>) {
        return createdJson['\$date'] as String? ?? '';
      } else if (createdJson is String) {
        return createdJson;
      } else {
        return '';
      }
    }

    final id = getId(json['_id'] ?? json['id']);

    final branchJson = json['branch'];
    final branchId = getId(branchJson);
    String branchName = 'Unknown Branch';
    if (branchJson is Map<String, dynamic>) {
      branchName = branchJson['name'] as String? ?? 'Unknown Branch';
    }

    final createdByJson = json['createdBy'];
    final createdById = getId(createdByJson);
    String waiterName = 'Unknown';
    if (createdByJson is Map<String, dynamic>) {
      final employee = createdByJson['employee'];
      if (employee != null && employee is Map<String, dynamic> && employee['name'] != null) {
        waiterName = employee['name'].toString();
      } else if (createdByJson['email'] != null) {
        waiterName = createdByJson['email'].toString();
      }
    }

    final companyJson = json['company'];
    final companyId = getId(companyJson);
    String companyName = 'Unknown Company';
    if (companyJson is Map<String, dynamic>) {
      companyName = companyJson['name'] as String? ?? 'Unknown Company';
    }

    final createdAtStr = getCreatedAtStr(json['createdAt']);
    final invoiceNumber = json['invoiceNumber'] ?? 'N/A';
    final totalAmount = json['totalAmount'] ?? 0;
    final items = json['items'] ?? [];
    final paymentMethod = json['paymentMethod'] ?? 'Unknown';
    final customerName = json['customerDetails']?['name'] ?? '';
    final notes = json['notes'] ?? '';
    final status = json['status'] ?? '';

    return Bill(
      id: id,
      invoiceNumber: invoiceNumber,
      totalAmount: totalAmount,
      branch: branchId,
      branchName: branchName,
      createdAt: DateTime.parse(createdAtStr),
      items: items,
      paymentMethod: paymentMethod,
      createdBy: createdById,
      waiterName: waiterName,
      company: companyId,
      companyName: companyName,
      customerName: customerName,
      notes: notes,
      status: status,
    );
  }
}

Future<List<Bill>> fetchBills(String branchId, String? token) async {
  Map<String, String>? headers = token != null ? {'Authorization': 'Bearer $token'} : null;
  final response = await http.get(
    Uri.parse(
        'https://admin.theblackforestcakes.com/api/billings?limit=1000&sort=-createdAt&depth=2'),
    headers: headers,
  );
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final docs = data['docs'] ?? [];
    List<Bill> allBills = [];
    for (var d in docs) {
      try {
        allBills.add(Bill.fromJson(d));
      } catch (_) {}
    }
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(Duration(days: 1));
    return allBills
        .where((b) =>
    b.branch == branchId &&
        b.createdAt.isAfter(todayStart) &&
        b.createdAt.isBefore(todayEnd))
        .toList();
  } else {
    throw Exception("Failed to load bills");
  }
}

Future<bool> updatePaymentMethod(String billId, String newMethod, String? token) async {
  if (billId.isEmpty) return false;

  Map<String, String>? headers = {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  final response = await http.patch(
    Uri.parse('https://admin.theblackforestcakes.com/api/billings/$billId'),
    headers: headers,
    body: json.encode({'paymentMethod': newMethod}),
  );

  return response.statusCode == 200;
}

class BillSheetPage extends StatefulWidget {
  const BillSheetPage({super.key});

  @override
  State<BillSheetPage> createState() => _BillSheetPageState();
}

class _BillSheetPageState extends State<BillSheetPage> {
  List<Bill> bills = [];
  bool isLoading = true;
  String? branchId;
  Timer? _timer;
  String? token;
  // Printer & Branch Details
  String? _printerIp;
  int _printerPort = 9100;
  String? _printerProtocol = 'esc_pos';
  String? _branchName;
  String? _branchGst;
  String? _branchMobile;
  String? _companyName;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _timer = Timer.periodic(Duration(seconds: 5), (_) => _fetchBills());
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    branchId = prefs.getString('branchId');
    token = prefs.getString('token');
    if (branchId == null) {
      setState(() => isLoading = false);
      return;
    }
    await _fetchBranchDetails(token, branchId!);
    await _fetchBills();
  }

  Future<void> _fetchBills() async {
    if (branchId == null) return;
    try {
      final result = await fetchBills(branchId!, token);
      setState(() {
        bills = result;
        isLoading = false;
      });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchBranchDetails(String? token, String branchId) async {
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches/$branchId?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final branch = jsonDecode(response.body);
        _branchName = branch['name'] ?? 'Unknown Branch';
        _branchGst = branch['gst'];
        _branchMobile = branch['phone'];
        _printerIp = branch['printerIp'];
        _printerPort = branch['printerPort'] ?? 9100;
        _printerProtocol = branch['printerProtocol'] ?? 'esc_pos';

        if (branch['company'] != null && branch['company'] is Map) {
          _companyName = branch['company']['name'];
        } else if (branch['company'] != null) {
          await _fetchCompanyDetails(token, branch['company'].toString());
        }
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

  Future<void> _printReceipt(Bill bill) async {
    if (_printerIp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No printer configured for this branch')),
      );
      return;
    }

    try {
      const PaperSize paper = PaperSize.mm80;
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(paper, profile);

      final PosPrintResult res = await printer.connect(_printerIp!, port: _printerPort);

      if (res == PosPrintResult.success) {
        // Prepare data
        DateTime now = DateTime.now();
        String date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        int hour = now.hour;
        String ampm = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12;
        if (hour == 0) hour = 12;
        String time = '$hour:${now.minute.toString().padLeft(2, '0')}$ampm';
        String dateStr = '$date $time';
        
        String billNo = bill.invoiceNumber.split("-").last.padLeft(3, '0');

        printer.text(_companyName ?? 'BLACK FOREST CAKES', styles: const PosStyles(align: PosAlign.center, bold: true));
        printer.text('Branch: ${_branchName ?? bill.branchName}', styles: const PosStyles(align: PosAlign.center));
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
        if (bill.waiterName != 'Unknown') {
          printer.text('Assigned by: ${bill.waiterName}', styles: const PosStyles(align: PosAlign.center));
        }
        printer.hr(ch: '=');
        printer.row([
          PosColumn(text: 'Item', width: 5, styles: const PosStyles(bold: true)),
          PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
          PosColumn(text: 'Price', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
          PosColumn(text: 'Amount', width: 3, styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]);
        printer.hr(ch: '-');

        for (var item in bill.items) {
          // Check if item structure matches expectation
           String name = item['product'] is Map ? item['product']['name'] ?? 'Item' : 'Item';
           // Fallback if 'product' is just ID or unexpected structure (though bill.items usually has populated data if depth=2)
           // Actually in fetchBills we request depth=2, so product should be populated.
           // However based on CartPage logic it might differ. Let's inspect Bill.fromJson. 
           // In Bill.fromJson items = json['items'].
           // Wait, usually items list contains objects with 'product' field.
           // Let's assume standard structure:
           // { product: { name: ... }, quantity: ..., unitPrice: ..., subtotal: ... } or similar.
           // The CartPage saves: 'product': item.id, 'name': item.name... 
           // So 'name' might be directly on the item object.
           
           String rawName = item['name'] ?? (item['product'] is Map ? item['product']['name'] : 'Item');
           // Remove standard Rupee symbol if present, or any non-ascii if needed.
           // For now, just replacing known issue char.
           String itemName = rawName.replaceAll('₹', 'Rs. ');
           double quantity = (item['quantity'] ?? 0).toDouble();
           double price = (item['unitPrice'] ?? 0).toDouble();
           double subtotal = (item['subtotal'] ?? 0).toDouble();
           
           final qtyStr = quantity % 1 == 0 ? quantity.toStringAsFixed(0) : quantity.toStringAsFixed(2);
           
           printer.row([
            PosColumn(text: itemName, width: 5),
            PosColumn(text: qtyStr, width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: price.toStringAsFixed(2), width: 2, styles: const PosStyles(align: PosAlign.right)),
            PosColumn(
                text: subtotal.toStringAsFixed(2),
                width: 3,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
        }

        printer.hr(ch: '-');
        printer.row([
          PosColumn(text: 'TOTAL RS', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(
              text: bill.totalAmount.toStringAsFixed(2),
              width: 4,
              styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        printer.text('Paid by: ${bill.paymentMethod.toUpperCase()}');

        // Note: Customer details could be parsed from bill.customerName if we had more structure, 
        // but Bill class only extracts customerName. 
        if (bill.customerName.isNotEmpty) {
           printer.hr();
           printer.text('Customer: ${bill.customerName}');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printer connection failed: ${res.msg}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ------------------ PAYMENT METHOD SHEET ------------------
  void _showPaymentSheet(Bill bill) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        String pay = bill.paymentMethod.toLowerCase();
        Color active = Colors.green;
        Color inactive = Colors.grey.shade300;
        Color inactiveTxt = Colors.black87;

        bool canUpdate() {
          final now = DateTime.now();
          final diff = now.difference(bill.createdAt);
          return diff.inMinutes < 5;
        }

        Widget btn(String label) {
          bool isActive = pay == label.toLowerCase();
          return Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 6),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? active : inactive,
                  foregroundColor: isActive ? Colors.white : inactiveTxt,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final newMethod = label.toLowerCase();
                  if (newMethod == pay) {
                    Navigator.pop(context);
                    return;
                  }

                  if (!canUpdate()) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                          Text("Cannot update payment method after 5 minutes.")),
                    );
                    return;
                  }

                  final success = await updatePaymentMethod(bill.id, newMethod, token);
                  if (success) {
                    await _fetchBills(); // Refresh list
                    Navigator.pop(context); // Close sheet
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Payment method updated to $label.")),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to update payment method.")),
                    );
                  }
                },
                child: Text(
                  label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Payment Method",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              Row(
                children: [
                  btn("Cash"),
                  btn("UPI"),
                  btn("Card"),
                  // Printer Icon Button
                  Container(
                    width: 60, // Fixed small width for printer icon
                    margin: EdgeInsets.only(left: 6),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                         await _printReceipt(bill);
                         if (mounted) Navigator.pop(context);
                      },
                      child: Icon(Icons.print, size: 20),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ------------------------ UI ------------------------
  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: "Bill Sheet",
      pageType: PageType.billsheet,
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : bills.isEmpty
          ? Center(child: Text("No bills today"))
          : GridView.builder(
        padding: EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: bills.length,
        itemBuilder: (_, i) {
          final bill = bills[i];
          // Format bill number (e.g., 001)
          final raw = bill.invoiceNumber.split("-").last;
          final billNo = raw.padLeft(3, '0');
          return GestureDetector(
            onTap: () => _showPaymentSheet(bill),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  billNo,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
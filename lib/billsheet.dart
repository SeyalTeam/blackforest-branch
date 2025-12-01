import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:intl/intl.dart';

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
                  if (newMethod == pay) return; // No change needed

                  if (!canUpdate()) {
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
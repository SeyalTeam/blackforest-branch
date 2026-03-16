import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/billsheet.dart'; // To reuse Bill model and fetchBills
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

class TableTrackingPage extends StatefulWidget {
  const TableTrackingPage({super.key});

  @override
  State<TableTrackingPage> createState() => _TableTrackingPageState();
}

class _TableTrackingPageState extends State<TableTrackingPage> {
  Map<String, dynamic>? _tableConfig;
  List<Bill> _activeBills = [];
  bool _isLoading = true;
  String? _token;
  String? _branchId;
  Timer? _timer;

  // Printer & Branch Details (copied from BillSheetPage logic)
  String? _printerIp;
  int _printerPort = 9100;
  String? _branchName;
  String? _branchGst;
  String? _branchMobile;
  String? _companyName;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchActiveBills();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _branchId = prefs.getString("branchId");

    if (_token != null && _branchId != null) {
      await _fetchBranchDetails(_token!, _branchId!);
      await _fetchTableConfig();
      await _fetchActiveBills();
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchTableConfig() async {
    try {
      final response = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/tables?where[branch][equals]=$_branchId&limit=1&depth=0",
        ),
        headers: ApiConfig.getHeaders(_token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data["docs"] as List;
        if (mounted) {
          setState(() {
            _tableConfig = docs.isNotEmpty ? docs.first : null;
          });
        }
      }
    } catch (e) {
      print("Error fetching table config: $e");
    }
  }

  Future<void> _fetchActiveBills() async {
    if (_branchId == null || _token == null) return;
    try {
      final result = await fetchBills(_branchId!, _token);
      if (mounted) {
        setState(() {
          // Filter only running (KOT) bills
          _activeBills = result.where((bill) {
            return bill.status.toLowerCase() != 'completed' ||
                bill.invoiceNumber.toUpperCase().contains('KOT');
          }).toList();
        });
      }
    } catch (e) {
      print("Error fetching active bills: $e");
    }
  }

  Future<void> _fetchBranchDetails(String token, String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches/$branchId?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final branch = jsonDecode(response.body);
        _branchName = branch['name'] ?? 'Unknown Branch';
        _branchGst = branch['gst'];
        _branchMobile = branch['phone'];
        _printerIp = branch['printerIp'];
        _printerPort = branch['printerPort'] ?? 9100;

        if (branch['company'] != null && branch['company'] is Map) {
          _companyName = branch['company']['name'];
        }
      }
    } catch (_) {}
  }

  String _getElapsedTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    if (hours > 0) {
      return "${hours}h ${minutes}m";
    } else {
      return "${minutes}m ${seconds}s";
    }
  }

  Bill? _getBillForTable(String sectionName, int tableNumber) {
    try {
      return _activeBills.firstWhere(
        (bill) =>
            bill.section == sectionName &&
            bill.tableNumber == tableNumber.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = (_tableConfig?["sections"] as List?) ?? [];

    return CommonScaffold(
      title: "Live Tables",
      pageType: PageType.table,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : sections.isEmpty
          ? const Center(
              child: Text("No tables configured. Please use Table Creation."),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchTableConfig();
                await _fetchActiveBills();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return _buildSectionGrid(section);
                },
              ),
            ),
    );
  }

  Widget _buildSectionGrid(dynamic section) {
    final name = section["name"] ?? "Section";
    final count = section["tableCount"] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 24,
            childAspectRatio: 1.0,
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            final tableNum = index + 1;
            final bill = _getBillForTable(name, tableNum);
            return _buildTableCard(name, tableNum, bill);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTableCard(String sectionName, int tableNumber, Bill? bill) {
    final bool isOccupied = bill != null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isOccupied
                ? const Color(0xFFFFF176)
                : const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOccupied ? Colors.orange.shade200 : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isOccupied) ...[
                  Text(
                    _getElapsedTime(bill.createdAt),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  "Table $tableNumber",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (isOccupied) ...[
                  const SizedBox(height: 4),
                  Text(
                    bill.invoiceNumber.split("-").last.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    "By: ${bill.waiterName}",
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Rs ${bill.totalAmount.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Action Buttons Positioning
        if (isOccupied)
          Positioned(
            bottom: -15,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circularAction(
                  icon: Icons.visibility,
                  onPressed: () => _showBillDetails(bill),
                  color: Colors.blue,
                ),
                const SizedBox(width: 12),
                _circularAction(
                  icon: Icons.print,
                  onPressed: () => _printBill(bill),
                  color: Colors.green,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _circularAction({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  void _showBillDetails(Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Order Details - ${bill.invoiceNumber.split("-").last}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: bill.items.length,
                  itemBuilder: (context, index) {
                    final item = bill.items[index];
                    final String name =
                        item['name'] ??
                        (item['product'] is Map
                            ? item['product']['name']
                            : 'Item');
                    final double qty = (item['quantity'] ?? 0).toDouble();
                    final double price = (item['unitPrice'] ?? 0).toDouble();
                    final double subtotal = (item['subtotal'] ?? 0).toDouble();

                    return ListTile(
                      title: Text(name),
                      subtitle: Text(
                        "${qty.toStringAsFixed(0)} x Rs ${price.toStringAsFixed(2)}",
                      ),
                      trailing: Text(
                        "Rs ${subtotal.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Amount",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Rs ${bill.totalAmount.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _printBill(Bill bill) async {
    // Reusing print logic from BillSheetPage
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

      final PosPrintResult res = await printer.connect(
        _printerIp!,
        port: _printerPort,
      );

      if (res == PosPrintResult.success) {
        // Prepare data (simplified version for this tool-call, but follows same pattern)
        DateTime now = DateTime.now();
        String dateStr =
            '${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}';

        printer.text(
          _companyName ?? 'BLACK FOREST CAKES',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        printer.text(
          'Branch: ${_branchName ?? bill.branchName}',
          styles: const PosStyles(align: PosAlign.center),
        );
        if (_branchGst != null) {
          printer.text(
            'GST: $_branchGst',
            styles: const PosStyles(align: PosAlign.center),
          );
        }
        if (_branchMobile != null) {
          printer.text(
            'Mobile: $_branchMobile',
            styles: const PosStyles(align: PosAlign.center),
          );
        }
        printer.hr(ch: '=');
        printer.text(
          'BILL NO - ${bill.invoiceNumber.split("-").last}',
          styles: const PosStyles(align: PosAlign.right, bold: true),
        );
        printer.text(
          'Date: $dateStr',
          styles: const PosStyles(align: PosAlign.left),
        );
        printer.hr(ch: '=');

        for (var item in bill.items) {
          String name =
              item['name'] ??
              (item['product'] is Map ? item['product']['name'] : 'Item');
          double quantity = (item['quantity'] ?? 0).toDouble();
          double price = (item['unitPrice'] ?? 0).toDouble();
          double subtotal = (item['subtotal'] ?? 0).toDouble();

          printer.row([
            PosColumn(text: name, width: 4),
            PosColumn(
              text: quantity.toStringAsFixed(0),
              width: 2,
              styles: const PosStyles(align: PosAlign.center),
            ),
            PosColumn(
              text: price.toStringAsFixed(2),
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: subtotal.toStringAsFixed(2),
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
            text: bill.totalAmount.toStringAsFixed(2),
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
        printer.hr(ch: '=');
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }
}

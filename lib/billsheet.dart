import 'package:flutter/material.dart';
import 'common_scaffold.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';
import 'dart:async';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:branch/printer/printer_settings_action.dart';
import 'package:branch/printer/unified_printer.dart';

class Bill {
  final String id;
  final String invoiceNumber;
  final double totalAmount;
  final double grossAmount;
  final double customerOfferDiscount;
  final double totalPercentageOfferDiscount;
  final bool totalPercentageOfferApplied;
  final double customerEntryPercentageOfferDiscount;
  final bool customerEntryPercentageOfferApplied;
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
  final String? tableNumber;
  final String? section;

  Bill({
    required this.id,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.grossAmount,
    required this.customerOfferDiscount,
    required this.totalPercentageOfferDiscount,
    required this.totalPercentageOfferApplied,
    required this.customerEntryPercentageOfferDiscount,
    required this.customerEntryPercentageOfferApplied,
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
    this.tableNumber,
    this.section,
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

    try {
      double toMoney(dynamic value) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '') ?? 0.0;
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
        if (employee != null &&
            employee is Map<String, dynamic> &&
            employee['name'] != null) {
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
      final totalAmount = toMoney(json['totalAmount']);
      final grossAmount = toMoney(json['grossAmount']);
      final customerOfferDiscount = toMoney(json['customerOfferDiscount']);
      final totalPercentageOfferDiscount = toMoney(
        json['totalPercentageOfferDiscount'],
      );
      final customerEntryPercentageOfferDiscount = toMoney(
        json['customerEntryPercentageOfferDiscount'],
      );
      final items = json['items'] ?? [];
      final paymentMethod = json['paymentMethod'] ?? 'Unknown';
      final customerName = json['customerDetails']?['name'] ?? '';
      final notes = json['notes'] ?? '';
      final status = json['status'] ?? '';
      final totalPercentageOfferApplied =
          json['totalPercentageOfferApplied'] == true;
      final customerEntryPercentageOfferApplied =
          json['customerEntryPercentageOfferApplied'] == true;

      // Table Details
      final tableObj = json['tableDetails'];
      String? tNum;
      String? tSec;
      if (tableObj is Map<String, dynamic>) {
        tNum = tableObj['tableNumber']?.toString();
        tSec = tableObj['section']?.toString();
      }

      DateTime parsedDate;
      try {
        parsedDate = DateTime.parse(createdAtStr);
      } catch (_) {
        parsedDate = DateTime.now();
      }

      return Bill(
        id: id,
        invoiceNumber: invoiceNumber,
        totalAmount: totalAmount,
        grossAmount: grossAmount > 0 ? grossAmount : totalAmount,
        customerOfferDiscount: customerOfferDiscount,
        totalPercentageOfferDiscount: totalPercentageOfferDiscount,
        totalPercentageOfferApplied: totalPercentageOfferApplied,
        customerEntryPercentageOfferDiscount:
            customerEntryPercentageOfferDiscount,
        customerEntryPercentageOfferApplied:
            customerEntryPercentageOfferApplied,
        branch: branchId,
        branchName: branchName,
        createdAt: parsedDate,
        items: items,
        paymentMethod: paymentMethod,
        createdBy: createdById,
        waiterName: waiterName,
        company: companyId,
        companyName: companyName,
        customerName: customerName,
        notes: notes,
        status: status,
        tableNumber: tNum,
        section: tSec,
      );
    } catch (e) {
      print('❌ Error parsing Bill: $e');
      rethrow;
    }
  }
}

Future<List<Bill>> fetchBills(String branchId, String? token) async {
  Map<String, String> headers = ApiConfig.getHeaders(token);

  final now = DateTime.now();
  final startOfToday = DateTime(
    now.year,
    now.month,
    now.day,
  ).toUtc().toIso8601String();

  // We fetch without status filter to get both KOTs and Bills
  final url =
      '${ApiConfig.baseUrl}/billings?where[branch][equals]=$branchId&where[createdAt][greater_than]=$startOfToday&limit=1000&sort=-createdAt&depth=2';

  final response = await http.get(Uri.parse(url), headers: headers);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final docs = data['docs'] ?? [];
    List<Bill> allBills = [];
    for (var d in docs) {
      try {
        allBills.add(Bill.fromJson(d));
      } catch (e) {
        print('Skipping bill due to error: $e');
      }
    }
    return allBills;
  } else {
    throw Exception("Failed to load bills: ${response.statusCode}");
  }
}

Future<bool> updatePaymentMethod(
  String billId,
  String newMethod,
  String? token,
) async {
  if (billId.isEmpty) return false;

  Map<String, String> headers = ApiConfig.getHeaders(token);

  final response = await http.patch(
    Uri.parse('${ApiConfig.baseUrl}/billings/$billId'),
    headers: headers,
    body: json.encode({'paymentMethod': newMethod}),
  );

  return response.statusCode == 200;
}

class BillUpdateResult {
  final bool success;
  final String? message;

  const BillUpdateResult({required this.success, this.message});
}

Future<BillUpdateResult> settleBill(
  String billId,
  String paymentMethod,
  String? token,
) async {
  if (billId.isEmpty) {
    return const BillUpdateResult(success: false, message: 'Invalid bill ID.');
  }

  const allowedMethods = {'cash', 'card', 'upi', 'other'};
  final normalizedMethod = paymentMethod.trim().toLowerCase();
  if (!allowedMethods.contains(normalizedMethod)) {
    return const BillUpdateResult(
      success: false,
      message: 'Please select a valid payment method before settlement.',
    );
  }

  try {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/billings/$billId'),
      headers: ApiConfig.getHeaders(token),
      body: json.encode({
        'status': 'settled',
        'paymentMethod': normalizedMethod,
      }),
    );

    if (response.statusCode == 200) {
      return const BillUpdateResult(success: true);
    }

    String? serverMessage;
    try {
      final data = json.decode(response.body);
      if (data is Map<String, dynamic>) {
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          serverMessage = message;
        } else if (message is List && message.isNotEmpty) {
          serverMessage = message.first.toString();
        } else if (data['errors'] is List &&
            (data['errors'] as List).isNotEmpty) {
          serverMessage = (data['errors'] as List).first.toString();
        }
      }
    } catch (_) {}

    return BillUpdateResult(
      success: false,
      message: serverMessage ?? 'Failed to settle bill.',
    );
  } catch (_) {
    return const BillUpdateResult(
      success: false,
      message: 'Unable to settle bill. Please try again.',
    );
  }
}

class _ReceiptItemLine {
  final String name;
  final double quantity;
  final double unitPrice;
  final double lineAmount;
  final double lineTaxAmount;
  final double gstPercent;

  const _ReceiptItemLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineAmount,
    required this.lineTaxAmount,
    required this.gstPercent,
  });
}

class _ReceiptSummary {
  final List<_ReceiptItemLine> lines;
  final Map<double, double> cgstSgstBreakdown;
  final double receiptSubTotalAmount;
  final double receiptGstAmount;
  final double receiptTotalAmount;
  final double roundedGrandTotal;
  final double roundOffAmount;
  final double billDiscount;
  final double remainingBillDiscount;

  const _ReceiptSummary({
    required this.lines,
    required this.cgstSgstBreakdown,
    required this.receiptSubTotalAmount,
    required this.receiptGstAmount,
    required this.receiptTotalAmount,
    required this.roundedGrandTotal,
    required this.roundOffAmount,
    required this.billDiscount,
    required this.remainingBillDiscount,
  });
}

class BillSheetPage extends StatefulWidget {
  const BillSheetPage({super.key});

  @override
  State<BillSheetPage> createState() => _BillSheetPageState();
}

class _BillSheetPageState extends State<BillSheetPage> {
  static const Set<String> _allowedPaymentMethods = {
    'cash',
    'card',
    'upi',
    'other',
  };
  static const Set<String> _allowedSettlementRoles = {
    'cashier',
    'supervisor',
    'branch',
    'waiter',
    'superadmin',
  };

  List<Bill> bills = [];
  bool isLoading = true;
  String? branchId;
  Timer? _timer;
  String? token;
  String? _userRole;
  // Printer & Branch Details
  String? _printerIp;
  int _printerPort = 9100;
  String? _printerProtocol = 'esc_pos';
  String? _branchName;
  String? _branchGst;
  String? _branchMobile;
  String? _companyName;
  OverlayEntry? _topAlertOverlay;
  Timer? _topAlertTimer;

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
    _userRole = prefs.getString('role')?.toLowerCase().trim();
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
        Uri.parse('${ApiConfig.baseUrl}/companies/$companyId?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final company = jsonDecode(response.body);
        _companyName = company['name'] ?? 'Unknown Company';
      }
    } catch (_) {}
  }

  bool get _canUpdateOrSettleBills =>
      _allowedSettlementRoles.contains(_userRole ?? '');

  String? _normalizePaymentMethod(String? method) {
    final value = method?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return _allowedPaymentMethods.contains(value) ? value : null;
  }

  void _hideTopAlert() {
    _topAlertTimer?.cancel();
    _topAlertTimer = null;
    _topAlertOverlay?.remove();
    _topAlertOverlay = null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    _hideTopAlert();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _topAlertOverlay = OverlayEntry(
      builder: (overlayContext) {
        final topInset = MediaQuery.of(overlayContext).padding.top + 10;
        return Positioned(
          top: topInset,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: _hideTopAlert,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_topAlertOverlay!);
    _topAlertTimer = Timer(const Duration(seconds: 2), _hideTopAlert);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double _toNonNegativeMoney(dynamic value) {
    final parsed = _toDouble(value);
    return parsed < 0 ? 0.0 : parsed;
  }

  double _parsePercent(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value?.toString().replaceAll('%', '').trim() ?? '';
    return double.tryParse(raw) ?? 0.0;
  }

  String _formatQty(double quantity) {
    return quantity % 1 == 0
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);
  }

  String _formatReceiptMoney(double value) {
    final rounded = double.parse(value.toStringAsFixed(2));
    if ((rounded - rounded.truncateToDouble()).abs() < 0.001) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(2);
  }

  String _buildReceiptDate(DateTime now) {
    String date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    int hour = now.hour;
    String ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String time = '$hour:${now.minute.toString().padLeft(2, '0')}$ampm';
    return '$date $time';
  }

  String _buildBillNo(Bill bill) {
    final raw = bill.invoiceNumber.split("-").last;
    return raw.padLeft(3, '0');
  }

  String _extractItemName(dynamic item) {
    if (item is! Map) return 'Item';
    final rawName =
        item['name'] ??
        (item['product'] is Map ? item['product']['name'] : 'Item');
    return rawName.toString().replaceAll('₹', 'Rs. ');
  }

  double _extractItemGstPercent(dynamic item) {
    if (item is! Map) return 0.0;
    final product = item['product'];
    return _parsePercent(
      item['gstPercent'] ??
          item['gstPercentage'] ??
          item['gst'] ??
          item['tax'] ??
          item['taxPercentValue'] ??
          item['taxPercent'] ??
          item['taxRate'] ??
          (product is Map
              ? (product['gstPercent'] ??
                    product['gstPercentage'] ??
                    product['gst'] ??
                    product['tax'] ??
                    product['taxPercentValue'] ??
                    product['taxPercent'] ??
                    product['taxRate'] ??
                    (product['defaultPriceDetails'] is Map
                        ? (product['defaultPriceDetails']['gst'] ??
                              product['defaultPriceDetails']['gstPercent'] ??
                              product['defaultPriceDetails']['gstPercentage'] ??
                              product['defaultPriceDetails']['taxPercent'] ??
                              product['defaultPriceDetails']['taxRate'])
                        : null))
              : null),
    );
  }

  double _extractItemUnitPrice(dynamic item) {
    if (item is! Map) return 0.0;
    return _toDouble(
      item['effectiveUnitPrice'] ?? item['unitPrice'] ?? item['price'],
    );
  }

  double _extractItemLineAmount(dynamic item, double qty, double unitPrice) {
    if (item is! Map) return qty * unitPrice;
    final direct = _toDouble(
      item['lineTotal'] ??
          item['subtotal'] ??
          item['amount'] ??
          item['total'] ??
          item['lineAmount'],
    );
    if (direct > 0) return direct;
    return qty * unitPrice;
  }

  _ReceiptSummary _buildReceiptSummary(Bill bill) {
    final grossAmount = _toNonNegativeMoney(bill.grossAmount);
    final totalAmount = _toNonNegativeMoney(bill.totalAmount);

    final cgstSgstBreakdown = <double, double>{};
    final lines = <_ReceiptItemLine>[];
    double receiptSubTotalAccumulator = 0.0;

    for (final rawItem in bill.items) {
      final item = rawItem is Map ? rawItem : null;
      final quantity = _toDouble(item?['quantity'] ?? item?['qty'] ?? 1);
      final safeQuantity = quantity > 0 ? quantity : 1.0;
      final unitPrice = _extractItemUnitPrice(rawItem);
      final lineAmount = _extractItemLineAmount(
        rawItem,
        safeQuantity,
        unitPrice,
      );
      final gstPercent = _extractItemGstPercent(rawItem);
      final effectiveLineAmount = lineAmount
          .clamp(0.0, double.infinity)
          .toDouble();
      final lineTaxAmount = gstPercent > 0
          ? effectiveLineAmount * gstPercent / 100
          : 0.0;
      receiptSubTotalAccumulator += effectiveLineAmount;

      if (gstPercent > 0 && lineTaxAmount > 0.0001) {
        final halfRate = double.parse((gstPercent / 2).toStringAsFixed(2));
        final halfTaxAmount = lineTaxAmount / 2;
        cgstSgstBreakdown.update(
          halfRate,
          (current) => current + halfTaxAmount,
          ifAbsent: () => halfTaxAmount,
        );
      }

      lines.add(
        _ReceiptItemLine(
          name: _extractItemName(rawItem),
          quantity: safeQuantity,
          unitPrice: unitPrice,
          lineAmount: effectiveLineAmount,
          lineTaxAmount: lineTaxAmount,
          gstPercent: gstPercent,
        ),
      );
    }

    final receiptSubTotalAmount = double.parse(
      receiptSubTotalAccumulator.toStringAsFixed(2),
    );
    final receiptGstAmount = double.parse(
      cgstSgstBreakdown.values
          .fold<double>(0.0, (sum, taxPart) => sum + (taxPart * 2))
          .toStringAsFixed(2),
    );
    final receiptTotalAmount = double.parse(
      (receiptSubTotalAmount + receiptGstAmount).toStringAsFixed(2),
    );
    final roundedGrandTotal = double.parse(
      receiptTotalAmount.ceilToDouble().toStringAsFixed(2),
    );
    final roundOffAmount = double.parse(
      (roundedGrandTotal - receiptTotalAmount).toStringAsFixed(2),
    );
    final billDiscount = (grossAmount - totalAmount)
        .clamp(0.0, double.infinity)
        .toDouble();
    final explainedBillDiscount =
        bill.customerOfferDiscount +
        bill.totalPercentageOfferDiscount +
        bill.customerEntryPercentageOfferDiscount;
    final remainingBillDiscount = (billDiscount - explainedBillDiscount)
        .clamp(0.0, double.infinity)
        .toDouble();

    return _ReceiptSummary(
      lines: lines,
      cgstSgstBreakdown: cgstSgstBreakdown,
      receiptSubTotalAmount: receiptSubTotalAmount,
      receiptGstAmount: receiptGstAmount,
      receiptTotalAmount: receiptTotalAmount,
      roundedGrandTotal: roundedGrandTotal,
      roundOffAmount: roundOffAmount,
      billDiscount: billDiscount,
      remainingBillDiscount: remainingBillDiscount,
    );
  }

  Widget _buildReceiptPreviewPanel(Bill bill, {String? selectedPaymentMethod}) {
    final now = DateTime.now();
    final dateStr = _buildReceiptDate(now);
    final billNo = _buildBillNo(bill);
    final summary = _buildReceiptSummary(bill);
    final paidBy =
        (_normalizePaymentMethod(selectedPaymentMethod) ??
                _normalizePaymentMethod(bill.paymentMethod) ??
                bill.paymentMethod)
            .toUpperCase();
    final hasTableOrder =
        (bill.tableNumber?.trim().isNotEmpty ?? false) ||
        (bill.section?.trim().isNotEmpty ?? false);

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: TextStyle(color: Colors.black87, fontSize: 11, height: 1.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _companyName ?? 'BLACK FOREST CAKES',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              'Branch: ${_branchName ?? bill.branchName}',
              textAlign: TextAlign.center,
            ),
            Text('GST: ${_branchGst ?? 'N/A'}', textAlign: TextAlign.center),
            Text(
              'Mobile: ${_branchMobile ?? 'N/A'}',
              textAlign: TextAlign.center,
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(thickness: 1.2),
            ),
            Row(
              children: [
                Expanded(child: Text('Date: $dateStr')),
                Text(
                  'BILL NO - $billNo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (bill.waiterName != 'Unknown')
              hasTableOrder
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Assigned by: ${bill.waiterName}',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          bill.section?.trim().isNotEmpty == true
                              ? 'Table: ${bill.tableNumber ?? '-'} (${bill.section})'
                              : 'Table: ${bill.tableNumber ?? '-'}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Assigned by: ${bill.waiterName}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(thickness: 1.2),
            ),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'Item',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Qty',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Price',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Tax',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Amt',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Divider(height: 10, thickness: 1),
            ...summary.lines.map((line) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: Text(line.name)),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatQty(line.quantity),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatReceiptMoney(line.unitPrice),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatReceiptMoney(line.lineTaxAmount),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatReceiptMoney(line.lineAmount),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
            Divider(height: 12, thickness: 1),
            if (summary.billDiscount > 0.0001) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Text('GROSS RS ${bill.grossAmount.toStringAsFixed(2)}'),
              ),
              if (summary.remainingBillDiscount > 0.009)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'OTHER DISCOUNT RS ${summary.remainingBillDiscount.toStringAsFixed(2)}',
                  ),
                ),
              if (bill.customerOfferDiscount > 0.0001)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'CREDIT OFFER RS ${bill.customerOfferDiscount.toStringAsFixed(2)}',
                  ),
                ),
              if (bill.totalPercentageOfferApplied &&
                  bill.totalPercentageOfferDiscount > 0.0001)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'PERCENT OFFER RS ${bill.totalPercentageOfferDiscount.toStringAsFixed(2)}',
                  ),
                ),
              if (bill.customerEntryPercentageOfferApplied &&
                  bill.customerEntryPercentageOfferDiscount > 0.0001)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'ENTRY PERCENT OFFER RS ${bill.customerEntryPercentageOfferDiscount.toStringAsFixed(2)}',
                  ),
                ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'SUB TOTAL RS ${_formatReceiptMoney(summary.receiptSubTotalAmount)}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (summary.receiptGstAmount > 0.0001)
              ...((summary.cgstSgstBreakdown.keys.toList()..sort()).expand((
                halfRate,
              ) {
                final taxPartAmount = double.parse(
                  (summary.cgstSgstBreakdown[halfRate] ?? 0.0).toStringAsFixed(
                    2,
                  ),
                );
                if (taxPartAmount <= 0.0001) return <Widget>[];
                return [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'CGST ${halfRate.toStringAsFixed(2)}% RS ${_formatReceiptMoney(taxPartAmount)}',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'SGST ${halfRate.toStringAsFixed(2)}% RS ${_formatReceiptMoney(taxPartAmount)}',
                    ),
                  ),
                ];
              })),
            Divider(height: 10, thickness: 1),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Round off ${summary.roundOffAmount >= 0 ? '+' : '-'}${summary.roundOffAmount.abs().toStringAsFixed(2)}',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PAID BY: $paidBy',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'GRAND TOTAL RS ${_formatReceiptMoney(summary.roundedGrandTotal)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            Divider(height: 10, thickness: 1.2),
            if (bill.customerName.isNotEmpty) ...[
              Divider(height: 12, thickness: 1),
              Text('Customer: ${bill.customerName}'),
            ],
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(thickness: 1.2),
            ),
            Text('Thank you! Visit Again', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _printReceipt(Bill bill, {String? paymentMethodOverride}) async {
    try {
      const PaperSize paper = PaperSize.mm80;
      final profile = await CapabilityProfile.load();
      final prefs = await SharedPreferences.getInstance();
      final hasBluetoothPrinter = (prefs.getString('bt_printer_mac') ?? '')
          .trim()
          .isNotEmpty;

      if (!hasBluetoothPrinter &&
          _printerProtocol != null &&
          _printerProtocol!.isNotEmpty &&
          _printerProtocol != 'esc_pos') {
        _showMessage('Unsupported printer protocol: $_printerProtocol');
        return;
      }

      final candidatePorts = <int>[
        _printerPort,
        9100,
        9101,
      ].toSet().toList(growable: false);
      final printer = await UnifiedPrinter.connect(
        printerIp: _printerIp?.trim(),
        candidatePorts: candidatePorts,
        paperSize: paper,
        profile: profile,
      );

      if (printer != null) {
        DateTime now = DateTime.now();
        final dateStr = _buildReceiptDate(now);
        final billNo = _buildBillNo(bill);
        final summary = _buildReceiptSummary(bill);
        final paidBy =
            (_normalizePaymentMethod(paymentMethodOverride) ??
                    _normalizePaymentMethod(bill.paymentMethod) ??
                    bill.paymentMethod)
                .toUpperCase();
        final hasTableOrder =
            (bill.tableNumber?.trim().isNotEmpty ?? false) ||
            (bill.section?.trim().isNotEmpty ?? false);

        printer.text(
          _companyName ?? 'BLACK FOREST CAKES',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        printer.text(
          'Branch: ${_branchName ?? bill.branchName}',
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
        if (bill.waiterName != 'Unknown') {
          if (hasTableOrder) {
            final tableText = bill.section?.trim().isNotEmpty == true
                ? 'Table: ${bill.tableNumber ?? '-'} (${bill.section})'
                : 'Table: ${bill.tableNumber ?? '-'}';
            printer.row([
              PosColumn(
                text: 'Assigned by: ${bill.waiterName}',
                width: 7,
                styles: const PosStyles(align: PosAlign.left, bold: true),
              ),
              PosColumn(
                text: tableText,
                width: 5,
                styles: const PosStyles(align: PosAlign.right, bold: true),
              ),
            ]);
          } else {
            printer.text(
              'Assigned by: ${bill.waiterName}',
              styles: const PosStyles(align: PosAlign.left, bold: true),
            );
          }
        }
        printer.hr(ch: '=');
        printer.row([
          PosColumn(
            text: 'Item',
            width: 4,
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
            text: 'Tax',
            width: 2,
            styles: const PosStyles(bold: true, align: PosAlign.right),
          ),
          PosColumn(
            text: 'Amt',
            width: 2,
            styles: const PosStyles(bold: true, align: PosAlign.right),
          ),
        ]);
        printer.hr(ch: '-');

        for (final line in summary.lines) {
          printer.row([
            PosColumn(text: line.name, width: 4),
            PosColumn(
              text: _formatQty(line.quantity),
              width: 2,
              styles: const PosStyles(align: PosAlign.center),
            ),
            PosColumn(
              text: _formatReceiptMoney(line.unitPrice),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: _formatReceiptMoney(line.lineTaxAmount),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: _formatReceiptMoney(line.lineAmount),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }

        printer.hr(ch: '-');
        if (summary.billDiscount > 0.0001) {
          printer.row([
            PosColumn(
              text: 'GROSS RS ${bill.grossAmount.toStringAsFixed(2)}',
              width: 12,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          if (summary.remainingBillDiscount > 0.009) {
            printer.row([
              PosColumn(
                text:
                    'OTHER DISCOUNT RS ${summary.remainingBillDiscount.toStringAsFixed(2)}',
                width: 12,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
          if (bill.customerOfferDiscount > 0.0001) {
            printer.row([
              PosColumn(
                text:
                    'CREDIT OFFER RS ${bill.customerOfferDiscount.toStringAsFixed(2)}',
                width: 12,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
          if (bill.totalPercentageOfferApplied &&
              bill.totalPercentageOfferDiscount > 0.0001) {
            printer.row([
              PosColumn(
                text:
                    'PERCENT OFFER RS ${bill.totalPercentageOfferDiscount.toStringAsFixed(2)}',
                width: 12,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
          if (bill.customerEntryPercentageOfferApplied &&
              bill.customerEntryPercentageOfferDiscount > 0.0001) {
            printer.row([
              PosColumn(
                text:
                    'ENTRY PERCENT OFFER RS ${bill.customerEntryPercentageOfferDiscount.toStringAsFixed(2)}',
                width: 12,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
        }

        printer.row([
          PosColumn(
            text:
                'SUB TOTAL RS ${_formatReceiptMoney(summary.receiptSubTotalAmount)}',
            width: 12,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);

        if (summary.receiptGstAmount > 0.0001) {
          final sortedHalfRates = summary.cgstSgstBreakdown.keys.toList()
            ..sort();
          for (final halfRate in sortedHalfRates) {
            final taxPartAmount = double.parse(
              (summary.cgstSgstBreakdown[halfRate] ?? 0.0).toStringAsFixed(2),
            );
            if (taxPartAmount <= 0.0001) continue;
            printer.row([
              PosColumn(
                text:
                    'CGST ${halfRate.toStringAsFixed(2)}% RS ${_formatReceiptMoney(taxPartAmount)}',
                width: 12,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
            printer.row([
              PosColumn(
                text:
                    'SGST ${halfRate.toStringAsFixed(2)}% RS ${_formatReceiptMoney(taxPartAmount)}',
                width: 12,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
          }
        }

        printer.hr(ch: '-');
        printer.row([
          PosColumn(
            text:
                'Round off ${summary.roundOffAmount >= 0 ? '+' : '-'}${summary.roundOffAmount.abs().toStringAsFixed(2)}',
            width: 12,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
        printer.row([
          PosColumn(
            text: 'PAID BY: $paidBy',
            width: 5,
            styles: const PosStyles(align: PosAlign.left, bold: true),
          ),
          PosColumn(
            text:
                'GRAND TOTAL RS ${_formatReceiptMoney(summary.roundedGrandTotal)}',
            width: 7,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);

        if (bill.customerName.isNotEmpty) {
          printer.hr();
          printer.text('Customer: ${bill.customerName}');
        }

        printer.hr(ch: '=');
        printer.text(
          'Thank you! Visit Again',
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.feed(2);
        printer.cut();
        await printer.disconnectAndPrint();

        _showMessage('Receipt printed successfully');
      } else {
        final message =
            hasBluetoothPrinter || ((_printerIp ?? '').trim().isNotEmpty)
            ? 'Could not connect to the printer. Check Bluetooth or network printer.'
            : 'No printer configured. Connect a Bluetooth printer or set a branch printer.';
        _showMessage(message);
      }
    } catch (e) {
      _showMessage('Print failed: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hideTopAlert();
    super.dispose();
  }

  // ------------------ PAYMENT METHOD SHEET ------------------
  void _showPaymentSheet(Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        String? pay = _normalizePaymentMethod(bill.paymentMethod);
        bool isSettling = false;
        Color active = Colors.green;
        Color inactive = Colors.grey.shade300;
        Color inactiveTxt = Colors.black87;
        final billStatus = bill.status.toLowerCase();

        bool canUpdate() {
          final now = DateTime.now();
          final diff = now.difference(bill.createdAt);
          return diff.inMinutes < 5;
        }

        return StatefulBuilder(
          builder: (statefulContext, sheetSetState) {
            Widget btn(String label) {
              final method = label.toLowerCase();
              bool isActive = pay == method;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? active : inactive,
                      foregroundColor: isActive ? Colors.white : inactiveTxt,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      if (!_canUpdateOrSettleBills) {
                        _showMessage(
                          "You don't have permission to update bill settlement.",
                        );
                        return;
                      }

                      if (!canUpdate()) {
                        _showMessage(
                          "Cannot update payment method after 5 minutes.",
                        );
                        return;
                      }

                      if (pay == method) return;

                      final previousPay = pay;
                      sheetSetState(() => pay = method);
                      final success = await updatePaymentMethod(
                        bill.id,
                        method,
                        token,
                      );
                      if (!mounted || !statefulContext.mounted) return;

                      if (success) {
                        await _fetchBills(); // Refresh list
                        _showMessage("Payment method updated to $label.");
                        if (billStatus == 'settled' &&
                            mounted &&
                            sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      } else {
                        sheetSetState(() => pay = previousPay);
                        _showMessage("Failed to update payment method.");
                      }
                    },
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }

            final canSettleNow =
                _canUpdateOrSettleBills &&
                billStatus == 'completed' &&
                pay != null &&
                !isSettling;
            final isAlreadySettled = billStatus == 'settled';
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: Colors.grey.shade200,
                      padding: EdgeInsets.all(8),
                      child: _buildReceiptPreviewPanel(
                        bill,
                        selectedPaymentMethod: pay,
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        btn("Cash"),
                        btn("UPI"),
                        btn("Card"),
                        Container(
                          width: 60,
                          margin: EdgeInsets.only(left: 8),
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
                              await _printReceipt(
                                bill,
                                paymentMethodOverride: pay,
                              );
                              if (mounted && sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            child: Icon(Icons.print, size: 20),
                          ),
                        ),
                      ],
                    ),
                    if (!isAlreadySettled) ...[
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black87,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: canSettleNow
                                  ? () async {
                                      final paymentMethod = pay;
                                      if (paymentMethod == null) {
                                        _showMessage(
                                          "Payment method is required before settling the bill.",
                                        );
                                        return;
                                      }

                                      if (billStatus != 'completed') {
                                        _showMessage(
                                          "Bill can be settled only after it is completed.",
                                        );
                                        return;
                                      }

                                      sheetSetState(() => isSettling = true);

                                      final result = await settleBill(
                                        bill.id,
                                        paymentMethod,
                                        token,
                                      );
                                      if (!mounted ||
                                          !statefulContext.mounted) {
                                        return;
                                      }
                                      sheetSetState(() => isSettling = false);

                                      if (result.success) {
                                        if (mounted && sheetContext.mounted) {
                                          Navigator.pop(sheetContext);
                                        }
                                        _showMessage(
                                          "Bill settled successfully.",
                                        );
                                        unawaited(_fetchBills());
                                        unawaited(
                                          _printReceipt(
                                            bill,
                                            paymentMethodOverride:
                                                paymentMethod,
                                          ),
                                        );
                                      } else {
                                        _showMessage(
                                          result.message ??
                                              "Failed to settle bill.",
                                        );
                                      }
                                    }
                                  : () {
                                      if (!_canUpdateOrSettleBills) {
                                        _showMessage(
                                          "You don't have permission to settle this bill.",
                                        );
                                      } else if (pay == null) {
                                        _showMessage(
                                          "Payment method is required before settling the bill.",
                                        );
                                      } else if (billStatus != 'completed') {
                                        _showMessage(
                                          "Bill can be settled only after it is completed.",
                                        );
                                      }
                                    },
                              child: Text(
                                isSettling
                                    ? "PROCESSING..."
                                    : "BILL SETTLEMENT",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
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
      actions: const [PrinterSettingsAction()],
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
                  final status = bill.status.toLowerCase();
                  final isSettled = status == 'settled';
                  final isCompleted = status == 'completed';
                  final isPrepared = status == 'prepared';
                  final isCancelled = status == 'cancelled';
                  final isFinalBill = isCompleted || isSettled;
                  const completedTileColor = Color(0xFF3F0305);
                  final isTableOrder =
                      (bill.tableNumber?.trim().isNotEmpty ?? false) ||
                      (bill.section?.trim().isNotEmpty ?? false);
                  // KOT detection based on status or invoice number
                  final isKot =
                      !isFinalBill ||
                      bill.invoiceNumber.toUpperCase().contains('KOT');
                  final tileColor = isSettled
                      ? Colors.black
                      : isCancelled
                      ? Colors.red.shade700
                      : isCompleted
                      ? completedTileColor
                      : (isPrepared && isTableOrder)
                      ? Colors.green.shade700
                      : Colors.yellow;
                  final isYellowTile =
                      !isSettled &&
                      !isCompleted &&
                      !isCancelled &&
                      !(isPrepared && isTableOrder);
                  final runningTextColor = isYellowTile
                      ? Colors.black87
                      : Colors.white;
                  final showSettledTableTag =
                      isSettled &&
                      isTableOrder &&
                      (bill.tableNumber?.trim().isNotEmpty ?? false);

                  // Format display number
                  final raw = bill.invoiceNumber.split("-").last;
                  // If it's a KOT and doesn't explicitly say KOT in the number part, we can add it or just show the number.
                  // Usually raw will be something like '002' or 'KOT002'.
                  String displayNo = raw;
                  if (isKot && !raw.toUpperCase().startsWith('KOT')) {
                    final normalizedKotNo = RegExp(r'^\d+$').hasMatch(raw)
                        ? raw.padLeft(2, '0')
                        : raw;
                    displayNo = 'KOT$normalizedKotNo';
                  } else if (isKot) {
                    displayNo = raw.replaceAll(' ', '');
                  } else if (!isKot) {
                    // Pad only finalized bills if they are just numbers
                    if (RegExp(r'^\d+$').hasMatch(raw)) {
                      displayNo = raw.padLeft(3, '0');
                    }
                  }

                  return GestureDetector(
                    onTap: () => _showPaymentSheet(bill),
                    child: Container(
                      decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          if (!isSettled)
                            BoxShadow(
                              color: isCompleted
                                  ? completedTileColor.withOpacity(0.3)
                                  : Colors.amber.withOpacity(0.35),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (showSettledTableTag)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: Text(
                                  "T-${bill.tableNumber}",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (isKot) ...[
                              Text(
                                isCancelled ? "CANCELLED" : "RUNNING",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: runningTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (bill.tableNumber != null &&
                                  bill.tableNumber!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2.0,
                                  ),
                                  child: Text(
                                    "T-${bill.tableNumber}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: runningTextColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              Text(
                                displayNo,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: runningTextColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            if (!isKot)
                              Text(
                                displayNo,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

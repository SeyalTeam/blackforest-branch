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
  final double subTotal;
  final double cgstAmount;
  final double sgstAmount;
  final double totalAmountBeforeRoundOff;
  final double roundOffAmount;
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
  final String customerPhone;
  final String notes;
  final String status;
  final String? tableNumber;
  final String? section;
  final bool isExistingCustomer;
  final bool hasSubTotalField;
  final bool hasCgstAmountField;
  final bool hasSgstAmountField;
  final bool hasTotalAmountBeforeRoundOffField;
  final bool hasRoundOffAmountField;

  Bill({
    required this.id,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.subTotal,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.totalAmountBeforeRoundOff,
    required this.roundOffAmount,
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
    required this.customerPhone,
    required this.notes,
    required this.status,
    this.tableNumber,
    this.section,
    required this.isExistingCustomer,
    required this.hasSubTotalField,
    required this.hasCgstAmountField,
    required this.hasSgstAmountField,
    required this.hasTotalAmountBeforeRoundOffField,
    required this.hasRoundOffAmountField,
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

      bool toBool(dynamic value) {
        if (value is bool) return value;
        final raw = value?.toString().trim().toLowerCase();
        return raw == 'true' || raw == '1' || raw == 'yes';
      }

      bool hasValue(dynamic value) {
        if (value == null) return false;
        if (value is String) return value.trim().isNotEmpty;
        if (value is Map) return value.isNotEmpty;
        return true;
      }

      String formatAssigneeLabel(String value) {
        final trimmed = value.trim();
        final normalized = trimmed.toLowerCase();
        const assigneeLabelMap = {
          'ettroad@bf.com': 'Ettayapuram Road',
          'ettroad': 'Ettayapuram Road',
          'ettayapuram road': 'Ettayapuram Road',
          'etp-ettayapuram road': 'Ettayapuram Road',
        };
        return assigneeLabelMap[normalized] ?? trimmed;
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
          waiterName = formatAssigneeLabel(employee['name'].toString());
        } else if (createdByJson['email'] != null) {
          waiterName = formatAssigneeLabel(createdByJson['email'].toString());
        }
      }
      if (waiterName == 'Unknown' &&
          branchName.trim().isNotEmpty &&
          branchName != 'Unknown Branch') {
        waiterName = formatAssigneeLabel(branchName);
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
      final hasSubTotalField =
          (json.containsKey('subTotal') && json['subTotal'] != null) ||
          (json.containsKey('subtotal') && json['subtotal'] != null);
      final subTotal = toMoney(json['subTotal'] ?? json['subtotal']);
      final hasCgstAmountField =
          json.containsKey('cgstAmount') && json['cgstAmount'] != null;
      final cgstAmount = toMoney(json['cgstAmount']);
      final hasSgstAmountField =
          json.containsKey('sgstAmount') && json['sgstAmount'] != null;
      final sgstAmount = toMoney(json['sgstAmount']);
      final hasTotalAmountBeforeRoundOffField =
          json.containsKey('totalAmountBeforeRoundOff') &&
          json['totalAmountBeforeRoundOff'] != null;
      final totalAmountBeforeRoundOff = toMoney(
        json['totalAmountBeforeRoundOff'],
      );
      final hasRoundOffAmountField =
          json.containsKey('roundOffAmount') && json['roundOffAmount'] != null;
      final roundOffAmount = toMoney(json['roundOffAmount']);
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
      final customerPhone =
          (json['customerDetails']?['phoneNumber'] ??
                  json['customerDetails']?['phone'] ??
                  '')
              .toString()
              .trim();
      final customerDetails = json['customerDetails'];
      bool isExistingCustomer = false;
      if (customerDetails is Map<String, dynamic>) {
        final existingFlag =
            customerDetails['isExistingCustomer'] ??
            customerDetails['isExisting'] ??
            customerDetails['existingCustomer'] ??
            customerDetails['existing'];
        final customerReference =
            customerDetails['customerId'] ??
            customerDetails['customer'] ??
            customerDetails['id'] ??
            customerDetails['_id'];
        isExistingCustomer =
            toBool(existingFlag) || hasValue(customerReference);
      }
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
        subTotal: subTotal,
        cgstAmount: cgstAmount,
        sgstAmount: sgstAmount,
        totalAmountBeforeRoundOff: totalAmountBeforeRoundOff,
        roundOffAmount: roundOffAmount,
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
        customerPhone: customerPhone,
        notes: notes,
        status: status,
        tableNumber: tNum,
        section: tSec,
        isExistingCustomer: isExistingCustomer,
        hasSubTotalField: hasSubTotalField,
        hasCgstAmountField: hasCgstAmountField,
        hasSgstAmountField: hasSgstAmountField,
        hasTotalAmountBeforeRoundOffField: hasTotalAmountBeforeRoundOffField,
        hasRoundOffAmountField: hasRoundOffAmountField,
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
  final double unitTaxablePrice;
  final double taxableAmount;
  final double lineTotalInclusive;
  final double gstAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double gstPercent;

  const _ReceiptItemLine({
    required this.name,
    required this.quantity,
    required this.unitTaxablePrice,
    required this.taxableAmount,
    required this.lineTotalInclusive,
    required this.gstAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.gstPercent,
  });
}

class _ReceiptSummary {
  final List<_ReceiptItemLine> lines;
  final double receiptSubTotalAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double totalAmountBeforeRoundOff;
  final double totalAmount;
  final double roundOffAmount;
  final double billDiscount;
  final double remainingBillDiscount;

  const _ReceiptSummary({
    required this.lines,
    required this.receiptSubTotalAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.totalAmountBeforeRoundOff,
    required this.totalAmount,
    required this.roundOffAmount,
    required this.billDiscount,
    required this.remainingBillDiscount,
  });
}

class _CustomerFavoriteCardData {
  final String name;
  final double count;
  final DateTime lastVisit;
  final String? imageUrl;
  final String? review;

  const _CustomerFavoriteCardData({
    required this.name,
    required this.count,
    required this.lastVisit,
    required this.imageUrl,
    required this.review,
  });
}

class _ReviewedProductsLookupResult {
  final Set<String> keys;
  final Map<String, String> messagesByProductKey;
  final Map<String, String> messagesByBillProductKey;
  final Map<String, String> messagesByBillTimeProductKey;

  const _ReviewedProductsLookupResult({
    required this.keys,
    required this.messagesByProductKey,
    required this.messagesByBillProductKey,
    required this.messagesByBillTimeProductKey,
  });
}

class BillSheetPage extends StatefulWidget {
  const BillSheetPage({super.key});

  @override
  State<BillSheetPage> createState() => _BillSheetPageState();
}

class _BillSheetPageState extends State<BillSheetPage> {
  static final Map<String, List<Bill>> _sessionBillsCacheByBranch = {};
  static final Map<String, Map<String, bool>>
  _sessionExistingByBillCacheByBranch = {};
  static final Map<String, Map<String, bool>>
  _sessionPhoneHistoryCacheByBranch = {};
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
  Timer? _liveClockTimer;
  bool _isFetchingBills = false;
  bool _hasCompletedInitialLiveFetch = false;
  final ValueNotifier<DateTime> _liveNow = ValueNotifier(DateTime.now());
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
  final Map<String, bool> _existingCustomerByBillId = {};
  final Map<String, bool> _phoneHistoryCache = {};
  final Set<String> _phoneHistoryCheckedByDualField = {};
  String? _selectedWaiterName;
  String? _selectedBillType;
  String? _selectedTableNumber;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _fetchBills());
    _liveClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _liveNow.value = DateTime.now();
    });
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

    final currentBranchId = branchId!;
    _phoneHistoryCache
      ..clear()
      ..addAll(_sessionPhoneHistoryCacheByBranch[currentBranchId] ?? const {});
    final cachedBills = _sessionBillsCacheByBranch[currentBranchId];
    final cachedExistingByBill =
        _sessionExistingByBillCacheByBranch[currentBranchId];
    if (cachedBills != null && cachedBills.isNotEmpty && mounted) {
      setState(() {
        bills = List<Bill>.from(cachedBills);
        if (cachedExistingByBill != null && cachedExistingByBill.isNotEmpty) {
          _existingCustomerByBillId
            ..clear()
            ..addAll(cachedExistingByBill);
        }
        isLoading = false;
      });
      if (cachedExistingByBill == null || cachedExistingByBill.isEmpty) {
        unawaited(_enrichExistingCustomerFlags(cachedBills));
      }
    }

    // Do not block bill list rendering on branch/company request.
    unawaited(_fetchBranchDetails(token, currentBranchId));
    await _fetchBills();
  }

  Future<void> _fetchBills() async {
    final currentBranchId = branchId;
    if (currentBranchId == null || _isFetchingBills) return;
    _isFetchingBills = true;
    try {
      final result = await fetchBills(currentBranchId, token);
      final resolveBeforeFirstPaint = !_hasCompletedInitialLiveFetch;
      Map<String, bool>? resolvedExistingByBill;
      if (resolveBeforeFirstPaint) {
        resolvedExistingByBill = await _resolveExistingCustomerFlags(result);
      }
      if (!mounted) return;
      setState(() {
        bills = result;
        if (resolvedExistingByBill != null) {
          _existingCustomerByBillId
            ..clear()
            ..addAll(resolvedExistingByBill);
        }
        isLoading = false;
      });
      _sessionBillsCacheByBranch[currentBranchId] = List<Bill>.from(result);
      if (resolvedExistingByBill != null) {
        _sessionExistingByBillCacheByBranch[currentBranchId] =
            Map<String, bool>.from(resolvedExistingByBill);
        _sessionPhoneHistoryCacheByBranch[currentBranchId] =
            Map<String, bool>.from(_phoneHistoryCache);
      } else {
        unawaited(_enrichExistingCustomerFlags(result));
      }
      _hasCompletedInitialLiveFetch = true;
    } catch (_) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    } finally {
      _isFetchingBills = false;
    }
  }

  Future<bool> _phoneHasCustomerHistory(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return false;

    if (_phoneHistoryCache[normalized] == true) {
      return true;
    }
    if (_phoneHistoryCheckedByDualField.contains(normalized)) {
      return false;
    }

    try {
      final seenIds = <String>{};
      bool hasHistory = false;
      const queryFields = [
        'customerDetails.phoneNumber',
        'customerDetails.phone',
      ];
      for (final field in queryFields) {
        final uri = Uri.parse('${ApiConfig.baseUrl}/billings').replace(
          queryParameters: {
            'where[$field][equals]': normalized,
            'limit': '2',
            'depth': '0',
            'sort': '-createdAt',
          },
        );
        final response = await http.get(
          uri,
          headers: ApiConfig.getHeaders(token),
        );
        if (response.statusCode != 200) {
          continue;
        }
        final data = json.decode(response.body);
        if (data is! Map<String, dynamic>) {
          continue;
        }
        final docs = data['docs'];
        if (docs is! List) {
          continue;
        }
        for (final raw in docs) {
          if (raw is! Map<String, dynamic>) continue;
          final id = _extractIdValue(raw['_id'] ?? raw['id']);
          if (id.isNotEmpty) {
            seenIds.add(id);
          }
        }
        if (seenIds.length > 1) {
          hasHistory = true;
          break;
        }
        if (docs.length > 1 && seenIds.isEmpty) {
          hasHistory = true;
          break;
        }
      }
      _phoneHistoryCache[normalized] = hasHistory;
      _phoneHistoryCheckedByDualField.add(normalized);
      return hasHistory;
    } catch (_) {
      _phoneHistoryCache[normalized] = false;
      _phoneHistoryCheckedByDualField.add(normalized);
      return false;
    }
  }

  Future<Map<String, bool>> _resolveExistingCustomerFlags(
    List<Bill> sourceBills,
  ) async {
    final phones = sourceBills
        .where((bill) {
          final status = bill.status.toLowerCase().trim();
          // Include completed bills so E-RUNNING tiles render with the
          // correct blue color without waiting for history lookup on tap.
          return status != 'settled' && status != 'cancelled';
        })
        .map((bill) => bill.customerPhone.trim())
        .where((phone) => phone.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (phones.isNotEmpty) {
      await Future.wait(
        phones.map((phone) async {
          await _phoneHasCustomerHistory(phone);
        }),
      );
    }

    final nextByBillId = <String, bool>{};
    for (final bill in sourceBills) {
      final phone = bill.customerPhone.trim();
      final hasHistoryByPhone =
          phone.isNotEmpty && (_phoneHistoryCache[phone] ?? false);
      nextByBillId[bill.id] = bill.isExistingCustomer || hasHistoryByPhone;
    }
    return nextByBillId;
  }

  Future<void> _enrichExistingCustomerFlags(List<Bill> sourceBills) async {
    final nextByBillId = await _resolveExistingCustomerFlags(sourceBills);
    final currentBranchId = branchId;
    if (currentBranchId != null) {
      _sessionExistingByBillCacheByBranch[currentBranchId] =
          Map<String, bool>.from(nextByBillId);
      _sessionPhoneHistoryCacheByBranch[currentBranchId] =
          Map<String, bool>.from(_phoneHistoryCache);
    }
    if (!mounted) return;

    final mapUnchanged =
        nextByBillId.length == _existingCustomerByBillId.length &&
        nextByBillId.entries.every(
          (entry) => _existingCustomerByBillId[entry.key] == entry.value,
        );
    if (mapUnchanged) return;

    setState(() {
      _existingCustomerByBillId
        ..clear()
        ..addAll(nextByBillId);
    });
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

  double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  bool _hasField(Map<dynamic, dynamic>? map, String key) {
    return map != null && map.containsKey(key) && map[key] != null;
  }

  List<int> _splitTaxPaise(int taxPaise) {
    final safeTaxPaise = taxPaise < 0 ? 0 : taxPaise;
    final cgstPaise = safeTaxPaise ~/ 2;
    final sgstPaise = safeTaxPaise - cgstPaise;
    return [cgstPaise, sgstPaise];
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

  String _formatRunningElapsedClock(DateTime createdAt, DateTime now) {
    final diff = now.difference(createdAt);
    final safeDiff = diff.isNegative ? Duration.zero : diff;
    final totalMinutes = safeDiff.inMinutes;
    final seconds = safeDiff.inSeconds % 60;
    return '$totalMinutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatReceiptMoney(double value) {
    final rounded = double.parse(value.toStringAsFixed(2));
    if ((rounded - rounded.truncateToDouble()).abs() < 0.001) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(2);
  }

  String _formatReceiptPercent(double value) {
    final normalized = _roundMoney(value);
    String text = normalized.toStringAsFixed(2);
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text%';
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

  bool _isSameBill(Bill a, Bill b) {
    final aId = a.id.trim();
    final bId = b.id.trim();
    if (aId.isNotEmpty && bId.isNotEmpty && aId == bId) {
      return true;
    }

    final aInvoice = a.invoiceNumber.trim().toUpperCase();
    final bInvoice = b.invoiceNumber.trim().toUpperCase();
    if (aInvoice.isNotEmpty && bInvoice.isNotEmpty && aInvoice == bInvoice) {
      return true;
    }

    final sameTime = a.createdAt.difference(b.createdAt).inSeconds.abs() <= 1;
    final sameAmount = (a.totalAmount - b.totalAmount).abs() < 0.001;
    final aTable = (a.tableNumber ?? '').trim();
    final bTable = (b.tableNumber ?? '').trim();
    return sameTime && sameAmount && aTable == bTable;
  }

  Future<List<Bill>> _fetchCustomerHistoryBills(
    String phone, {
    String? excludeBillId,
    Bill? excludeBill,
  }) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return [];

    final headers = ApiConfig.getHeaders(token);
    const pageLimit = 100;
    final queryFields = [
      'customerDetails.phoneNumber',
      'customerDetails.phone',
    ];

    final seenIds = <String>{};
    final history = <Bill>[];

    for (final field in queryFields) {
      var page = 1;
      var totalPages = 1;

      while (page <= totalPages) {
        try {
          final uri = Uri.parse('${ApiConfig.baseUrl}/billings').replace(
            queryParameters: {
              'where[$field][equals]': normalized,
              'limit': '$pageLimit',
              'page': '$page',
              'sort': '-createdAt',
              'depth': '2',
            },
          );
          final response = await http.get(uri, headers: headers);
          if (response.statusCode != 200) break;
          final data = json.decode(response.body);
          if (data is! Map<String, dynamic>) break;
          final docs = data['docs'];
          if (docs is! List) break;
          totalPages = (data['totalPages'] is num)
              ? (data['totalPages'] as num).toInt()
              : totalPages;

          for (final raw in docs) {
            if (raw is! Map<String, dynamic>) continue;
            try {
              final bill = Bill.fromJson(raw);
              if (excludeBill != null && _isSameBill(bill, excludeBill)) {
                continue;
              }
              if (excludeBillId != null &&
                  excludeBillId.isNotEmpty &&
                  bill.id == excludeBillId) {
                continue;
              }
              if (seenIds.add(bill.id)) {
                history.add(bill);
              }
            } catch (_) {}
          }
          page += 1;
        } catch (_) {
          break;
        }
      }
    }

    history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (excludeBillId != null && excludeBillId.isNotEmpty) {
      _phoneHistoryCache[normalized] = history.isNotEmpty;
      _phoneHistoryCheckedByDualField.add(normalized);
    }
    return history;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _extractIdValue(dynamic value) {
    if (value is String) return value.trim();
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return (map['id'] ?? map['_id'] ?? map[r'$oid'] ?? '').toString().trim();
    }
    return '';
  }

  String _normalizePhoneValue(dynamic value) {
    if (value == null) return '';
    final digits = value.toString().replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  List<String> _phoneCandidates(String normalizedPhone) {
    final candidates = <String>{};
    final trimmed = normalizedPhone.trim();
    if (trimmed.isNotEmpty) candidates.add(trimmed);
    if (trimmed.length > 10) {
      candidates.add(trimmed.substring(trimmed.length - 10));
    }
    return candidates.toList();
  }

  Set<String> _collectBillIds(List<Bill> sourceBills) {
    final ids = <String>{};
    for (final bill in sourceBills) {
      final billId = bill.id.trim();
      if (billId.isNotEmpty) ids.add(billId);
      final invoice = bill.invoiceNumber.trim();
      if (invoice.isNotEmpty) ids.add(invoice);
    }
    return ids;
  }

  String _extractReviewBillId(Map<String, dynamic> reviewDoc) {
    final billValue = reviewDoc['bill'];
    if (billValue is String) return billValue.trim();
    if (billValue is Map) {
      final billMap = Map<String, dynamic>.from(billValue);
      final id = _extractIdValue(billMap['id'] ?? billMap['_id']);
      if (id.isNotEmpty) return id;
      return (billMap['invoiceNumber'] ?? billMap['kotNumber'] ?? '')
          .toString()
          .trim();
    }
    return '';
  }

  String _extractReviewBillUpdatedAt(Map<String, dynamic> reviewDoc) {
    final billValue = reviewDoc['bill'];
    if (billValue is! Map) return '';
    final billMap = Map<String, dynamic>.from(billValue);
    return (billMap['updatedAt'] ?? billMap['createdAt'] ?? '')
        .toString()
        .trim();
  }

  String _extractReviewPhoneFromBill(Map<String, dynamic> reviewDoc) {
    final billValue = reviewDoc['bill'];
    if (billValue is! Map) return '';
    final billMap = Map<String, dynamic>.from(billValue);
    final customerDetails = _asMap(billMap['customerDetails']);
    return _normalizePhoneValue(
      customerDetails?['phoneNumber'] ??
          customerDetails?['phone'] ??
          billMap['customerPhone'] ??
          billMap['phoneNumber'],
    );
  }

  bool _reviewDocBelongsToCustomer(
    Map<String, dynamic> reviewDoc, {
    required Set<String> normalizedPhoneSet,
    required Set<String> allowedBillIds,
  }) {
    final reviewPhone = _normalizePhoneValue(reviewDoc['customerPhone']);
    final billPhone = _extractReviewPhoneFromBill(reviewDoc);
    final reviewBillId = _extractReviewBillId(reviewDoc);

    final matchesPhone =
        (reviewPhone.isNotEmpty && normalizedPhoneSet.contains(reviewPhone)) ||
        (billPhone.isNotEmpty && normalizedPhoneSet.contains(billPhone));
    final matchesBill =
        reviewBillId.isNotEmpty && allowedBillIds.contains(reviewBillId);
    return matchesPhone || matchesBill;
  }

  bool _isPositiveReviewItem(Map<String, dynamic> reviewItem) {
    final rating = _toDouble(
      reviewItem['rating'] ??
          reviewItem['ratingValue'] ??
          reviewItem['reviewRating'] ??
          reviewItem['stars'] ??
          reviewItem['starRating'],
    );
    if (rating > 0) return true;
    return _extractReviewMessage(reviewItem).isNotEmpty;
  }

  String _extractReviewMessage(Map<String, dynamic> reviewItem) {
    final message =
        (reviewItem['feedback'] ??
                reviewItem['review'] ??
                reviewItem['comment'] ??
                reviewItem['message'] ??
                reviewItem['text'])
            ?.toString()
            .trim() ??
        '';
    if (message.isEmpty) return '';
    return message.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<Map<String, dynamic>> _extractReviewDocsFromPayload(dynamic payload) {
    if (payload is! Map) return const [];
    final map = Map<String, dynamic>.from(payload);
    final data = _asMap(map['data']);
    final result = _asMap(map['result']);
    final candidates = <dynamic>[
      map['docs'],
      map['reviews'],
      map['items'],
      data?['docs'],
      data?['reviews'],
      result?['docs'],
      result?['reviews'],
    ];
    for (final candidate in candidates) {
      if (candidate is! List || candidate.isEmpty) continue;
      final docs = <Map<String, dynamic>>[];
      for (final entry in candidate) {
        if (entry is Map) docs.add(Map<String, dynamic>.from(entry));
      }
      if (docs.isNotEmpty) return docs;
    }
    return const [];
  }

  String _billProductReviewKey(String billId, String productKey) {
    return '$billId|$productKey';
  }

  String _billTimeProductReviewKey(String billUpdatedAt, String productKey) {
    return '$billUpdatedAt|$productKey';
  }

  void _addBillKeyCandidate(Set<String> output, dynamic value) {
    final key = value?.toString().trim() ?? '';
    if (key.isNotEmpty) output.add(key);
  }

  Set<String> _reviewBillKeyCandidatesFromReviewDoc(
    Map<String, dynamic> reviewDoc,
  ) {
    final keys = <String>{};
    final billValue = reviewDoc['bill'];
    if (billValue is String) {
      _addBillKeyCandidate(keys, billValue);
      return keys;
    }
    if (billValue is Map) {
      final billMap = Map<String, dynamic>.from(billValue);
      _addBillKeyCandidate(keys, billMap['id']);
      _addBillKeyCandidate(keys, billMap['_id']);
      _addBillKeyCandidate(keys, billMap['invoiceNumber']);
      _addBillKeyCandidate(keys, billMap['kotNumber']);
    }
    return keys;
  }

  void _addReviewedKeysFromReviewDoc(
    Map<String, dynamic> reviewDoc,
    Set<String> output,
    Map<String, String> messagesByProductKey,
    Map<String, String> messagesByBillProductKey,
    Map<String, String> messagesByBillTimeProductKey,
  ) {
    final reviewItems = reviewDoc['items'];
    if (reviewItems is! List) return;
    final billKeys = _reviewBillKeyCandidatesFromReviewDoc(reviewDoc);
    final billUpdatedAt = _extractReviewBillUpdatedAt(reviewDoc);

    for (final raw in reviewItems) {
      if (raw is! Map) continue;
      final reviewItem = Map<String, dynamic>.from(raw);
      if (!_isPositiveReviewItem(reviewItem)) continue;
      final reviewMessage = _extractReviewMessage(reviewItem);

      final product = _asMap(reviewItem['product']);
      final productId = _extractIdValue(
        reviewItem['productId'] ??
            reviewItem['productID'] ??
            reviewItem['itemId'] ??
            product?['id'] ??
            product?['_id'] ??
            reviewItem['product'],
      );
      final productName =
          (reviewItem['name'] ?? reviewItem['productName'] ?? product?['name'])
              ?.toString()
              .trim();
      final nameKey = (productName != null && productName.isNotEmpty)
          ? 'name:${productName.toLowerCase()}'
          : null;

      if (productId.isNotEmpty) {
        final idKey = 'id:$productId';
        output.add(idKey);
        if (reviewMessage.isNotEmpty &&
            !messagesByProductKey.containsKey(idKey)) {
          messagesByProductKey[idKey] = reviewMessage;
        }
        if (reviewMessage.isNotEmpty && billKeys.isNotEmpty) {
          for (final billKey in billKeys) {
            final billProductKey = _billProductReviewKey(billKey, idKey);
            if (!messagesByBillProductKey.containsKey(billProductKey)) {
              messagesByBillProductKey[billProductKey] = reviewMessage;
            }
            if (nameKey != null) {
              final nameBillProductKey = _billProductReviewKey(
                billKey,
                nameKey,
              );
              if (!messagesByBillProductKey.containsKey(nameBillProductKey)) {
                messagesByBillProductKey[nameBillProductKey] = reviewMessage;
              }
            }
          }
        }
        if (reviewMessage.isNotEmpty && billUpdatedAt.isNotEmpty) {
          final timeProductKey = _billTimeProductReviewKey(
            billUpdatedAt,
            idKey,
          );
          if (!messagesByBillTimeProductKey.containsKey(timeProductKey)) {
            messagesByBillTimeProductKey[timeProductKey] = reviewMessage;
          }
          if (nameKey != null) {
            final nameTimeProductKey = _billTimeProductReviewKey(
              billUpdatedAt,
              nameKey,
            );
            if (!messagesByBillTimeProductKey.containsKey(nameTimeProductKey)) {
              messagesByBillTimeProductKey[nameTimeProductKey] = reviewMessage;
            }
          }
        }
      } else if (nameKey != null) {
        output.add(nameKey);
        if (reviewMessage.isNotEmpty &&
            !messagesByProductKey.containsKey(nameKey)) {
          messagesByProductKey[nameKey] = reviewMessage;
        }
        if (reviewMessage.isNotEmpty && billKeys.isNotEmpty) {
          for (final billKey in billKeys) {
            final billProductKey = _billProductReviewKey(billKey, nameKey);
            if (!messagesByBillProductKey.containsKey(billProductKey)) {
              messagesByBillProductKey[billProductKey] = reviewMessage;
            }
          }
        }
        if (reviewMessage.isNotEmpty && billUpdatedAt.isNotEmpty) {
          final timeProductKey = _billTimeProductReviewKey(
            billUpdatedAt,
            nameKey,
          );
          if (!messagesByBillTimeProductKey.containsKey(timeProductKey)) {
            messagesByBillTimeProductKey[timeProductKey] = reviewMessage;
          }
        }
      }
    }
  }

  Future<_ReviewedProductsLookupResult> _fetchReviewedProductKeysForPhone(
    String normalizedPhone, {
    List<Bill>? knownBills,
  }) async {
    final keys = <String>{};
    final messagesByProductKey = <String, String>{};
    final messagesByBillProductKey = <String, String>{};
    final messagesByBillTimeProductKey = <String, String>{};
    final phoneValues = _phoneCandidates(normalizedPhone);
    final normalizedPhoneSet = phoneValues
        .map(_normalizePhoneValue)
        .where((value) => value.isNotEmpty)
        .toSet();
    final allowedBillIds = _collectBillIds(knownBills ?? const []);
    final headers = ApiConfig.getHeaders(token);

    for (final phone in phoneValues) {
      for (var page = 1; page <= 12; page++) {
        final uri = Uri.parse('${ApiConfig.baseUrl}/reviews').replace(
          queryParameters: {
            'sort': '-createdAt',
            'page': page.toString(),
            'limit': '100',
            'depth': '2',
            'where[customerPhone][equals]': phone,
          },
        );
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) break;

        final decoded = jsonDecode(response.body);
        final reviewDocs = _extractReviewDocsFromPayload(decoded);
        if (reviewDocs.isEmpty) break;

        for (final reviewDoc in reviewDocs) {
          if (!_reviewDocBelongsToCustomer(
            reviewDoc,
            normalizedPhoneSet: normalizedPhoneSet,
            allowedBillIds: allowedBillIds,
          )) {
            continue;
          }
          _addReviewedKeysFromReviewDoc(
            reviewDoc,
            keys,
            messagesByProductKey,
            messagesByBillProductKey,
            messagesByBillTimeProductKey,
          );
        }

        if (reviewDocs.length < 100) break;
      }
    }

    return _ReviewedProductsLookupResult(
      keys: keys,
      messagesByProductKey: messagesByProductKey,
      messagesByBillProductKey: messagesByBillProductKey,
      messagesByBillTimeProductKey: messagesByBillTimeProductKey,
    );
  }

  Future<void> _showCustomerHistorySheet(
    String phone,
    List<Bill> history, {
    String? currentBillId,
    _ReviewedProductsLookupResult? reviewedLookup,
  }) async {
    final historyBillCount = history.length;
    final historyTotalAmount = history.fold<double>(
      0.0,
      (sum, bill) => sum + _toNonNegativeMoney(bill.totalAmount),
    );
    final favorites = _buildCustomerFavorites(
      history,
      reviewedLookup: reviewedLookup,
    );
    bool showFavorites = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            final dialogTitle = showFavorites
                ? "Customer Favorite's"
                : 'Customer History';
            final toggleIcon = showFavorites
                ? Icons.receipt_long_rounded
                : Icons.grid_view_rounded;

            return Dialog(
              backgroundColor: const Color(0xFF1E1E22),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: SizedBox(
                width: double.infinity,
                height: MediaQuery.of(ctx).size.height * 0.84,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dialogTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => dialogSetState(
                              () => showFavorites = !showFavorites,
                            ),
                            icon: Icon(toggleIcon, color: Colors.white70),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 12),
                      Expanded(
                        child: showFavorites
                            ? _buildCustomerFavoritesGrid(favorites)
                            : history.isEmpty
                            ? Center(
                                child: Text(
                                  'No customer history found',
                                  style: TextStyle(color: Colors.grey.shade400),
                                ),
                              )
                            : ListView.builder(
                                itemCount: history.length,
                                itemBuilder: (_, index) {
                                  final h = history[index];
                                  final isCurrent =
                                      currentBillId != null &&
                                      currentBillId.isNotEmpty &&
                                      currentBillId == h.id;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCurrent
                                            ? const Color(0xFF1FAE4B)
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: _buildReceiptPreviewPanel(h),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1FAE4B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          'Total Amount: ${_formatReceiptMoney(historyTotalAmount)} ($historyBillCount ${historyBillCount == 1 ? 'Bill' : 'Bills'})',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String? _productKeyFromFavoriteItem(
    Map<String, dynamic> item, {
    Map<String, dynamic>? product,
    String? fallbackName,
  }) {
    final productMap = product ?? _asMap(item['product']);
    final productId = _extractIdValue(
      productMap?['id'] ??
          productMap?['_id'] ??
          item['productId'] ??
          item['product'],
    );
    if (productId.isNotEmpty) return 'id:$productId';

    final itemName =
        (fallbackName ??
                item['name'] ??
                productMap?['name'] ??
                item['productName'] ??
                '')
            .toString()
            .trim();
    if (itemName.isEmpty) return null;
    return 'name:${itemName.toLowerCase()}';
  }

  Set<String> _billKeyCandidatesFromBillEntity(Bill bill) {
    final keys = <String>{};
    _addBillKeyCandidate(keys, bill.id);
    _addBillKeyCandidate(keys, bill.invoiceNumber);
    return keys;
  }

  String? _resolveFavoriteReviewMessage({
    required Bill bill,
    required String productKey,
    required String nameKey,
    required _ReviewedProductsLookupResult reviewedLookup,
  }) {
    final byBillProduct = reviewedLookup.messagesByBillProductKey;
    final byBillTimeProduct = reviewedLookup.messagesByBillTimeProductKey;
    final byProduct = reviewedLookup.messagesByProductKey;
    final billKeys = _billKeyCandidatesFromBillEntity(bill);
    for (final billKey in billKeys) {
      final direct = byBillProduct[_billProductReviewKey(billKey, productKey)];
      if (direct != null && direct.trim().isNotEmpty) return direct.trim();
      final byName = byBillProduct[_billProductReviewKey(billKey, nameKey)];
      if (byName != null && byName.trim().isNotEmpty) return byName.trim();
    }

    final billTimeCandidates = <String>{
      bill.createdAt.toIso8601String(),
      bill.createdAt.toUtc().toIso8601String(),
    };
    for (final billTime in billTimeCandidates) {
      final direct =
          byBillTimeProduct[_billTimeProductReviewKey(billTime, productKey)];
      if (direct != null && direct.trim().isNotEmpty) return direct.trim();
      final byName =
          byBillTimeProduct[_billTimeProductReviewKey(billTime, nameKey)];
      if (byName != null && byName.trim().isNotEmpty) return byName.trim();
    }

    final productMessage = byProduct[productKey];
    if (productMessage != null && productMessage.trim().isNotEmpty) {
      return productMessage.trim();
    }
    final nameMessage = byProduct[nameKey];
    if (nameMessage != null && nameMessage.trim().isNotEmpty) {
      return nameMessage.trim();
    }
    return null;
  }

  List<_CustomerFavoriteCardData> _buildCustomerFavorites(
    List<Bill> history, {
    _ReviewedProductsLookupResult? reviewedLookup,
  }) {
    final aggregate = <String, _CustomerFavoriteCardData>{};
    final sortedHistory = List<Bill>.from(history)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final lookup =
        reviewedLookup ??
        const _ReviewedProductsLookupResult(
          keys: <String>{},
          messagesByProductKey: <String, String>{},
          messagesByBillProductKey: <String, String>{},
          messagesByBillTimeProductKey: <String, String>{},
        );

    for (final bill in sortedHistory) {
      for (final raw in bill.items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final product = _asMap(item['product']);
        final name = _extractItemName(item).trim();
        if (name.isEmpty) continue;
        final normalizedNameKey =
            'name:${name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}';
        final key =
            _productKeyFromFavoriteItem(
              item,
              product: product,
              fallbackName: name,
            ) ??
            normalizedNameKey;
        final qty = _toDouble(item['quantity']);
        final count = qty > 0 ? qty : 1.0;
        final imageUrl = _extractFavoriteImageUrl(item);
        final review = _resolveFavoriteReviewMessage(
          bill: bill,
          productKey: key,
          nameKey: normalizedNameKey,
          reviewedLookup: lookup,
        );
        final existing = aggregate[key];

        if (existing == null) {
          aggregate[key] = _CustomerFavoriteCardData(
            name: name,
            count: count,
            lastVisit: bill.createdAt.toLocal(),
            imageUrl: imageUrl,
            review: review,
          );
          continue;
        }

        final mergedCount = existing.count + count;
        final isLatest = bill.createdAt.isAfter(existing.lastVisit);
        final mergedLastVisit = isLatest
            ? bill.createdAt.toLocal()
            : existing.lastVisit;
        final mergedImage =
            (existing.imageUrl == null || existing.imageUrl!.trim().isEmpty)
            ? imageUrl
            : existing.imageUrl;
        final hasExistingReview = existing.review?.trim().isNotEmpty ?? false;
        final mergedReview = hasExistingReview ? existing.review : review;

        aggregate[key] = _CustomerFavoriteCardData(
          name: existing.name,
          count: mergedCount,
          lastVisit: mergedLastVisit,
          imageUrl: mergedImage,
          review: mergedReview,
        );
      }
    }

    final favorites = aggregate.values.toList();
    favorites.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return b.lastVisit.compareTo(a.lastVisit);
    });
    return favorites;
  }

  String? _normalizeFavoriteImageUrl(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '${ApiConfig.domain}$value';
    }
    return null;
  }

  String? _extractFavoriteImageUrl(Map<String, dynamic> item) {
    final direct = _normalizeFavoriteImageUrl(
      item['imageUrl'] ??
          item['image']?['url'] ??
          item['thumbnail']?['url'] ??
          item['photo']?['url'],
    );
    if (direct != null) return direct;

    final product = item['product'];
    if (product is Map) {
      final productMap = Map<String, dynamic>.from(product);
      final fromProduct = _normalizeFavoriteImageUrl(
        productMap['imageUrl'] ??
            productMap['image']?['url'] ??
            productMap['thumbnail']?['url'] ??
            productMap['photo']?['url'],
      );
      if (fromProduct != null) return fromProduct;

      final images = productMap['images'];
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map) {
          return _normalizeFavoriteImageUrl(
            first['image'] is Map ? first['image']['url'] : first['url'],
          );
        }
      }
    }

    return null;
  }

  String _formatFavoriteCount(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.001) {
      return rounded.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _formatFavoriteLastVisit(DateTime when) {
    final local = when.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    int hour = local.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day-$month-$year $hour:$minute $ampm';
  }

  Widget _buildCustomerFavoritesGrid(
    List<_CustomerFavoriteCardData> favorites,
  ) {
    if (favorites.isEmpty) {
      return Center(
        child: Text(
          'No favorite items found',
          style: TextStyle(color: Colors.grey.shade400),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.86,
      ),
      itemCount: favorites.length,
      itemBuilder: (_, index) {
        final favorite = favorites[index];
        final reviewText = favorite.review?.trim();
        final hasReview = reviewText != null && reviewText.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2B30),
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: favorite.imageUrl != null
                          ? Image.network(
                              favorite.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFE8ECEB),
                                child: const Icon(
                                  Icons.fastfood,
                                  color: Color(0xFF9CA3AF),
                                  size: 48,
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFE8ECEB),
                              child: const Icon(
                                Icons.fastfood,
                                color: Color(0xFF9CA3AF),
                                size: 48,
                              ),
                            ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              favorite.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Last Visit: ${_formatFavoriteLastVisit(favorite.lastVisit)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1FAE4B),
                                fontSize: 8.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 52,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1FAE4B),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white, width: 1.3),
                          ),
                          child: Text(
                            'Count: ${_formatFavoriteCount(favorite.count)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: hasReview ? 30 : 16,
              child: hasReview
                  ? Text(
                      'Review: $reviewText',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF93D8A7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
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

  double _extractItemFinalLineTotal(dynamic item, double qty, double unitPrice) {
    if (item is! Map) return qty * unitPrice;
    final direct = _toDouble(
      item['finalLineTotal'] ??
          item['lineTotalInclusive'] ??
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

    final lines = <_ReceiptItemLine>[];
    int receiptSubTotalPaise = 0;
    int cgstAmountPaise = 0;
    int sgstAmountPaise = 0;
    int totalBeforeRoundOffPaise = 0;

    for (final rawItem in bill.items) {
      final item = rawItem is Map ? rawItem : null;
      final quantity = _toDouble(item?['quantity'] ?? item?['qty'] ?? 1);
      final safeQuantity = quantity > 0 ? quantity : 1.0;
      final unitPrice = _extractItemUnitPrice(rawItem);
      final lineTotalInclusive = _extractItemFinalLineTotal(
        rawItem,
        safeQuantity,
        unitPrice,
      );
      final gstPercent = _extractItemGstPercent(rawItem);
      final effectiveLineTotalInclusive = lineTotalInclusive
          .clamp(0.0, double.infinity)
          .toDouble();
      final lineTotalInclusivePaise = (effectiveLineTotalInclusive * 100).round();

      final hasTaxableAmount = _hasField(item, 'taxableAmount');
      final hasGstAmount = _hasField(item, 'gstAmount');
      final hasCgstAmount = _hasField(item, 'cgstAmount');
      final hasSgstAmount = _hasField(item, 'sgstAmount');

      int taxableAmountPaise;
      if (hasTaxableAmount) {
        taxableAmountPaise = (_toDouble(item!['taxableAmount']) * 100).round();
      } else if (gstPercent > 0) {
        taxableAmountPaise =
            ((lineTotalInclusivePaise * 100) / (100 + gstPercent)).round();
      } else {
        taxableAmountPaise = lineTotalInclusivePaise;
      }
      taxableAmountPaise = taxableAmountPaise.clamp(0, lineTotalInclusivePaise);

      int gstAmountPaise;
      if (hasGstAmount) {
        gstAmountPaise = (_toDouble(item!['gstAmount']) * 100).round();
      } else {
        gstAmountPaise = (lineTotalInclusivePaise - taxableAmountPaise).clamp(
          0,
          lineTotalInclusivePaise,
        );
      }

      int cgstPaise = 0;
      int sgstPaise = 0;
      if (hasCgstAmount) {
        cgstPaise = (_toDouble(item!['cgstAmount']) * 100).round();
      }
      if (hasSgstAmount) {
        sgstPaise = (_toDouble(item!['sgstAmount']) * 100).round();
      }

      if (hasCgstAmount && !hasSgstAmount) {
        sgstPaise = (gstAmountPaise - cgstPaise).clamp(0, gstAmountPaise);
      } else if (!hasCgstAmount && hasSgstAmount) {
        cgstPaise = (gstAmountPaise - sgstPaise).clamp(0, gstAmountPaise);
      } else if (!hasCgstAmount && !hasSgstAmount) {
        final split = _splitTaxPaise(gstAmountPaise);
        cgstPaise = split[0];
        sgstPaise = split[1];
      }

      if (cgstPaise + sgstPaise != gstAmountPaise) {
        final split = _splitTaxPaise(gstAmountPaise);
        cgstPaise = split[0];
        sgstPaise = split[1];
      }

      receiptSubTotalPaise += taxableAmountPaise;
      cgstAmountPaise += cgstPaise;
      sgstAmountPaise += sgstPaise;
      totalBeforeRoundOffPaise += lineTotalInclusivePaise;

      lines.add(
        _ReceiptItemLine(
          name: _extractItemName(rawItem),
          quantity: safeQuantity,
          unitTaxablePrice: _roundMoney(
            (taxableAmountPaise / 100) / safeQuantity,
          ),
          taxableAmount: _roundMoney(taxableAmountPaise / 100),
          lineTotalInclusive: _roundMoney(lineTotalInclusivePaise / 100),
          gstAmount: _roundMoney(gstAmountPaise / 100),
          cgstAmount: _roundMoney(cgstPaise / 100),
          sgstAmount: _roundMoney(sgstPaise / 100),
          gstPercent: gstPercent,
        ),
      );
    }

    final fallbackSubTotalAmount = _roundMoney(receiptSubTotalPaise / 100);
    final fallbackCgstAmount = _roundMoney(cgstAmountPaise / 100);
    final fallbackSgstAmount = _roundMoney(sgstAmountPaise / 100);
    final fallbackTotalAmountBeforeRoundOff = _roundMoney(
      totalBeforeRoundOffPaise / 100,
    );

    final receiptSubTotalAmount = bill.hasSubTotalField
        ? _toNonNegativeMoney(bill.subTotal)
        : fallbackSubTotalAmount;
    final receiptCgstAmount = bill.hasCgstAmountField
        ? _toNonNegativeMoney(bill.cgstAmount)
        : fallbackCgstAmount;
    final receiptSgstAmount = bill.hasSgstAmountField
        ? _toNonNegativeMoney(bill.sgstAmount)
        : fallbackSgstAmount;
    final totalAmountBeforeRoundOff = bill.hasTotalAmountBeforeRoundOffField
        ? _toNonNegativeMoney(bill.totalAmountBeforeRoundOff)
        : fallbackTotalAmountBeforeRoundOff;

    double payableTotalAmount = totalAmount;
    if (payableTotalAmount <= 0 && totalAmountBeforeRoundOff > 0) {
      payableTotalAmount = _roundMoney(totalAmountBeforeRoundOff.roundToDouble());
    }

    final roundOffAmount = bill.hasRoundOffAmountField
        ? _toDouble(bill.roundOffAmount)
        : _roundMoney(payableTotalAmount - totalAmountBeforeRoundOff);
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
      receiptSubTotalAmount: receiptSubTotalAmount,
      cgstAmount: receiptCgstAmount,
      sgstAmount: receiptSgstAmount,
      totalAmountBeforeRoundOff: totalAmountBeforeRoundOff,
      totalAmount: payableTotalAmount,
      roundOffAmount: roundOffAmount,
      billDiscount: billDiscount,
      remainingBillDiscount: remainingBillDiscount,
    );
  }

  Widget _buildReceiptPreviewPanel(
    Bill bill, {
    String? selectedPaymentMethod,
    bool showCustomerHistoryButton = false,
    bool isCustomerHistoryLoading = false,
    VoidCallback? onCustomerHistoryTap,
  }) {
    final billDateTime = bill.createdAt.toLocal();
    final dateStr = _buildReceiptDate(billDateTime);
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
            if (showCustomerHistoryButton) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FAE4B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isCustomerHistoryLoading
                      ? null
                      : onCustomerHistoryTap,
                  icon: isCustomerHistoryLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.history, size: 18),
                  label: const Text(
                    'CUSTOMER HISTORY',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
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
                        _formatReceiptMoney(line.unitTaxablePrice),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatReceiptPercent(line.gstPercent),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatReceiptMoney(line.taxableAmount),
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
            if (summary.cgstAmount > 0.0001)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'CGST RS ${_formatReceiptMoney(summary.cgstAmount)}',
                ),
              ),
            if (summary.sgstAmount > 0.0001)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'SGST RS ${_formatReceiptMoney(summary.sgstAmount)}',
                ),
              ),
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
                  'GRAND TOTAL RS ${_formatReceiptMoney(summary.totalAmount)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            Divider(height: 10, thickness: 1.2),
            if (bill.customerName.isNotEmpty ||
                bill.customerPhone.isNotEmpty) ...[
              Divider(height: 12, thickness: 1),
              if (bill.customerName.isNotEmpty)
                Text('Customer: ${bill.customerName}'),
              if (bill.customerPhone.isNotEmpty)
                Text('Phone: ${bill.customerPhone}'),
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
        purpose: PrintPurpose.billing,
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
              text: _formatReceiptMoney(line.unitTaxablePrice),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: _formatReceiptPercent(line.gstPercent),
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: _formatReceiptMoney(line.taxableAmount),
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

        if (summary.cgstAmount > 0.0001) {
          printer.row([
            PosColumn(
              text: 'CGST RS ${_formatReceiptMoney(summary.cgstAmount)}',
              width: 12,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
        if (summary.sgstAmount > 0.0001) {
          printer.row([
            PosColumn(
              text: 'SGST RS ${_formatReceiptMoney(summary.sgstAmount)}',
              width: 12,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
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
                'GRAND TOTAL RS ${_formatReceiptMoney(summary.totalAmount)}',
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
    _liveClockTimer?.cancel();
    _liveNow.dispose();
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
        bool isHistoryLoading = false;
        final normalizedPhone = bill.customerPhone.trim();
        bool showCustomerHistoryButton =
            normalizedPhone.isNotEmpty &&
            (_phoneHistoryCache[normalizedPhone] ?? false);
        bool hasCheckedHistoryAvailability = _phoneHistoryCache.containsKey(
          normalizedPhone,
        );
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
            if (!hasCheckedHistoryAvailability &&
                normalizedPhone.isNotEmpty &&
                !showCustomerHistoryButton) {
              hasCheckedHistoryAvailability = true;
              unawaited(() async {
                final history = await _fetchCustomerHistoryBills(
                  normalizedPhone,
                  excludeBillId: bill.id,
                  excludeBill: bill,
                );
                final hasHistory = history.isNotEmpty;
                if (!mounted || !statefulContext.mounted) return;
                sheetSetState(() => showCustomerHistoryButton = hasHistory);
              }());
            }

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
            final screenHeight = MediaQuery.of(statefulContext).size.height;
            final maxSheetHeight = screenHeight * 0.85;

            return SafeArea(
              top: false,
              child: Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: 450,
                    maxHeight: maxSheetHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Container(
                              margin: EdgeInsets.symmetric(vertical: 12),
                              color: Colors.grey.shade200,
                              padding: EdgeInsets.all(8),
                              child: _buildReceiptPreviewPanel(
                        bill,
                        selectedPaymentMethod: pay,
                        showCustomerHistoryButton: showCustomerHistoryButton,
                        isCustomerHistoryLoading: isHistoryLoading,
                        onCustomerHistoryTap: () async {
                          final phone = bill.customerPhone.trim();
                          if (phone.isEmpty) {
                            _showMessage(
                              'No customer mobile number in this bill.',
                            );
                            return;
                          }

                          sheetSetState(() => isHistoryLoading = true);
                          final history = await _fetchCustomerHistoryBills(
                            phone,
                            excludeBillId: bill.id,
                            excludeBill: bill,
                          );
                          if (!mounted || !statefulContext.mounted) return;

                          if (history.isEmpty) {
                            sheetSetState(() => isHistoryLoading = false);
                            sheetSetState(
                              () => showCustomerHistoryButton = false,
                            );
                            _showMessage('No previous customer history found.');
                            return;
                          }

                          _ReviewedProductsLookupResult reviewedLookup =
                              const _ReviewedProductsLookupResult(
                                keys: <String>{},
                                messagesByProductKey: <String, String>{},
                                messagesByBillProductKey: <String, String>{},
                                messagesByBillTimeProductKey:
                                    <String, String>{},
                              );
                          try {
                            reviewedLookup =
                                await _fetchReviewedProductKeysForPhone(
                                  phone,
                                  knownBills: history,
                                );
                          } catch (_) {}
                          if (!mounted || !statefulContext.mounted) return;
                          sheetSetState(() => isHistoryLoading = false);

                          await _showCustomerHistorySheet(
                            phone,
                            history,
                            currentBillId: bill.id,
                            reviewedLookup: reviewedLookup,
                          );
                        },
                              ),
                            ),
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
    String canonicalWaiterName(String rawName) {
      final trimmed = rawName.trim();
      final normalized = trimmed.toLowerCase();
      const waiterAliasMap = {
        'ettroad@bf.com': 'Ettayapuram Road',
        'ettroad': 'Ettayapuram Road',
        'ettayapuram road': 'Ettayapuram Road',
        'etp-ettayapuram road': 'Ettayapuram Road',
      };
      return waiterAliasMap[normalized] ?? trimmed;
    }

    final visibleBills = bills
        .where((bill) => bill.status.toLowerCase() != 'settled')
        .toList(growable: false);
    final waiterNames =
        visibleBills
            .map((bill) => canonicalWaiterName(bill.waiterName))
            .where((name) => name.isNotEmpty && name != 'Unknown')
            .toSet()
            .toList(growable: false)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final tableNumbers =
        visibleBills
            .map((bill) => (bill.tableNumber ?? '').trim())
            .where((table) => table.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort((a, b) {
            final aNumber = int.tryParse(a);
            final bNumber = int.tryParse(b);
            if (aNumber != null && bNumber != null) {
              return aNumber.compareTo(bNumber);
            }
            return a.compareTo(b);
          });
    final selectedWaiterName = waiterNames.contains(_selectedWaiterName)
        ? _selectedWaiterName
        : null;
    final selectedBillType =
        _selectedBillType == 'normal' || _selectedBillType == 'table'
        ? _selectedBillType
        : null;
    final selectedTableNumber = tableNumbers.contains(_selectedTableNumber)
        ? _selectedTableNumber
        : null;
    final filteredBills = visibleBills
        .where((bill) {
          final billWaiterName = canonicalWaiterName(bill.waiterName);
          if (selectedWaiterName != null &&
              billWaiterName != selectedWaiterName) {
            return false;
          }
          final isTableOrder =
              (bill.tableNumber?.trim().isNotEmpty ?? false) ||
              (bill.section?.trim().isNotEmpty ?? false);
          if (selectedBillType == 'table' && !isTableOrder) {
            return false;
          }
          if (selectedBillType == 'normal' && isTableOrder) {
            return false;
          }
          final tableNo = (bill.tableNumber ?? '').trim();
          if (selectedTableNumber != null && tableNo != selectedTableNumber) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    return CommonScaffold(
      title: "Bill Sheet",
      pageType: PageType.billsheet,
      actions: const [PrinterSettingsAction()],
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : visibleBills.isEmpty
          ? Center(child: Text("No bills today"))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: selectedWaiterName,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Waiter',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Waiters'),
                            ),
                            ...waiterNames.map(
                              (name) => DropdownMenuItem<String?>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedWaiterName = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: selectedBillType,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Type',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Types'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'normal',
                              child: Text('Normal'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'table',
                              child: Text('Table Order'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedBillType = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: selectedTableNumber,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Table Number',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Tables'),
                            ),
                            ...tableNumbers.map(
                              (table) => DropdownMenuItem<String?>(
                                value: table,
                                child: Text('T-$table'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedTableNumber = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredBills.isEmpty
                      ? Center(
                          child: Text("No bills for selected waiter/table"),
                        )
                      : GridView.builder(
                          padding: EdgeInsets.all(16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 1,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemCount: filteredBills.length,
                          itemBuilder: (_, i) {
                            final bill = filteredBills[i];
                            final status = bill.status.toLowerCase();
                            final isSettled = status == 'settled';
                            final isCompleted = status == 'completed';
                            final isPrepared = status == 'prepared';
                            final isCancelled = status == 'cancelled';
                            final isFinalBill = isCompleted || isSettled;
                            const completedTileColor = Color(0xFF380202);
                            final isTableOrder =
                                (bill.tableNumber?.trim().isNotEmpty ??
                                    false) ||
                                (bill.section?.trim().isNotEmpty ?? false);
                            final isExistingCustomer =
                                _existingCustomerByBillId[bill.id] ??
                                bill.isExistingCustomer;
                            // KOT detection based on status or invoice number
                            final isKot =
                                !isFinalBill ||
                                bill.invoiceNumber.toUpperCase().contains(
                                  'KOT',
                                );
                            final isExistingCustomerTableTile =
                                isExistingCustomer &&
                                isTableOrder &&
                                !isSettled &&
                                !isCancelled;
                            final tileColor = isSettled
                                ? Colors.black
                                : isCancelled
                                ? Colors.black
                                : isExistingCustomerTableTile
                                ? Colors.blue.shade700
                                : isCompleted
                                ? completedTileColor
                                : (isPrepared && isTableOrder)
                                ? Colors.green.shade700
                                : Colors.yellow;
                            final isYellowTile =
                                !isSettled &&
                                !isCompleted &&
                                !isCancelled &&
                                !isExistingCustomerTableTile &&
                                !(isPrepared && isTableOrder);
                            final runningTextColor = isYellowTile
                                ? Colors.black87
                                : Colors.white;
                            final runningStatusText = isCancelled
                                ? "CANCELLED"
                                : (isExistingCustomer
                                      ? "E-RUNNING"
                                      : "RUNNING");
                            // Format display number
                            final raw = bill.invoiceNumber.split("-").last;
                            // If it's a KOT and doesn't explicitly say KOT in the number part, we can add it or just show the number.
                            // Usually raw will be something like '002' or 'KOT002'.
                            String displayNo = raw;
                            if (isKot && !raw.toUpperCase().startsWith('KOT')) {
                              final normalizedKotNo =
                                  RegExp(r'^\d+$').hasMatch(raw)
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
                            String runningKotNo = displayNo;
                            if (isKot &&
                                runningKotNo.toUpperCase().startsWith('KOT') &&
                                !runningKotNo.toUpperCase().startsWith(
                                  'KOT-',
                                )) {
                              runningKotNo = 'KOT-${runningKotNo.substring(3)}';
                            }
                            final hasTableNumber =
                                bill.tableNumber != null &&
                                bill.tableNumber!.trim().isNotEmpty;
                            final showCornerTableKotBadges =
                                hasTableNumber && isTableOrder;
                            final rawInvoicePart = raw.replaceAll(' ', '');
                            final rawInvoiceForKot =
                                RegExp(r'^\d+$').hasMatch(rawInvoicePart)
                                ? (int.tryParse(rawInvoicePart)?.toString() ??
                                      rawInvoicePart)
                                : rawInvoicePart;
                            String cornerKotLabel = runningKotNo;
                            final upperCornerKot = cornerKotLabel.toUpperCase();
                            if (upperCornerKot.startsWith('KOT')) {
                              if (!upperCornerKot.startsWith('KOT-')) {
                                cornerKotLabel =
                                    'KOT-${cornerKotLabel.substring(3)}';
                              }
                            } else {
                              final fallbackKotNumber =
                                  rawInvoiceForKot.isNotEmpty
                                  ? rawInvoiceForKot
                                  : displayNo;
                              cornerKotLabel = 'KOT-$fallbackKotNumber';
                            }
                            final badgeBackgroundColor = isYellowTile
                                ? Colors.black87
                                : Colors.black.withValues(alpha: 0.35);

                            return GestureDetector(
                              onTap: () => _showPaymentSheet(bill),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: tileColor,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: tileColor.withValues(
                                        alpha: isYellowTile ? 0.28 : 0.4,
                                      ),
                                      blurRadius: 10,
                                      spreadRadius: 0.8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    if (showCornerTableKotBadges)
                                      Positioned(
                                        top: 6,
                                        left: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeBackgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'T-${bill.tableNumber!.trim()}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (showCornerTableKotBadges)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeBackgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            cornerKotLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Center(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          top: showCornerTableKotBadges
                                              ? 18
                                              : 0,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (isKot) ...[
                                              ValueListenableBuilder<DateTime>(
                                                valueListenable: _liveNow,
                                                builder: (_, liveNow, __) {
                                                  final runningStatusWithTime =
                                                      isCancelled
                                                      ? runningStatusText
                                                      : '$runningStatusText (${_formatRunningElapsedClock(bill.createdAt, liveNow)})';
                                                  return Text(
                                                    runningStatusWithTime,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: runningTextColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'RS ${_formatReceiptMoney(bill.totalAmount)}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  color: runningTextColor,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (bill.waiterName
                                                      .trim()
                                                      .isNotEmpty &&
                                                  bill.waiterName !=
                                                      'Unknown') ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  bill.waiterName,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: runningTextColor,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                            if (!isKot)
                                              Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'BILL- $displayNo',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'RS ${_formatReceiptMoney(bill.totalAmount)}',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  if (bill.waiterName
                                                          .trim()
                                                          .isNotEmpty &&
                                                      bill.waiterName !=
                                                          'Unknown') ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      bill.waiterName,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

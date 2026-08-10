import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';

class ClosingEntryPage extends StatefulWidget {
  const ClosingEntryPage({Key? key}) : super(key: key);

  @override
  State<ClosingEntryPage> createState() => _ClosingEntryPageState();
}

class _ClosingEntryPageState extends State<ClosingEntryPage> {
  final _salesFormKey = GlobalKey<FormState>();
  final _paymentsFormKey = GlobalKey<FormState>();
  final _systemSalesController = TextEditingController();
  final _manualSalesController = TextEditingController();
  final _onlineSalesController = TextEditingController();
  final _expensesController = TextEditingController();
  final _returnTotalController = TextEditingController();
  final _creditCardController = TextEditingController();
  final _upiController = TextEditingController();
  final _cashController = TextEditingController();
  // NEW Controller for Stock Sending
  final _stockOrderController = TextEditingController();
  final List<int> _denominationValues = [2000, 500, 200, 100, 50, 20, 10, 5];
  late final List<TextEditingController> _denomControllers;
  bool _isLoading = true;
  bool _isFetchingSales = false;
  bool _isFetchingExpenses = false;
  bool _isFetchingReturns = false;
  bool _isFetchingStockOrders = false; // NEW
  bool _isSubmitting = false;
  String? _branchId;
  String? _token;
  String? _userName;
  String? _userId;

  bool _hasError = false; // Block UI if initialization fails

  @override
  void initState() {
    super.initState();
    _denomControllers = List.generate(
      _denominationValues.length,
      (_) => TextEditingController(),
    );
    for (var c in _denomControllers) {
      c.addListener(_updateCashFromDenoms);
    }
    // Listeners for real-time summary updates
    _systemSalesController.addListener(_updateUI);
    _manualSalesController.addListener(_updateUI);
    _onlineSalesController.addListener(_updateUI);
    _expensesController.addListener(_updateUI); // Good to have just in case
    _creditCardController.addListener(_updateUI);
    _upiController.addListener(_updateUI);

    _init();
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    [
      _systemSalesController,
      _manualSalesController,
      _onlineSalesController,
      _expensesController,
      _returnTotalController,
      _creditCardController,
      _upiController,
      _cashController,
      _stockOrderController,
      ..._denomControllers,
    ].forEach((c) => c.dispose());
    super.dispose();
  }

  void _updateCashFromDenoms() {
    double total = 0.0;
    for (int i = 0; i < _denominationValues.length; i++) {
      final cnt = int.tryParse(_denomControllers[i].text) ?? 0;
      total += _denominationValues[i] * cnt;
    }
    _cashController.text = total.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _branchId = prefs.getString('branchId') ?? prefs.getString('branch');
    _userName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? prefs.getString('username');
    _userId = prefs.getString('user_id');
    if (_token == null || _branchId == null || _branchId!.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch ID missing. Please log in again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    try {
      final lastClosing = await _fetchLastClosingToday();

      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).toUtc();
      final startTime = lastClosing ?? startOfToday;

      await Future.wait([
        _fetchIncrementalSystemSales(startTime),
        _fetchIncrementalExpenses(startTime),
        _fetchIncrementalReturns(startTime),
        _fetchIncrementalStockOrders(startTime),
      ]);
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() => _hasError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load data: $e. Please check your connection and retry.',
            ),
            duration: const Duration(seconds: 10),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _init,
              textColor: Colors.white,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<DateTime?> _fetchLastClosingToday() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/closing-entries?where[branch][equals]=$_branchId&limit=1&sort=-createdAt',
      );
      final res = await http.get(uri, headers: ApiConfig.getHeaders(_token));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final docs = json['docs'] as List<dynamic>? ?? [];
        if (docs.isNotEmpty) {
          final createdAtStr = docs.first['createdAt'] as String?;
          if (createdAtStr != null) {
            final createdAt = DateTime.parse(createdAtStr).toUtc();
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day).toUtc();
            if (createdAt.isAfter(todayStart)) {
              return createdAt;
            }
          }
        }
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('fetchLastClosingToday error: $e');
      return null;
    }
  }

  Future<void> _fetchIncrementalSystemSales(DateTime startTime) async {
    setState(() => _isFetchingSales = true);
    try {
      final dateFilter = startTime.toIso8601String();
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/billings?where[branch][equals]=$_branchId&where[createdAt][greater_than]=$dateFilter&limit=2000&depth=0',
      );
      final res = await http.get(uri, headers: ApiConfig.getHeaders(_token));
      if (res.statusCode != 200) {
        debugPrint('Billing fetch failed: ${res.statusCode}');
        return;
      }
      final docs = jsonDecode(res.body)['docs'] ?? [];
      double total = 0.0;
      for (final bill in docs) {
        final status = bill['status']?.toString().toLowerCase();
        if (status == 'completed' || status == 'settled') {
          final amount =
              bill['grandTotal'] ??
              bill['total'] ??
              bill['netAmount'] ??
              bill['totalAmount'] ??
              bill['amount'];
          if (amount is num) total += amount.toDouble();
        }
      }
      _systemSalesController.text = total.toStringAsFixed(2);
    } catch (e) {
      debugPrint('fetchIncrementalSystemSales error: $e');
    }
    setState(() => _isFetchingSales = false);
  }

  Future<void> _fetchIncrementalExpenses(DateTime startTime) async {
    setState(() => _isFetchingExpenses = true);
    try {
      final dateFilter = startTime.toIso8601String();
      /*
      final uri = Uri.https(_apiHost, '/api/expenses', {
        'where[branch][equals]': _branchId!,
        'where[createdAt][greater_than]': dateFilter,
        'limit': '2000',
        'depth': '0',
      });
      */
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/expenses?where[branch][equals]=$_branchId&where[createdAt][greater_than]=$dateFilter&limit=2000&depth=0',
      );
      final res = await http.get(uri, headers: ApiConfig.getHeaders(_token));
      if (res.statusCode != 200) return;
      final docs = jsonDecode(res.body)['docs'] ?? [];
      double total = 0.0;
      for (final exp in docs) {
        total += (exp['total'] ?? 0).toDouble();
      }
      _expensesController.text = total.toStringAsFixed(2);
    } catch (e) {
      debugPrint('fetchIncrementalExpenses error: $e');
    }
    setState(() => _isFetchingExpenses = false);
  }

  Future<void> _fetchIncrementalReturns(DateTime startTime) async {
    setState(() => _isFetchingReturns = true);
    try {
      final dateFilter = startTime.toIso8601String();
      /*
      final uri = Uri.https(_apiHost, '/api/return-orders', {
        'where[branch][equals]': _branchId!,
        'where[createdAt][greater_than]': dateFilter,
        'limit': '2000',
        'depth': '0',
      });
      */
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/return-orders?where[branch][equals]=$_branchId&where[createdAt][greater_than]=$dateFilter&limit=2000&depth=0',
      );
      final res = await http.get(uri, headers: ApiConfig.getHeaders(_token));
      if (res.statusCode != 200) {
        debugPrint('Returns fetch failed: ${res.statusCode}');
        return;
      }
      final docs = jsonDecode(res.body)['docs'] ?? [];
      double total = 0.0;
      for (final order in docs) {
        if (order['status'] == 'returned') {
          total += (order['totalAmount'] ?? 0).toDouble();
        }
      }
      _returnTotalController.text = total.toStringAsFixed(2);
    } catch (e) {
      debugPrint('fetchIncrementalReturns error: $e');
    }
    setState(() => _isFetchingReturns = false);
  }

  // -------------------------------------------------------
  // NEW: CORRECT INCREMENTAL STOCK BASED ON ITEM.sendingDate
  // -------------------------------------------------------
  Future<void> _fetchIncrementalStockOrders(DateTime startTime) async {
    setState(() => _isFetchingStockOrders = true);
    try {
      // Stock orders are trickier because they loop through items which have sendingDate.
      // But usually we filter by order creation or update.
      // The previous logic filtered items by sendingDate > lastClosing.
      // Let's filter orders modified/created after sendingDate.
      // However, the payload is traversing stock-orders.
      // Let's stick to the same logic but filter stock-orders by updated/createdAt to reduce payload?
      // Or just filter all active stock orders?
      // Since 'sendingDate' is on item level, and we want items sent TODAY > lastClosing.



      // Fetching stock orders created/updated recently?
      // Actually stock orders might be created earlier but items sent today.
      // So filtering by 'items.sendingDate' would be ideal but Payload doesn't support deep nested queries easily on arrays sometimes.
      // Safe bet: Filter stock orders updated today? Or just last 100 which is better than 2000.

      // Let's keep it simpler but optimized: Filter orders created OR updated today?
      // The previous logic iterated all 2000.
      // Let's try to filter by `updatedAt` > today start?
      // If a stock order was created yesterday but an item sent today, updatedAt would be today.

      // Let's use startOfToday for the query to be safe, then filter items strictly by startTime.
      final now = DateTime.now();
      final startOfToday = DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc().toIso8601String();

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/stock-orders?where[branch][equals]=$_branchId&where[updatedAt][greater_than]=$startOfToday&limit=500&depth=0',
      );

      final res = await http.get(uri, headers: ApiConfig.getHeaders(_token));
      if (res.statusCode != 200) {
        debugPrint('Stock order fetch failed: ${res.statusCode}');
        return;
      }
      final docs = jsonDecode(res.body)['docs'] ?? [];
      double total = 0.0;

      for (final so in docs) {
        final items = so['items'] as List<dynamic>?;
        if (items == null) continue;
        for (final item in items) {
          final sendingDateStr = item['sendingDate'];
          final sendingAmount = item['sendingAmount'] ?? 0;
          if (sendingDateStr == null) continue;
          final sendingDate = DateTime.parse(sendingDateStr).toUtc();

          if (sendingDate.isAfter(startTime)) {
            total += sendingAmount.toDouble();
          }
        }
      }
      _stockOrderController.text = total.toStringAsFixed(2);
    } catch (e) {
      debugPrint('fetchIncrementalStockOrders error: $e');
    }
    setState(() => _isFetchingStockOrders = false);
  }

  Future<void> _submitForm() async {
    if (!_salesFormKey.currentState!.validate() ||
        !_paymentsFormKey.currentState!.validate())
      return;
    setState(() => _isSubmitting = true);
    try {
      // Must succeed strictly
      final lastClosing = await _fetchLastClosingToday();
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).toUtc();
      final startTime = lastClosing ?? startOfToday;

      await Future.wait([
        _fetchIncrementalSystemSales(startTime),
        _fetchIncrementalExpenses(startTime),
        _fetchIncrementalReturns(startTime),
        _fetchIncrementalStockOrders(startTime),
      ]);
      final systemSales = double.tryParse(_systemSalesController.text) ?? 0.0;
      final payload = {
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'systemSales': systemSales,
        'manualSales': double.tryParse(_manualSalesController.text) ?? 0.0,
        'onlineSales': double.tryParse(_onlineSalesController.text) ?? 0.0,
        'expenses': double.tryParse(_expensesController.text) ?? 0.0,
        'returnTotal': double.tryParse(_returnTotalController.text) ?? 0.0,
        'stockOrders': double.tryParse(_stockOrderController.text) ?? 0.0,
        'creditCard': double.tryParse(_creditCardController.text) ?? 0.0,
        'upi': double.tryParse(_upiController.text) ?? 0.0,
        'cash': double.tryParse(_cashController.text) ?? 0.0,
        'denominations': {
          for (int i = 0; i < _denominationValues.length; i++)
            'count${_denominationValues[i]}':
                int.tryParse(_denomControllers[i].text) ?? 0,
        },
        'branch': _branchId,
        'createdByName': _userName,
        'createdByUser': _userId,
        'createdBy': _userId,
      };
      // final uri = Uri.https(_apiHost, '/api/closing-entries');
      final uri = Uri.parse('${ApiConfig.baseUrl}/closing-entries');
      final res = await http.post(
        uri,
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Closing entry submitted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed: ${res.statusCode}')));
        }
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => _isSubmitting = false);
  }

  Widget _buildNumberField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        filled: true,
        fillColor: readOnly ? Colors.grey[200] : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading ||
        _isFetchingSales ||
        _isFetchingExpenses ||
        _isFetchingReturns ||
        _isFetchingStockOrders) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Closing Entry Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to verify previous closing status.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'To prevent sales double-counting, you cannot proceed without a stable connection.',
                  textAlign: TextAlign.center,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _init,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final totalSales =
        (double.tryParse(_manualSalesController.text) ?? 0.0) +
        (double.tryParse(_onlineSalesController.text) ?? 0.0);
    final totalPayments =
        (double.tryParse(_creditCardController.text) ?? 0.0) +
        (double.tryParse(_upiController.text) ?? 0.0) +
        (double.tryParse(_cashController.text) ?? 0.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Closing Entry Form')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            // -------------------------------------------------------
            // Sales Section
            // -------------------------------------------------------
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Form(
                  key: _salesFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sales',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNumberField('Manual Sales', _manualSalesController),
                      const SizedBox(height: 10),
                      _buildNumberField('Online Sales', _onlineSalesController),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // -------------------------------------------------------
            // Payments Section
            // -------------------------------------------------------
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Form(
                  key: _paymentsFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNumberField('Credit Card', _creditCardController),
                      const SizedBox(height: 10),
                      _buildNumberField('UPI', _upiController),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _cashController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Cash (from denominations)',
                          prefixText: '₹ ',
                          filled: true,
                          fillColor: Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // -------------------------------------------------------
            // Denominations Section
            // -------------------------------------------------------
            Card(
              color: Colors.yellow[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cash Denominations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_denominationValues.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Text(
                              '₹${_denominationValues[i]} × ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _denomControllers[i],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Count',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  filled: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // -------------------------------------------------------
            // Summary Section
            // -------------------------------------------------------
            Card(
              color: Colors.purple[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Manual Sales'),
                        Text('₹${_manualSalesController.text}'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Online Sales'),
                        Text('₹${_onlineSalesController.text}'),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Sales',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${totalSales.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Credit Card'),
                        Text('₹${_creditCardController.text}'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('UPI'),
                        Text('₹${_upiController.text}'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cash'),
                        Text('₹${_cashController.text}'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...List.generate(_denominationValues.length, (i) {
                      final count =
                          int.tryParse(_denomControllers[i].text) ?? 0;
                      if (count > 0) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('₹${_denominationValues[i]} ×'),
                            Text('$count'),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    const Divider(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Payments',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${totalPayments.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_userName != null && _userName!.isNotEmpty)
              Card(
                color: Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Submitted By',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            _userName!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 30),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submitForm,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const Icon(Icons.send, color: Colors.white),
          label: Text(
            _isSubmitting ? 'Submitting...' : 'Submit Closing Entry',
            style: const TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: Colors.green,
          ),
        ),
      ),
    );
  }
}

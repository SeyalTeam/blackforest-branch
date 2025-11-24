import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExpenseDetailsPage extends StatefulWidget {
  const ExpenseDetailsPage({Key? key}) : super(key: key);

  @override
  _ExpenseDetailsPageState createState() => _ExpenseDetailsPageState();
}

class _ExpenseDetailsPageState extends State<ExpenseDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _expenseDetails = [];
  final _totalExpensesController = TextEditingController();
  final List<String> _expenseSources = [
    'MAINTENANCE',
    'TRANSPORT',
    'FUEL',
    'PACKING',
    'STAFF WELFARE',
    'ADVERTISEMENT',
    'ADVANCE',
    'COMPLEMENTARY',
    'RAW MATERIAL',
    'SALARY',
    'OC PRODUCTS',
    'OTHERS'
  ];
  bool _isSubmitting = false;
  bool _loadingBranch = true;
  String? _branchId;
  String? _branchName;

  @override
  void initState() {
    super.initState();
    _loadBranch();
  }

  Future<void> _loadBranch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _branchId = prefs.getString('branchId');
      _branchName = prefs.getString('branchName');
      _loadingBranch = false;
    });
  }

  void _addExpenseDetail() {
    setState(() {
      final amountController = TextEditingController();
      amountController.addListener(_updateTotalExpenses);
      _expenseDetails.add({
        'source': null,
        'reason': TextEditingController(),
        'amount': amountController,
      });
    });
  }

  void _removeExpenseDetail(int index) {
    setState(() {
      _expenseDetails[index]['amount'].removeListener(_updateTotalExpenses);
      _expenseDetails[index]['reason'].dispose();
      _expenseDetails[index]['amount'].dispose();
      _expenseDetails.removeAt(index);
      _updateTotalExpenses();
    });
  }

  void _updateTotalExpenses() {
    double total = _expenseDetails.fold(
      0.0,
          (sum, exp) => sum + (double.tryParse(exp['amount'].text) ?? 0.0),
    );
    _totalExpensesController.text = total.toStringAsFixed(2);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch not found. Please log in again.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final expenseData = {
      'branch': _branchId,
      'details': _expenseDetails.map((e) {
        return {
          'source': e['source'],
          'reason': e['reason'].text,
          'amount': double.tryParse(e['amount'].text) ?? 0.0,
        };
      }).toList(),
      'total': double.tryParse(_totalExpensesController.text) ?? 0.0,
      'date': DateTime.now().toIso8601String(),
    };
    try {
      final response = await http.post(
        Uri.parse('https://admin.theblackforestcakes.com/api/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(expenseData),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expenses submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _expenseDetails.clear();
          _totalExpensesController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    if (_loadingBranch) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expense Details',
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              // Toggle theme if needed, but assuming theme is handled elsewhere
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Expenses',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₹${_totalExpensesController.text}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Expense Details - ${_branchName ?? "Branch"}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView.builder(
                  itemCount: _expenseDetails.length,
                  itemBuilder: (context, index) {
                    var expense = _expenseDetails[index];
                    return Dismissible(
                      key: UniqueKey(),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) {
                        _removeExpenseDetail(index);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Expense ${index + 1} removed'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () {
                                // Implement undo if desired
                              },
                            ),
                          ),
                        );
                      },
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20.0),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 16.0),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Expense ${index + 1}',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _removeExpenseDetail(index),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: expense['source'],
                                items: _expenseSources.map((source) {
                                  return DropdownMenuItem<String>(
                                    value: source,
                                    child: Text(source),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    expense['source'] = value;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'Source',
                                  prefixIcon: const Icon(Icons.category),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                validator: (value) => value == null
                                    ? 'Please select a source'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: expense['reason'],
                                decoration: InputDecoration(
                                  labelText: 'Reason',
                                  prefixIcon: const Icon(Icons.description),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                validator: (value) => value!.isEmpty
                                    ? 'Please enter a reason'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: expense['amount'],
                                decoration: InputDecoration(
                                  labelText: 'Amount',
                                  prefixText: '₹',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                ),
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                validator: (value) => value!.isEmpty
                                    ? 'Please enter an amount'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _addExpenseDetail,
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitForm,
              icon: _isSubmitting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white),
              )
                  : const Icon(Icons.send),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit Expenses'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
            ),
            const SizedBox(height: 16), // Extra padding at bottom
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _totalExpensesController.dispose();
    for (var expense in _expenseDetails) {
      expense['amount'].removeListener(_updateTotalExpenses);
      expense['reason'].dispose();
      expense['amount'].dispose();
    }
    super.dispose();
  }
}
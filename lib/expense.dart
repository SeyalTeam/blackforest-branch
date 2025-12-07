import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/common_scaffold.dart';

class _ExpenseItem {
  String? source;
  final TextEditingController reason;
  final TextEditingController amount;

  _ExpenseItem({
    this.source,
    TextEditingController? reason,
    TextEditingController? amount,
  })  : reason = reason ?? TextEditingController(),
        amount = amount ?? TextEditingController();

  void dispose() {
    reason.dispose();
    amount.dispose();
  }
}

class ExpenseDetailsPage extends StatefulWidget {
  const ExpenseDetailsPage({Key? key}) : super(key: key);

  @override
  _ExpenseDetailsPageState createState() => _ExpenseDetailsPageState();
}

class _ExpenseDetailsPageState extends State<ExpenseDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final List<_ExpenseItem> _expenseItems = [];
  final _totalExpensesController = TextEditingController(); // Only for display
  DateTime _selectedDate = DateTime.now();

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
      final newItem = _ExpenseItem();
      newItem.amount.addListener(_updateTotalExpenses);
      _expenseItems.add(newItem);
    });
  }

  void _removeExpenseDetail(int index) {
    setState(() {
      _expenseItems[index].amount.removeListener(_updateTotalExpenses);
      _expenseItems[index].dispose();
      _expenseItems.removeAt(index);
      _updateTotalExpenses();
    });
  }

  void _updateTotalExpenses() {
    double total = _expenseItems.fold(
      0.0,
      (sum, item) {
        final val = double.tryParse(item.amount.text);
        return sum + (val ?? 0.0);
      },
    );
    _totalExpensesController.text = total.toStringAsFixed(2);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct errors in the form.')),
      );
      return;
    }
    if (_expenseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one expense.')),
      );
      return;
    }
    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch not found. Please log in again.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final expenseData = {
      'branch': _branchId,
      'details': _expenseItems.map((e) {
        return {
          'source': e.source,
          'reason': e.reason.text.trim(),
          'amount': double.tryParse(e.amount.text) ?? 0.0,
        };
      }).toList(),
      'total': double.tryParse(_totalExpensesController.text) ?? 0.0,
      'date': _selectedDate.toIso8601String(),
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
        _resetForm();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${response.statusCode} - ${response.body}'),
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      for (var item in _expenseItems) {
        item.dispose();
      }
      _expenseItems.clear();
      _updateTotalExpenses();
      _selectedDate = DateTime.now();
    });
  }

  @override
  void dispose() {
    _totalExpensesController.dispose();
    for (var item in _expenseItems) {
      item.amount.removeListener(_updateTotalExpenses);
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBranch) {
      return const CommonScaffold(
        title: 'Expense Details',
        pageType: PageType.expense,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return CommonScaffold(
      title: 'Expense Details',
      pageType: PageType.expense,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Expenses',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${_totalExpensesController.text.isEmpty ? "0.00" : _totalExpensesController.text}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _branchName ?? 'Branch',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        InkWell(
                          onTap: () => _selectDate(context),
                          child: Row(
                            children: [
                              Text(
                                "${_selectedDate.toLocal()}".split(' ')[0],
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.calendar_today, size: 16),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Expense List Form
            Form(
              key: _formKey,
              child: Column(
                children: [
                  if (_expenseItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Text(
                        "No expenses added yet.\nTap 'Add Expense' to begin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ..._expenseItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return _buildExpenseCard(index, item);
                  }).toList(),
                ],
              ),
            ),

            const SizedBox(height: 16),
            
            // Add Button
            ElevatedButton.icon(
              onPressed: _addExpenseDetail,
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            
            // Submit Button
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitForm,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit Expenses'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard(int index, _ExpenseItem item) {
    return Dismissible(
      key: ObjectKey(item),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => _removeExpenseDetail(index),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expense #${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeExpenseDetail(index),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Source Dropdown
              DropdownButtonFormField<String>(
                value: item.source,
                items: _expenseSources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => item.source = val),
                decoration: InputDecoration(
                  labelText: 'Source',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (val) => val == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              
              // Reason Input
              TextFormField(
                controller: item.reason,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: const Icon(Icons.description_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              
              // Amount Input
              TextFormField(
                controller: item.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  final num = double.tryParse(val);
                  if (num == null) return 'Invalid number';
                  if (num <= 0) return 'Must be > 0';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
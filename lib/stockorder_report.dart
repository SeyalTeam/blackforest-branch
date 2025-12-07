import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/stock_provider.dart';

class StockOrderReportPage extends StatefulWidget {
  const StockOrderReportPage({super.key});

  @override
  State<StockOrderReportPage> createState() => _StockOrderReportPageState();
}

class _StockOrderReportPageState extends State<StockOrderReportPage> {
  DateTime _selectedDate = DateTime.now();
  // Map to track local edits: OrderID -> { ProductID -> ReceivedQty }
  final Map<String, Map<String, TextEditingController>> _controllers = {};
  // Map to track status: OrderID -> { ProductID -> Status ("pending" | "approved") }
  final Map<String, Map<String, String>> _statusControllers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  void _fetchData() {
    Provider.of<StockProvider>(context, listen: false).fetchStockReports(date: _selectedDate);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.deepPurple),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _controllers.clear();
        _statusControllers.clear();
      });
      _fetchData();
    }
  }

  @override
  void dispose() {
    for (var orderControllers in _controllers.values) {
      for (var controller in orderControllers.values) {
        controller.dispose();
      }
    }
    _statusControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Stock Order Report',
      pageType: PageType.stock, 
      body: Consumer<StockProvider>(
        builder: (context, sp, child) {
          if (sp.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (sp.stockReports.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              _buildDateHeader(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sp.stockReports.length,
                  itemBuilder: (context, index) {
                    return _buildOrderCard(context, sp.stockReports[index], sp);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            "No Stock Orders for ${DateFormat('dd MMM yyyy').format(_selectedDate)}",
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _selectDate(context),
            icon: const Icon(Icons.calendar_today),
            label: const Text("Change Date"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          TextButton.icon(
            onPressed: () => _selectDate(context),
            icon: const Icon(Icons.calendar_today, size: 18),
            label: const Text("Filter"),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, dynamic order, StockProvider sp) {
    final items = order["items"] as List<dynamic>? ?? [];
    final orderId = order["id"];
    
    // Initialize controllers for this order if not exists
    if (!_controllers.containsKey(orderId)) {
      _controllers[orderId] = {};
      for (var item in items) {
        final pid = _getProductId(item);
        // Default received to sending (or 0 if sending missing)
        // User requested: "Snt count only need to show in Rec"
        var recv = item["receivedQty"];
        if (recv == 0 || recv == null) recv = item["sendingQty"];
        final initialVal = (recv ?? 0).toString();
        _controllers[orderId]![pid] = TextEditingController(text: initialVal);
      }
    }

    if (!_statusControllers.containsKey(orderId)) {
      _statusControllers[orderId] = {};
      for (var item in items) {
        final pid = _getProductId(item);
        // Default to item status or 'pending'
        _statusControllers[orderId]![pid] = item["status"] ?? "pending";
      }
    }

    // Calculate totals
    int totalQty = 0;
    double totalAmount = 0;

    for (var item in items) {
      final pid = _getProductId(item);
      final qty = int.tryParse(_controllers[orderId]![pid]?.text ?? "0") ?? 0;
      final price = _getProductPrice(item);
      
      totalQty += qty;
      totalAmount += (qty * price);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "${order['invoiceNumber'] ?? 'No Invoice #'}".toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order["status"]).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getStatusColor(order["status"])),
                  ),
                  child: Text(
                    (order["status"] ?? "pending").toString().toUpperCase(),
                    style: TextStyle(color: _getStatusColor(order["status"]), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Table Header
          Container(
            color: Colors.grey[50],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: const [
                Expanded(flex: 3, child: Text("Product", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 1, child: Center(child: Text("Req", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                Expanded(flex: 1, child: Center(child: Text("Snt", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                Expanded(flex: 1, child: Center(child: Text("Rec", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13)))),
              ],
            ),
          ),
          const Divider(height: 1),

          // Items List
          ...items.map((item) {
             final pid = _getProductId(item);
             final controller = _controllers[orderId]![pid];
             
             final product = item["product"];
             final productName = (product is Map ? product["name"] : "Unknown Product");
             final price = _getProductPrice(item);

             final reqQty = item["requiredQty"] ?? 0;
             final sentQty = item["sendingQty"] ?? 0;

             final isApproved = _statusControllers[orderId]![pid] == "approved";
             
             return GestureDetector(
               onTap: () {
                   setState(() {
                      final current = _statusControllers[orderId]![pid];
                      _statusControllers[orderId]![pid] = (current == "approved") ? "pending" : "approved";
                   });
               },
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                 decoration: BoxDecoration(
                   color: isApproved ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.1),
                   border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                 ),
                 child: Row(
                   children: [
                     // Product Name & Price
                     Expanded(
                       flex: 3,
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(productName, style: const TextStyle(fontSize: 14)),
                           Text("₹$price", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                         ],
                       ),
                     ),
                     // Required Qty
                     Expanded(
                       flex: 1,
                       child: Center(child: Text(reqQty.toString(), style: const TextStyle(fontSize: 14))),
                     ),
                     // Sent Qty
                     Expanded(
                       flex: 1,
                       child: Center(child: Text(sentQty.toString(), style: const TextStyle(fontSize: 14))),
                     ),
                     // Received Qty (Editable)
                     Expanded(
                       flex: 1,
                       child: Container(
                         height: 36,
                         padding: const EdgeInsets.symmetric(horizontal: 4),
                         decoration: BoxDecoration(
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: Colors.blue.withOpacity(0.5)),
                           color: Colors.white.withOpacity(0.5),
                         ),
                         child: TextField(
                           controller: controller,
                           keyboardType: TextInputType.number,
                           textAlign: TextAlign.center,
                           style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                           decoration: const InputDecoration(
                             border: InputBorder.none,
                             contentPadding: EdgeInsets.only(bottom: 12),
                           ),
                           onChanged: (v) {
                             // Trigger rebuild to update totals
                             setState(() {}); 
                           },
                         ),
                        ),
                      ),
                   ],
                 ),
               ),
             );
          }).toList(),

          // Totals Section
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Qty:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      totalQty.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Amount:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      "₹${totalAmount.toStringAsFixed(2)}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                       await _saveChanges(context, orderId, items, sp);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("UPDATE RECEIVED QTY"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getProductId(dynamic item) {
    if (item["product"] is Map) {
      return item["product"]["id"];
    }
    return item["product"].toString();
  }

  double _getProductPrice(dynamic item) {
    if (item["product"] is Map) {
       final p = item["product"];
       // Handling nested price structure safely as seen in stock_provider
       return (p['defaultPriceDetails']?['price'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'received':
      case 'approved':
        return Colors.green;
      case 'cancelled':
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  Future<void> _saveChanges(BuildContext context, String orderId, List<dynamic> originalItems, StockProvider sp) async {
    final orderCtrls = _controllers[orderId];
    if (orderCtrls == null) return;

    List<Map<String, dynamic>> updatedItems = [];
    
    for (var item in originalItems) {
      final pid = _getProductId(item);
      final qty = int.tryParse(orderCtrls[pid]?.text ?? "0") ?? 0;
      
      // Construct item object to send back
      Map<String, dynamic> newItem = Map<String, dynamic>.from(item);
      newItem["receivedQty"] = qty;
      newItem["product"] = pid; 
      newItem["status"] = _statusControllers[orderId]![pid];

      updatedItems.add(newItem);
    }

    final success = await sp.updateStockOrderReceipt(orderId, updatedItems);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? "Updated Successfully" : "Update Failed"),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _fetchData();
    }
  }
}

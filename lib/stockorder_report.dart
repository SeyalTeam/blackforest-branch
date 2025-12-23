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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    await Provider.of<StockProvider>(context, listen: false).fetchStockReports(date: _selectedDate);
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
            return RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  _buildEmptyState(),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildDateHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: sp.stockReports.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(context, sp.stockReports[index], sp);
                    },
                  ),
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
      width: double.infinity,
      color: Colors.grey[100],
      child: GestureDetector(
        onTap: () => _selectDate(context),
        child: Text(
          "Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
          textAlign: TextAlign.center,
        ),
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
        // Default received to sending only (strictly Snt column)
        final initialVal = (item["sendingQty"] ?? 0).toString();
        _controllers[orderId]![pid] = TextEditingController(text: initialVal);
      }
    }

    // Calculate totals
    double totalQty = 0;
    double totalAmount = 0;

    for (var item in items) {
      final pid = _getProductId(item);
      final isReceived = item["status"] == "received";
      
      // If received, use the actual value from item. If not, use controller value.
      double qty = 0;
      if (isReceived) {
        qty = (item["receivedQty"] as num?)?.toDouble() ?? 0;
      } else {
        qty = double.tryParse(_controllers[orderId]![pid]?.text ?? "0") ?? 0;
      }

      final price = _getProductPrice(item);
      
      totalQty += qty;
      totalAmount += (qty * price);
    }
    
    // Delivery Date Formatting
    String deliveryText = "";
    if (order["deliveryDate"] != null) {
      try {
        final dt = DateTime.parse(order["deliveryDate"]);
        deliveryText = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
      } catch (e) {
        deliveryText = "";
      }
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order["invoiceNumber"] ?? "Order #${orderId.toString().substring(orderId.toString().length - 6).toUpperCase()}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Builder(
                            builder: (context) {
                              bool isLive = false;
                              if (order["deliveryDate"] != null && order["createdAt"] != null) {
                                try {
                                  final deliveryDate = DateTime.parse(order["deliveryDate"]);
                                  final createdAt = DateTime.parse(order["createdAt"]);
                                  isLive = deliveryDate.year == createdAt.year &&
                                           deliveryDate.month == createdAt.month &&
                                           deliveryDate.day == createdAt.day;
                                } catch (_) {}
                              }
                              
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isLive ? Colors.red : Colors.blue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isLive ? "Live" : "Stock",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(order["status"]).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _getStatusColor(order["status"])),
                            ),
                            child: Text(
                              (order["status"] ?? "Unknown").toUpperCase(),
                              style: TextStyle(
                                color: _getStatusColor(order["status"]), 
                                fontWeight: FontWeight.bold, 
                                fontSize: 10
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (deliveryText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Delivery: $deliveryText",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ],
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
                Expanded(flex: 1, child: Center(child: Text("Ord", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
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
             
             String priceDetails = "";
             if (product is Map) {
                final d = product['defaultPriceDetails'];
                if (d != null) {
                   priceDetails = "${d['quantity'] ?? ''}${d['unit'] ?? ''}";
                }
             }

             final reqQty = (item["requiredQty"] as num?)?.toDouble() ?? 0;
             final sentQty = (item["sendingQty"] as num?)?.toDouble() ?? 0;
             final recQty = (item["receivedQty"] as num?)?.toDouble() ?? 0;
             
             final isReceived = item["status"] == "received";

             return InkWell(
               onTap: isReceived ? null : () => _markItemReceived(context, orderId, items, item, sp),
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                 decoration: BoxDecoration(
                   color: isReceived ? Colors.green.withOpacity(0.1) : Colors.white,
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
                           Row(
                             children: [
                                Text(
                                  "₹$price $priceDetails",
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                               if (item["status"] != null) ...[
                                 const SizedBox(width: 8),
                                 Text(
                                   item["status"],
                                   style: TextStyle(
                                     fontSize: 12, 
                                     fontWeight: FontWeight.bold,
                                     color: _getStatusColor(item["status"]),
                                   ),
                                 ),
                               ],
                             ],
                           ),
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
                     // Received Qty (Editable if not received)
                     Expanded(
                       flex: 1,
                       child: isReceived 
                         ? Center(
                             child: Text(
                               recQty.toString(),
                               style: const TextStyle(
                                 fontSize: 14, 
                                 fontWeight: FontWeight.bold,
                                 color: Colors.green
                               ),
                             ),
                           )
                         : Container(
                             height: 36,
                             padding: const EdgeInsets.symmetric(horizontal: 4),
                             margin: const EdgeInsets.only(left: 8, right: 8),
                             decoration: BoxDecoration(
                               borderRadius: BorderRadius.circular(8),
                               border: Border.all(color: Colors.blue.withOpacity(0.5)),
                               color: Colors.white,
                             ),
                             child: TextField(
                               controller: controller,
                               keyboardType: const TextInputType.numberWithOptions(decimal: true),
                               textAlign: TextAlign.center,
                               style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                               decoration: const InputDecoration(
                                 border: InputBorder.none,
                                 contentPadding: EdgeInsets.only(bottom: 12),
                               ),
                               onTap: () {
                                 // Prevent InkWell onTap from firing when tapping inside TextField
                               },
                               onChanged: (v) {
                                  // Update UI totals only
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

  Future<void> _markItemReceived(BuildContext context, String orderId, List<dynamic> currentItems, Map<String, dynamic> itemToUpdate, StockProvider sp) async {
    // Optimistic check
    if (itemToUpdate["status"] == "received") return;

    final orderCtrls = _controllers[orderId];
    if (orderCtrls == null) return;

    // List for API (compact)
    List<Map<String, dynamic>> apiItems = [];
    // List for Local State (full structure)
    List<Map<String, dynamic>> localItems = [];
    
    // Logic: 
    // If target item: use controller text as receivedQty.
    // Else: keep existing item.
    
    for (var item in currentItems) {
      final pid = _getProductId(item);
      final isTarget = pid == _getProductId(itemToUpdate);
      
      // Clone for local state (preserve all fields like product object)
      Map<String, dynamic> localItem = Map<String, dynamic>.from(item);
      
      // Clone for API (clean up product field)
      Map<String, dynamic> apiItem = Map<String, dynamic>.from(item);

      if (isTarget) {
         // Get value from controller
         final qty = double.tryParse(orderCtrls[pid]?.text ?? "0") ?? 0;
         
         // Update both
         localItem["receivedQty"] = qty;
         localItem["status"] = "received";

         apiItem["receivedQty"] = qty;
         apiItem["status"] = "received";
      }
      
      // Ensure product is just ID for API
      apiItem["product"] = pid; 

      localItems.add(localItem);
      apiItems.add(apiItem);
    }

    // Show loading? Or just await
    final success = await sp.updateStockOrderReceipt(orderId, apiItems);
    
    if (mounted) {
       if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Item Received"), backgroundColor: Colors.green, duration: Duration(milliseconds: 500)),
          );
          // Update Locally instead of Fetching
          sp.updateOrderLocally(orderId, localItems);
       } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to update"), backgroundColor: Colors.red),
          );
       }
    }
  }
  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'received':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
      case 'ordered':
        return Colors.orange;
      case 'ready':
      case 'picked':
      case 'delivered':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

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
  String _selectedFilter = "All";
  // Map to track local edits: OrderID -> { ProductID -> ReceivedQty }
  final Map<String, Map<String, TextEditingController>> _controllers = {};
  // Track items currently being updated to prevent double-tap race conditions
  final Set<String> _updatingItems = {}; // "orderId_productId"
  // Track expanded order cards
  final Set<String> _expandedOrderIds = {};

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
          final reports = sp.stockReports.where((order) {
            if (_selectedFilter == "All") return true;
            final isLive = _isLive(order);
            if (_selectedFilter == "Live") return isLive;
            if (_selectedFilter == "Stock") return !isLive;
            return true;
          }).toList();

          if (reports.isEmpty) {
            return Column(
              children: [

                _buildFilterChips(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                        _buildEmptyState(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [

              _buildFilterChips(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(context, reports[index], sp);
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

  bool _isLive(dynamic order) {
    if (order["deliveryDate"] == null || order["createdAt"] == null) return false;
    try {
      final deliveryDate = DateTime.parse(order["deliveryDate"]).toLocal();
      final createdAt = DateTime.parse(order["createdAt"]).toLocal();
      return deliveryDate.year == createdAt.year &&
             deliveryDate.month == createdAt.month &&
             deliveryDate.day == createdAt.day;
    } catch (_) {
      return false;
    }
  }



  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _selectedFilter == "All" 
              ? "No Stock Orders for ${DateFormat('dd MMM yyyy').format(_selectedDate)}"
              : "No orders for ${DateFormat('dd MMM yyyy').format(_selectedDate)} with selection: $_selectedFilter",
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
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



  Widget _buildFilterChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Calendar Button
            InkWell(
              onTap: () => _selectDate(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM dd').format(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Filter Chips
            ...["All", "Stock", "Live"].map((filter) {
              final isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Text(
                    filter,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: filter == "Live" ? Colors.red : (filter == "Stock" ? Colors.blue : Colors.deepPurple),
                  backgroundColor: Colors.white,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    }
                  },
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: isSelected ? 2 : 0,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              );
            }).toList(),
          ],
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
        // Default received to picked only (strictly Pic column)
        final initialVal = (item["pickedQty"] ?? 0).toString();
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
    


    // Check if expanded
    final isExpanded = _expandedOrderIds.contains(orderId);

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER (Always Visible, Tappable)
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedOrderIds.remove(orderId);
                } else {
                  _expandedOrderIds.add(orderId);
                }
              });
            },
            child: Padding(
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
                                final isLive = _isLive(order);
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
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            String ordText = "";
                            String delText = "";
                            try {
                               if (order["createdAt"] != null) {
                                 final ordDt = DateTime.parse(order["createdAt"]).toLocal();
                                 ordText = DateFormat('dd MMM, hh:mm a').format(ordDt);
                               }
                               if (order["deliveryDate"] != null) {
                                 final delDt = DateTime.parse(order["deliveryDate"]).toLocal();
                                 delText = DateFormat('dd MMM, hh:mm a').format(delDt);
                               }
                            } catch (_) {}

                            return Row(
                              children: [
                                Text(
                                  "Ord: $ordText",
                                  style: TextStyle(fontSize: 11, color: Colors.grey[800], fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "Del: $delText",
                                  style: TextStyle(fontSize: 11, color: Colors.grey[800], fontWeight: FontWeight.w500),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Chevron Icon
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded) ...[
            const Divider(height: 1),
            
            // Table Header
            Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text("Product", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(flex: 1, child: Center(child: Text("Ord", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                  Expanded(flex: 1, child: Center(child: Text("Pic", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
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
               final sentQty = (item["pickedQty"] as num?)?.toDouble() ?? 0; // UPDATED to pickedQty
               final recQty = (item["receivedQty"] as num?)?.toDouble() ?? 0;
               final isReceived = item["status"] == "received";
               final canUpdate = sentQty > 0;

               return InkWell(
                 onDoubleTap: (isReceived || !canUpdate) ? null : () => _markItemReceived(context, orderId, items, item, sp),
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
                             Text(productName, style: TextStyle(fontSize: 14, color: canUpdate || isReceived ? Colors.black : Colors.grey)),
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
                                       color: _getStatusColor(item["status"]).withOpacity(canUpdate || isReceived ? 1.0 : 0.5),
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
                         child: Center(child: Text(reqQty.toString(), style: TextStyle(fontSize: 14, color: canUpdate || isReceived ? Colors.black : Colors.grey))),
                       ),
                       // Sent Qty (Now Picked)
                       Expanded(
                         flex: 1,
                         child: Center(child: Text(sentQty.toString(), style: TextStyle(fontSize: 14, color: canUpdate || isReceived ? Colors.black : Colors.grey))),
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
                                 border: Border.all(color: canUpdate ? Colors.blue.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
                                 color: canUpdate ? Colors.white : Colors.grey[100],
                               ),
                               child: TextField(
                                 controller: controller,
                                 enabled: canUpdate,
                                 keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                 textAlign: TextAlign.center,
                                 style: TextStyle(fontWeight: FontWeight.bold, color: canUpdate ? Colors.blue : Colors.grey),
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
          ], // End ifExpanded
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
    
    final pid = _getProductId(itemToUpdate);
    final key = "${orderId}_$pid";
    if (_updatingItems.contains(key)) return;

    final orderCtrls = _controllers[orderId];
    if (orderCtrls == null) return;
    
    setState(() {
      _updatingItems.add(key);
    });

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
    bool success = false;
    try {
      success = await sp.updateStockOrderReceipt(orderId, apiItems);
    } finally {
       if (mounted) {
         setState(() {
           _updatingItems.remove(key);
         });
       }
    }
    
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

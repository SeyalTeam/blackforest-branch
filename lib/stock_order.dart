import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/stock_provider.dart';

class StockOrderPage extends StatelessWidget {
  const StockOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StockProvider>(
      builder: (context, sp, child) {
        return PopScope(
          canPop: sp.step != "products",
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && sp.step == "products") {
              sp.goBackToCategories();
            }
          },
          child: CommonScaffold(
            title: sp.step == "categories"
                ? "Stock Categories"
                : "Products in ${sp.selectedCategoryName}",
            pageType: PageType.stock, // Changed from PageType.billsheet to PageType.stock for better semantic accuracy (assuming PageType.stock is added to the enum if not present)
            body: sp.isLoading
                ? const Center(
              child: CircularProgressIndicator(color: Colors.black),
            )
                : sp.step == "categories"
                ? _buildCategories(context, sp)
                : _buildProducts(context, sp),
          ),
        );
      },
    );
  }

  // ========================== CATEGORY GRID ===========================
  Widget _buildCategories(BuildContext context, StockProvider sp) {
    final hasSelections = sp.selected.values.any((v) => v == true);

    if (sp.categories.isEmpty) {
      return const Center(child: Text("No categories found"));
    }

    double screenWidth = MediaQuery.of(context).size.width;
    const double paddingHorizontal = 28;
    double availableWidth = screenWidth - paddingHorizontal;
    double buttonWidth = availableWidth * 0.8;
    double spaceWidth = availableWidth * 0.1;
    double iconWidth = availableWidth * 0.1;

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sp.categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (_, i) {
              final c = sp.categories[i];
              String? img = c["image"]?["url"];
              if (img != null && img.startsWith("/")) {
                img = "https://admin.theblackforestcakes.com$img";
              }
              img ??= "https://via.placeholder.com/200?text=No+Image";

              return GestureDetector(
                onTap: () async {
                  await sp.selectCategory(c);
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.15),
                        blurRadius: 4,
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10)),
                            child: Image.network(
                              img,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(10)),
                        ),
                        child: Text(
                          c["name"] ?? "",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ====================== DELIVERY DATE & TIME PICKER ======================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: GestureDetector(
            onTap: () async {
              final selectedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (selectedDate == null) return;

              final selectedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );

              final finalDate = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime?.hour ?? 0,
                selectedTime?.minute ?? 0,
              );

              sp.deliveryDate = finalDate;
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: Colors.black),
                  const SizedBox(width: 12),
                  Text(
                    sp.deliveryDate == null
                        ? "Select Delivery Date & Time"
                        : "${sp.deliveryDate!.day}/${sp.deliveryDate!.month}/${sp.deliveryDate!.year}   "
                        "${sp.deliveryDate!.hour.toString().padLeft(2, '0')}:"
                        "${sp.deliveryDate!.minute.toString().padLeft(2, '0')}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ====================== CONFIRM BUTTON + CART ICON ======================
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: buttonWidth,
                child: ElevatedButton(
                  onPressed: (hasSelections && sp.deliveryDate != null)
                      ? () => sp.submitStockOrder(context)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Confirm",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(width: spaceWidth),
              SizedBox(
                width: iconWidth,
                height: 52,
                child: GestureDetector(
                  onTap: () => _showCartDialog(context, sp),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.shopping_cart,
                          color: Colors.black, size: 28),
                      if (sp.selected.values.where((v) => v == true).isNotEmpty)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '${sp.selected.values.where((v) => v == true).length}',
                              style:
                              const TextStyle(color: Colors.white, fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========================== CART POPUP ===========================
  void _showCartDialog(BuildContext context, StockProvider sp) {
    double screenWidth = MediaQuery.of(context).size.width;
    double dialogWidth = screenWidth * 0.95;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Consumer<StockProvider>(
          builder: (ctx, sp, _) {
            final selectedEntries =
            sp.selected.entries.where((e) => e.value).toList();

            int totalReq = 0;
            int totalInS = 0;
            double totalAmount = 0.0;

            List<DataRow> rows = List.generate(selectedEntries.length, (index) {
              final entry = selectedEntries[index];
              final pid = entry.key;

              final name = sp.productNames[pid] ?? "Unknown";
              final req = sp.quantities[pid] ?? 0;
              final inS = sp.inStock[pid] ?? 0;
              final price = sp.prices[pid] ?? 0.0;

              final amount = (req * price);

              totalReq += req;
              totalInS += inS;
              totalAmount += amount;

              final bg = index % 2 == 0
                  ? Colors.grey.shade300
                  : Colors.grey.shade100;

              return DataRow(
                color: WidgetStateProperty.resolveWith<Color?>((_) => bg),
                cells: [
                  DataCell(
                    GestureDetector(
                      onDoubleTap: () {
                        sp.toggleSelection(pid, false);
                      },
                      child: SizedBox(
                        width: dialogWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${index + 1}. $name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('inS: $inS'),
                                const SizedBox(width: 12),
                                Text(
                                  'Req: $req',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '₹ ${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            });

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Stock (${selectedEntries.length})"),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: dialogWidth,
                height: 400,
                child: selectedEntries.isEmpty
                    ? const Center(child: Text("No products selected"))
                    : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 0,
                            columns: const [
                              DataColumn(
                                  label: SizedBox(width: double.infinity)),
                            ],
                            rows: rows,
                          ),
                        ),
                      ),
                    ),

                    Container(
                      color: Colors.grey.shade200,
                      padding: const EdgeInsets.all(8),
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total',
                            style:
                            TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('inS: $totalInS'),
                              const SizedBox(width: 12),
                              Text(
                                'Req: $totalReq',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '₹ ${totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ========================== PRODUCT LIST ===========================
  Widget _buildProducts(BuildContext context, StockProvider sp) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: sp.searchCtrl,
            decoration: InputDecoration(
              hintText: "Search products...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: sp.filteredProducts.isEmpty
              ? const Center(child: Text("No products found"))
              : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sp.filteredProducts.length,
            itemBuilder: (_, i) {
              final p = sp.filteredProducts[i];
              final String id = p["id"];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sp.selected[id] == true
                        ? Colors.green
                        : Colors.pink.shade300,
                    width: sp.selected[id] == true ? 3 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p["name"] ?? "Unknown",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                    ),

                    _numBox(
                      label: "InStock",
                      controller: sp.stockCtrl[id]!,
                      onChanged: (v) {
                        sp.updateInStock(id, int.tryParse(v) ?? 0);
                      },
                    ),
                    const SizedBox(width: 10),

                    _numBox(
                      label: "Required",
                      controller: sp.qtyCtrl[id]!,
                      onChanged: (v) {
                        sp.updateQuantity(id, int.tryParse(v) ?? 0);
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Checkbox(
                        value: sp.selected[id],
                        onChanged: (v) {
                          sp.toggleSelection(id, v ?? false);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ========================== NUMBER INPUT BOX ===========================
  Widget _numBox({
    required String label,
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return Column(
      children: [
        Text(label,
            style:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey),
          ),
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.only(bottom: 8),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
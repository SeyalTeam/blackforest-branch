import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/cart_page.dart';

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
    if (sp.categories.isEmpty) {
      return const Center(child: Text("No categories found"));
    }

    return GridView.builder(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p["name"] ?? "Unknown",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "₹ ${sp.prices[id] ?? 0}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
                img = "${ApiConfig.domain}$img";
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
                              headers: ApiConfig.getHeaders(null),
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
      ],
    );
  }

  // ========================== PRODUCT LIST ===========================
  Widget _buildProducts(BuildContext context, StockProvider sp) {
    return Column(
      children: [
        // SUPERADMIN BRANCH SELECTION (NEW)
        if (sp.userRole == 'superadmin' && sp.availableBranches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 12),
               decoration: BoxDecoration(
                 color: const Color(0xFFFFF0F0),
                 borderRadius: BorderRadius.circular(10),
                 border: Border.all(color: Colors.pink.shade300),
               ),
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<String>(
                   isExpanded: true,
                   hint: const Text("Select Branch"),
                   value: sp.overrideBranchId,
                   items: sp.availableBranches.map<DropdownMenuItem<String>>((b) {
                     return DropdownMenuItem<String>(
                       value: b['id'] ?? b['_id'],
                       child: Text(
                         b['name'] ?? 'Unknown Branch',
                         style: const TextStyle(fontWeight: FontWeight.bold),
                       ),
                     );
                   }).toList(),
                   onChanged: (val) {
                     sp.setOverrideBranch(val);
                   },
                 ),
               ),
            ),
          ),

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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = (width > 600) ? 5 : 3;
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: sp.filteredProducts.length,
                      itemBuilder: (_, i) {
                        final p = sp.filteredProducts[i];
                        final String id = p["id"];

                        String? imageUrl;
                        if (p['images'] != null &&
                            p['images'].isNotEmpty &&
                            p['images'][0]['image'] != null &&
                            p['images'][0]['image']['url'] != null) {
                          imageUrl = p['images'][0]['image']['url'];
                          if (imageUrl != null && imageUrl.startsWith('/')) {
                            imageUrl = '${ApiConfig.domain}$imageUrl';
                          }
                        }
                        imageUrl ??=
                            'https://via.placeholder.com/150?text=No+Image';

                        final isSelected = sp.selected[id] == true;
                        final qtyNum = sp.quantities[id] ?? 0.0;
                        String qtyText;
                        if (qtyNum == qtyNum.floorToDouble()) {
                          qtyText = qtyNum.toInt().toString();
                        } else {
                          qtyText = qtyNum.toStringAsFixed(2);
                        }

                        return GestureDetector(
                          onTap: () async {
                            bool isWeightBased = false;
                            try {
                              final unit = p['defaultPriceDetails']?['unit']?.toString().toLowerCase();
                              final isKgFlag = p['isKg'] == true || p['sellByWeight'] == true || p['weightBased'] == true;
                              final pricingType = p['pricingType']?.toString().toLowerCase();

                              if (unit != null && (unit.contains('kg') || unit.contains('gram'))) isWeightBased = true;
                              if (isKgFlag) isWeightBased = true;
                              if (pricingType != null && pricingType.contains('kg')) isWeightBased = true;
                            } catch (e) {
                              isWeightBased = false;
                            }

                            final currentQty = sp.quantities[id] ?? 0.0;

                            if (isWeightBased) {
                              final unit = p['defaultPriceDetails']?['unit'] ?? 'kg';
                              final TextEditingController weightController = TextEditingController(
                                text: currentQty > 0 ? currentQty.toStringAsFixed(2) : '',
                              );
                              final enteredWeight = await showDialog<double>(
                                context: context,
                                barrierDismissible: true,
                                builder: (context) {
                                  return AlertDialog(
                                    title: Text('Enter Weight ($unit)'),
                                    content: TextField(
                                      controller: weightController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        hintText: 'e.g. 0.5',
                                        labelText: 'Weight in $unit',
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          final value = double.tryParse(weightController.text.trim()) ?? 0.0;
                                          Navigator.pop(context, value);
                                        },
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (enteredWeight == null || enteredWeight <= 0) return;
                              sp.updateQuantity(id, enteredWeight);
                            } else {
                              sp.updateQuantity(id, currentQty + 1);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: Colors.green, width: 4)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  spreadRadius: 2,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    Expanded(
                                      flex: 8,
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(
                                            top: Radius.circular(8)),
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrl!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          placeholder: (context, url) =>
                                              const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              const Center(
                                            child: Text(
                                              'No Image',
                                              style: TextStyle(
                                                  color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        width: double.infinity,
                                        decoration: const BoxDecoration(
                                          color: Colors.black,
                                          borderRadius:
                                              BorderRadius.vertical(
                                                  bottom: Radius.circular(8)),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          p["name"] ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  top: 2,
                                  left: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "₹ ${sp.prices[id] ?? 0}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned.fill(
                                    child: Align(
                                      alignment: Alignment.center,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          border: Border.all(
                                              color: Colors.grey, width: 1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        child: Text(
                                          qtyText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

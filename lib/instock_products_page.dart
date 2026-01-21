import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/instock_provider.dart';
import 'package:branch/api_config.dart';

class InstockProductsPage extends StatefulWidget {
  const InstockProductsPage({super.key});

  @override
  _InstockProductsPageState createState() => _InstockProductsPageState();
}

class _InstockProductsPageState extends State<InstockProductsPage> {
  // No need to set live mode as InstockProvider handles it implicitly

  void _toggleProductSelection(int index) async {
    final sp = Provider.of<InstockProvider>(context, listen: false);
    final product = sp.filteredProducts[index];
    final String id = product["id"];

    // Detect Weight Based
    bool isWeightBased = false;
    try {
      final unit = product['defaultPriceDetails']?['unit']?.toString().toLowerCase();
      final isKgFlag = product['isKg'] == true || product['sellByWeight'] == true || product['weightBased'] == true;
      final pricingType = product['pricingType']?.toString().toLowerCase();

      if (unit != null && (unit.contains('kg') || unit.contains('gram'))) isWeightBased = true;
      if (isKgFlag) isWeightBased = true;
      if (pricingType != null && pricingType.contains('kg')) isWeightBased = true;
    } catch (e) {
      isWeightBased = false;
    }

    // Current InStock Value
    double currentStock = sp.inStockQuery[id] ?? 0.0;
    
    if (isWeightBased) {
      final unit = product['defaultPriceDetails']?['unit'] ?? 'kg';
      final TextEditingController weightController = TextEditingController(
        text: currentStock > 0 ? currentStock.toStringAsFixed(2) : '',
      );
      final enteredWeight = await showDialog<double>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: Text('Enter Instock Weight ($unit)'),
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

      if (enteredWeight == null) return;
      sp.updateInStock(id, enteredWeight);
    } else {
      sp.updateInStock(id, currentStock + 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InstockProvider>(
      builder: (context, sp, child) {
        return CommonScaffold(
          title: 'Instock: ${sp.selectedCategoryName ?? "Products"}',
          pageType: PageType.instock, 
          body: sp.isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.black))
              : sp.filteredProducts.isEmpty
                  ? const Center(
                      child: Text('No products found',
                          style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 18)))
                  : Column(
                      children: [
                        Expanded(child: _buildGrid(sp)),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildGrid(InstockProvider sp) {
    return LayoutBuilder(
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
          itemBuilder: (context, index) {
            final product = sp.filteredProducts[index];
            final String id = product["id"];
            
            String? imageUrl;
            if (product['images'] != null &&
                product['images'].isNotEmpty &&
                product['images'][0]['image'] != null &&
                product['images'][0]['image']['url'] != null) {
              imageUrl = product['images'][0]['image']['url'];
              if (imageUrl != null && imageUrl.startsWith('/')) {
                imageUrl = '${ApiConfig.domain}$imageUrl';
              }
            }
            imageUrl ??= 'https://via.placeholder.com/150?text=No+Image';

            final double pVal = sp.prices[id] ?? 0.0;
            final price = '₹${pVal % 1 == 0 ? pVal.toInt() : pVal}';

            final currentStock = sp.inStockQuery[id] ?? 0.0;
            final isSelected = currentStock > 0;
            
            String qtyText;
            if (currentStock == currentStock.floorToDouble()) {
              qtyText = currentStock.toInt().toString();
            } else {
              qtyText = currentStock.toStringAsFixed(2);
            }

            final unitDetails = product['defaultPriceDetails'];
            final double uQty = (unitDetails != null && unitDetails['quantity'] != null) 
                ? (unitDetails['quantity'] as num).toDouble() 
                : 1.0;
            final String uName = unitDetails?['unit'] ?? 'pcs';
            final String uQtyStr = uQty % 1 == 0 ? uQty.toInt().toString() : uQty.toString();
            final String unitDisplay = '$uQtyStr$uName';

            return GestureDetector(
              onTap: () => _toggleProductSelection(index),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected ? Border.all(color: Colors.blue, width: 4) : null,
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
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) =>
                                  const Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) => const Center(
                                child: Text('No Image', style: TextStyle(color: Colors.grey)),
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
                              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              product['name'] ?? 'Unknown',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          price,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          unitDisplay,
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
                              border: Border.all(color: Colors.white, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }


}

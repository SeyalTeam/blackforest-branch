import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/cart_provider.dart';

class ProductsPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const ProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  _ProductsPageState createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<dynamic> _products = [];
  bool _isLoading = true;
  String? _branchId;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  /// Fetch user data and determine branch or waiter roles
  Future<void> _fetchUserData(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/users/me?depth=2'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final user = data['user'] ?? data;
        setState(() {
          _userRole = user['role'];
        });
        if (user['role'] == 'branch' && user['branch'] != null) {
          setState(() {
            _branchId = (user['branch'] is Map) ? user['branch']['id'] : user['branch'];
          });
        } else if (user['role'] == 'waiter') {
          await _fetchWaiterBranch(token);
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  /// Get private device IP (LAN)
  Future<String?> _fetchDeviceIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      return ip?.trim();
    } catch (e) {
      return null;
    }
  }

  /// Convert IP string to int for range comparison
  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  /// Check if an IP falls inside a range "startIP - endIP"
  bool _isIpInRange(String deviceIp, String range) {
    final parts = range.split('-');
    if (parts.length != 2) return false;
    final startIp = _ipToInt(parts[0].trim());
    final endIp = _ipToInt(parts[1].trim());
    final device = _ipToInt(deviceIp);
    return device >= startIp && device <= endIp;
  }

  /// Find the waiter's branch by matching device IP to branch IP or range
  Future<void> _fetchWaiterBranch(String token) async {
    String? deviceIp = await _fetchDeviceIp();
    if (deviceIp == null) return;
    try {
      final allBranchesResponse = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (allBranchesResponse.statusCode == 200) {
        final branchesData = jsonDecode(allBranchesResponse.body);
        if (branchesData['docs'] != null && branchesData['docs'] is List) {
          for (var branch in branchesData['docs']) {
            String? bIpRange = branch['ipAddress']?.toString().trim();
            if (bIpRange != null) {
              if (bIpRange == deviceIp || _isIpInRange(deviceIp, bIpRange)) {
                setState(() {
                  _branchId = branch['id'];
                });
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  /// Fetch all products under a category, filtered by role/branch
  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No token found. Please login again.')),
        );
        return;
      }
      if (_branchId == null && _userRole == null) {
        await _fetchUserData(token);
      }
      // Updated: Fetch all products in the category without restricting to branch overrides
      String url = 'https://admin.theblackforestcakes.com/api/products?where[category][equals]=${widget.categoryId}&limit=100&depth=1';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _products = data['docs'] ?? [];
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch products: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error: Check your internet')),
      );
    }
    setState(() {
      _isLoading = false;
    });
  }

  /// Add or update product in cart
  void _toggleProductSelection(int index) async {
    final product = _products[index];
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    // Step 1: Get product price
    double price = product['defaultPriceDetails']?['price']?.toDouble() ?? 0.0;
    if (_branchId != null && product['branchOverrides'] != null) {
      for (var override in product['branchOverrides']) {
        var branch = override['branch'];
        String branchOid = branch is Map ? (branch[r'$oid'] ?? branch['id'] ?? '') : (branch ?? '');
        if (branchOid == _branchId) {
          price = override['price']?.toDouble() ?? price;
          break;
        }
      }
    }

    // Step 2: Detect if the product is weight-based
    bool isWeightBased = false;
    try {
      final unit = product['defaultPriceDetails']?['unit']?.toString().toLowerCase();
      final isKgFlag = product['isKg'] == true || product['sellByWeight'] == true || product['weightBased'] == true;
      final pricingType = product['pricingType']?.toString().toLowerCase();

      if (unit != null && (unit.contains('kg') || unit.contains('gram'))) isWeightBased = true;
      if (isKgFlag) isWeightBased = true;
      if (pricingType != null && pricingType.contains('kg')) isWeightBased = true;
      // Removed name check to avoid false positives
    } catch (e) {
      isWeightBased = false;
    }

    // Step 3: Get current quantity if exists
    double existingQty = 0.0;
    final existingItem = cartProvider.cartItems.firstWhere(
          (i) => i.id == product['id'],
      orElse: () => CartItem(id: '', name: '', price: 0, quantity: 0),
    );
    if (existingItem.id.isNotEmpty) {
      existingQty = existingItem.quantity.toDouble();
    }

    double quantity = 1.0;
    if (isWeightBased) {
      // Step 4: Show popup if weight-based
      final unit = product['defaultPriceDetails']?['unit'] ?? 'kg';
      final TextEditingController weightController = TextEditingController(
        text: existingQty > 0 ? existingQty.toStringAsFixed(2) : '',
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
      quantity = enteredWeight;
    }

    // Step 5: Update or add
    final item = CartItem.fromProduct(product, quantity, branchPrice: price);
    if (isWeightBased) {
      if (existingItem.id.isNotEmpty) {
        cartProvider.updateQuantity(product['id'], quantity);
      } else {
        cartProvider.addOrUpdateItem(item);
      }
    } else {
      cartProvider.addOrUpdateItem(item);
    }
  }

  /// Barcode scan support
  void _handleScan(String scanResult) {
    for (int index = 0; index < _products.length; index++) {
      final product = _products[index];
      if (product['upc'] == scanResult) {
        _toggleProductSelection(index);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product not found in this category')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Products in ${widget.categoryName}',
      pageType: PageType.billing,
      onScanCallback: _handleScan,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : _products.isEmpty
          ? const Center(
          child: Text('No products found', style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 18)))
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
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final product = _products[index];
              String? imageUrl;
              if (product['images'] != null &&
                  product['images'].isNotEmpty &&
                  product['images'][0]['image'] != null &&
                  product['images'][0]['image']['url'] != null) {
                imageUrl = product['images'][0]['image']['url'];
                if (imageUrl != null && imageUrl.startsWith('/')) {
                  imageUrl = 'https://admin.theblackforestcakes.com$imageUrl';
                }
              }
              imageUrl ??= 'https://via.placeholder.com/150?text=No+Image';

              dynamic priceDetails = product['defaultPriceDetails'];
              if (_branchId != null && product['branchOverrides'] != null) {
                for (var override in product['branchOverrides']) {
                  var branch = override['branch'];
                  String branchOid = branch is Map ? branch[r'$oid'] ?? branch['id'] ?? '' : branch ?? '';
                  if (branchOid == _branchId) {
                    priceDetails = override;
                    break;
                  }
                }
              }
              final price = priceDetails != null ? '₹${priceDetails['price'] ?? 0}' : '₹0';

              return GestureDetector(
                onTap: () => _toggleProductSelection(index),
                child: Consumer<CartProvider>(
                  builder: (context, cartProvider, child) {
                    final isSelected = cartProvider.cartItems.any((i) => i.id == product['id']);
                    final qty = cartProvider.cartItems
                        .firstWhere(
                          (i) => i.id == product['id'],
                      orElse: () => CartItem(
                        id: '',
                        name: '',
                        price: 0,
                        quantity: 0,
                      ),
                    )
                        .quantity;
                    String qtyText;
                    if (qty == qty.floorToDouble()) {
                      qtyText = qty.toInt().toString();
                    } else {
                      qtyText = qty.toStringAsFixed(2);
                    }

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: Colors.green, width: 4) : null,
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
                          if (isSelected)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    border: Border.all(color: Colors.grey, width: 1),
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
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
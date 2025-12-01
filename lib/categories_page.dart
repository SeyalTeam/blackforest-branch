// lib/categories_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:branch/common_scaffold.dart';
import 'package:branch/products_page.dart';
import 'package:branch/stock_order.dart';
import 'package:branch/return_order_page.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:branch/cart_provider.dart';
import 'package:network_info_plus/network_info_plus.dart';

class CategoriesPage extends StatefulWidget {
  final bool isPastryFilter;     // For pastry billing (rarely used)
  final bool isStockFilter;      // For stock orders
  final bool isReturnOrder;      // ⭐ NEW — For Return Orders

  const CategoriesPage({
    super.key,
    this.isPastryFilter = false,
    this.isStockFilter = false,
    this.isReturnOrder = false,
  });

  @override
  _CategoriesPageState createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  List<dynamic> _categories = [];
  bool _isLoading = true;
  String _errorMessage = '';

  String? _companyId;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  // ------------------ USER DATA ------------------
  Future<void> _fetchUserData(String token) async {
    try {
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/users/me?depth=2'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data['user'] ?? data;

        _userRole = user['role'];

        if (user['role'] == 'company') {
          _companyId = (user['company'] is Map)
              ? user['company']['id']
              : user['company'];
        } else if (user['role'] == 'branch') {
          final branch = user['branch'];
          if (branch != null && branch['company'] != null) {
            _companyId = branch['company'] is Map
                ? branch['company']['id']
                : branch['company'];
          }
        }
      }
    } catch (_) {}
  }

  // ------------------ NETWORK HELPERS ------------------
  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  int _ipToInt(String ip) {
    final p = ip.split('.').map(int.parse).toList();
    return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
  }

  bool _ipInRange(String deviceIp, String range) {
    final split = range.split('-');
    if (split.length != 2) return false;
    return _ipToInt(deviceIp) >= _ipToInt(split[0]) &&
        _ipToInt(deviceIp) <= _ipToInt(split[1]);
  }

  Future<List<String>> _matchingCompanies(String token, String? deviceIp) async {
    if (deviceIp == null) return [];

    List<String> ids = [];

    try {
      final res = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final docs = jsonDecode(res.body)['docs'] ?? [];

        for (final b in docs) {
          final r = b['ipAddress']?.toString();
          if (r != null && _ipInRange(deviceIp, r)) {
            final c = b['company'];
            final id = c is Map ? c['id'] : c?.toString();
            if (id != null) ids.add(id);
          }
        }
      }
    } catch (_) {}

    return ids;
  }

  // ------------------ FETCH CATEGORIES ------------------
  Future<void> _fetchCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _errorMessage = "No token found. Please login.";
        setState(() => _isLoading = false);
        return;
      }

      if (_userRole == null) await _fetchUserData(token);

      /// TYPE OF CATEGORY
      String filter;

      if (widget.isReturnOrder) {
        filter = "where[isStock][equals]=true"; // Same products used
      } else if (widget.isStockFilter) {
        filter = "where[isStock][equals]=true";
      } else {
        filter = "where[isBilling][equals]=true";
      }

      // Company filter
      if (_userRole != "superadmin") {
        String? extra;

        if (_userRole == "waiter") {
          final ip = await _deviceIp();
          final matches = await _matchingCompanies(token, ip);
          if (matches.isNotEmpty) {
            extra = "&where[company][in]=${matches.join(',')}";
          }
        } else if (_companyId != null) {
          extra = "&where[company][contains]=$_companyId";
        }

        if (extra != null) filter += extra;
      }

      final res = await http.get(
        Uri.parse(
          "https://admin.theblackforestcakes.com/api/categories?$filter&limit=100&depth=1",
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        _categories = jsonDecode(res.body)['docs'] ?? [];
      } else {
        _errorMessage = "Failed: ${res.statusCode}";
      }
    } catch (e) {
      _errorMessage = "Network error";
    }

    setState(() => _isLoading = false);
  }

  // ------------------ GLOBAL SCAN (Billing Only) ------------------
  Future<void> _handleScan(String scanResult) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final res = await http.get(
        Uri.parse(
          "https://admin.theblackforestcakes.com/api/products?where[upc][equals]=$scanResult&limit=1&depth=1",
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final product = jsonDecode(res.body)['docs']?[0];
        if (product != null) {
          final cart = Provider.of<CartProvider>(context, listen: false);
          double price =
              product['defaultPriceDetails']?['price']?.toDouble() ?? 0;

          cart.addOrUpdateItem(
            CartItem.fromProduct(product, 1, branchPrice: price),
          );
        }
      }
    } catch (_) {}
  }

  // ------------------ UI ------------------
  @override
  Widget build(BuildContext context) {
    // PAGE TITLE + FOOTER TYPE
    String title;
    PageType pageType;

    if (widget.isReturnOrder) {
      title = "Return Order Categories";
      pageType = PageType.returnorder;    // ⭐ FIXED
    } else if (widget.isStockFilter) {
      title = "Stock Order Categories";
      pageType = PageType.stock;          // ⭐ FIXED
    } else {
      title = "Billing Categories";
      pageType = PageType.billing;        // Billing footer highlight
    }

    return CommonScaffold(
      title: title,
      pageType: pageType,
      onScanCallback: _handleScan,
      body: RefreshIndicator(
        onRefresh: _fetchCategories,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.black))
            : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage))
            : _categories.isEmpty
            ? const Center(
          child: Text(
            "No categories found",
            style: TextStyle(fontSize: 18),
          ),
        )
            : _buildGrid(),
      ),
    );
  }

  // ------------------ CATEGORY GRID ------------------
  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cross = constraints.maxWidth > 600 ? 5 : 3;

        return GridView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _categories.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemBuilder: (_, index) {
            final c = _categories[index];

            String? img = c['image']?['url'];
            if (img != null && img.startsWith('/')) {
              img = "https://admin.theblackforestcakes.com$img";
            }
            img ??= "https://via.placeholder.com/150?text=No+Image";

            return GestureDetector(
              onTap: () {
                Widget page;

                if (widget.isReturnOrder) {
                  page = ReturnOrderPage(
                    categoryId: c['id'],
                    categoryName: c['name'],
                  );
                } else if (widget.isStockFilter) {
                  page = const StockOrderPage();
                } else {
                  page = ProductsPage(
                    categoryId: c['id'],
                    categoryName: c['name'],
                  );
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => page),
                );
              },
              child: _buildCard(c, img),
            );
          },
        );
      },
    );
  }

  // ------------------ CARD UI ------------------
  Widget _buildCard(dynamic c, String img) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            flex: 8,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
              child: Text(
                c['name'] ?? "Unknown",
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:branch/api_config.dart';
import 'package:branch/auth_service.dart';

class InstockProvider extends ChangeNotifier {
  // ========== STEP SYSTEM ==========
  String _step = "categories";
  String get step => _step;
  
  // ========== CATEGORY DATA ==========
  List<dynamic> _categories = [];
  List<dynamic> get categories => _categories;

  // ========== PRODUCT DATA ==========
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  List<dynamic> get filteredProducts => _filteredProducts;

  // ========== DEALER DATA ==========
  List<Map<String, dynamic>> _dealers = [];
  List<Map<String, dynamic>> get dealers => _dealers;
  
  String? _selectedDealerId;
  String? get selectedDealerId => _selectedDealerId;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedCategoryName => _selectedCategoryName;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _userRole;
  String? _companyId;
  String? _branchId;
  String? get userRole => _userRole;

  // ========== CART DATA (Separate from StockProvider) ==========
  // We only track inStock values here
  final Map<String, double> _inStockQuery = {}; 
  final Map<String, double> _baseQuantities = {};
  final Map<String, String> _productNames = {};
  final Map<String, double> _prices = {};

  Map<String, double> get inStockQuery => _inStockQuery;
  Map<String, String> get productNames => _productNames;
  Map<String, double> get prices => _prices;

  // ========== CONSTRUCTOR ==========
  InstockProvider() {
    _loadCategories();
  }

  // ========== USER & BRANCH LOGIC (Copied for consistency) ==========
  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  bool _ipInRange(String ip, String range) {
    final parts = range.split("-");
    if (parts.length != 2) return false;
    final start = _ipToInt(parts[0].trim());
    final end = _ipToInt(parts[1].trim());
    final device = _ipToInt(ip);
    return device >= start && device <= end;
  }

  Future<void> _loadUserData(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/users/me?depth=2"),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final user = data["user"] ?? data;

      _userRole = user["role"];

      if (_userRole == "company") {
        _companyId = user["company"] is Map ? user["company"]["id"] : user["company"];
      }

      if (_userRole == "branch") {
        _branchId = user["branch"] is Map ? user["branch"]["id"] : user["branch"];
        final comp = user["branch"]["company"];
        _companyId = comp is Map ? comp["id"] : comp;
      }

      if (_userRole == "waiter") {
        await _detectWaiterBranch(token);
      }
    } catch (_) {}
  }

  Future<void> _detectWaiterBranch(String token) async {
    final ip = await _deviceIp();
    if (ip == null) return;
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/branches?depth=1"),
      headers: ApiConfig.getHeaders(token),
    );
    if (res.statusCode != 200) return;
    final docs = jsonDecode(res.body)["docs"] ?? [];
    for (var b in docs) {
      final range = b["ipAddress"]?.toString().trim();
      if (range != null && (_ipInRange(ip, range) || ip == range)) {
        _branchId = b["id"];
        final comp = b["company"];
        _companyId = comp is Map ? comp["id"] : comp;
        break;
      }
    }
  }

  Future<List<String>> _matchingCompanies(String token, String? ip) async {
    if (ip == null) return [];
    List<String> out = [];
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/branches?depth=1"),
      headers: ApiConfig.getHeaders(token),
    );
    if (res.statusCode != 200) return [];
    final docs = jsonDecode(res.body)["docs"] ?? [];
    for (var b in docs) {
      final range = b["ipAddress"]?.toString().trim();
      if (range != null && _ipInRange(ip, range)) {
        final comp = b["company"];
        final cid = comp is Map ? comp["id"] : comp?.toString();
        if (cid != null) out.add(cid);
      }
    }
    return out;
  }

  // ========== LOAD CATEGORIES ==========
  Future<void> _loadCategories() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) return;

    if (_userRole == null) await _loadUserData(token);

    String query = "where[isStock][equals]=true";
    if (_userRole != "superadmin") {
      if (_companyId != null) {
        query += "&where[company][equals]=$_companyId";
      }
      if (_userRole == "waiter") {
        final ip = await _deviceIp();
        final matches = await _matchingCompanies(token, ip);
        if (matches.isNotEmpty) {
          query += "&where[company][in]=${matches.join(",")}";
        }
      }
    }

    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/categories?$query&limit=100&depth=1"),
      headers: ApiConfig.getHeaders(token),
    );

    if (res.statusCode == 200) {
      _categories = jsonDecode(res.body)["docs"] ?? [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // ========== SELECT CATEGORY & LOAD PRODUCTS ==========
  Future<void> selectCategory(dynamic category) async {
    _selectedCategoryId = category["id"];
    _selectedCategoryName = category["name"];
    _step = "products";
    notifyListeners();
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (_selectedCategoryId == null) return;
    _isLoading = true; // Use bool literal, not variable assignment outside method
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) return;

    final url = "${ApiConfig.baseUrl}/products?where[category][equals]=$_selectedCategoryId&limit=200&depth=2";
    final res = await http.get(Uri.parse(url), headers: ApiConfig.getHeaders(token));

    if (res.statusCode == 200) {
      final docs = jsonDecode(res.body)["docs"] ?? [];
      _products = docs;
      _filteredProducts = docs; 

      for (var p in docs) {
         final id = p["id"];
         dynamic priceDetails = p['defaultPriceDetails'];
         
         // Extract Dealer Info for this product
         var dealer = p["dealer"];
         dealer ??= p["vendor"]; // Fallback 1
         dealer ??= p["supplier"]; // Fallback 2
         dealer ??= p["dealers"]; // Fallback 3 (Plural)
         
         if (dealer != null) {
           String dId;
           String dName;
           if (dealer is Map) {
             dId = dealer["id"] ?? dealer["_id"] ?? "";
             // Updated to check companyName
             dName = dealer["companyName"] ?? dealer["name"] ?? "Unknown Dealer"; 
           } else {
             dId = dealer.toString();
             dName = "Dealer $dId"; // Fallback
           }
           if (dId.isNotEmpty) {
             _productDealers[id] = {"id": dId, "name": dName};
           }
         }

         if (_branchId != null && p['branchOverrides'] != null) {
           for (var override in p['branchOverrides']) {
              var b = override['branch'];
              String bId = b is Map ? b['id'] ?? b['_id'] : b;
              if (bId == _branchId) {
                priceDetails = override;
                break;
              }
           }
         }

         _productNames[id] = p["name"] ?? "Unknown";
         _prices[id] = (priceDetails['price'] as num?)?.toDouble() ?? 0.0;
         _baseQuantities[id] = (priceDetails['quantity'] as num?)?.toDouble() ?? 1.0;
         if (_baseQuantities[id] == 0) _baseQuantities[id] = 1.0;
      }
    }
    _isLoading = false;
    notifyListeners();
    
  }
 
  // ========== CART DEALER FILTER (REMOVED) ==========
  // The backend handles dealer association automatically. 
  // We keep _productDealers map populated in _loadProducts just in case we need it for display later,
  // but filtering logic is removed as per user request.

  final Map<String, Map<String, dynamic>> _productDealers = {}; // productId -> dealerData

  // ========== CART OPERATIONS ==========
  void updateInStock(String productId, double qty) {
    if (qty <= 0) {
      _inStockQuery.remove(productId);
    } else {
      _inStockQuery[productId] = qty;
    }
    notifyListeners();
  }

  void clearCart() {
    _inStockQuery.clear();
    notifyListeners();
  }

  // ========== SUBMIT INSTOCK ==========
  Future<void> submitInstock(BuildContext context) async {
    if (_isSubmitting) return;
    if (_inStockQuery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items updated")),
      );
      return;
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return;

      final List<Map<String, dynamic>> items = [];
      _inStockQuery.forEach((pid, qty) {
        items.add({
          "product": pid,
          "inStock": qty,
          "requiredQty": 0, // Explicitly 0 for instock entry
        });
      });

      // Instock is always "Live" sort of, so we use current time
      final now = DateTime.now();

      final payload = jsonEncode({
         "branch": _branchId,
         "date": now.toUtc().toIso8601String(),
         "items": items.map((item) => {
           "product": item['product'],
           "instock": item['inStock'] // Changed from 'quantity' to 'instock'
         }).toList()
      });

      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/instock-entries"),
        headers: ApiConfig.getHeaders(token),
        body: payload,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Instock Updated Successfully!")),
        );
        clearCart();
        // Optional: Go back to categories
        _step = "categories";
        _products.clear();
        _filteredProducts.clear();
        _selectedCategoryId = null;
        await _loadCategories();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${res.statusCode}")),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}

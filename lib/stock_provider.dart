// UPDATED StockProvider.dart — qty → requiredQty + deliveryDate support
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';

class StockProvider extends ChangeNotifier {
  // ========== STEP SYSTEM ==========
  String _step = "categories";
  String get step => _step;
  set step(String value) {
    _step = value;
    notifyListeners();
  }

  // ========== DELIVERY DATE ==========
  DateTime? _deliveryDate;
  DateTime? get deliveryDate => _deliveryDate;
  set deliveryDate(DateTime? v) {
    _deliveryDate = v;
    notifyListeners();
  }

  // ========== CATEGORY DATA ==========
  List<dynamic> _categories = [];
  List<dynamic> get categories => _categories;

  // ========== PRODUCT DATA ==========
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  List<dynamic> get products => _products;
  List<dynamic> get filteredProducts => _filteredProducts;

  // ========== REPORT DATA ==========
  List<dynamic> _stockReports = [];
  List<dynamic> get stockReports => _stockReports;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedCategoryName => _selectedCategoryName;

  String? _userRole;
  String? _companyId;
  String? _branchId;
  String? get userRole => _userRole;
  String? get companyId => _companyId;
  String? get branchId => _branchId;

  // ========== FIELD MAPS ==========
  final Map<String, int?> _requiredQty = {};          // UPDATED
  final Map<String, int?> _inStock = {};
  final Map<String, bool> _selected = {};
  final Map<String, TextEditingController> _requiredCtrl = {}; // UPDATED
  final Map<String, TextEditingController> _stockCtrl = {};
  final Map<String, String> _productNames = {};
  final Map<String, double> _prices = {};

  final TextEditingController _searchCtrl = TextEditingController();

  Map<String, int?> get quantities => _requiredQty;      // alias
  Map<String, int?> get inStock => _inStock;
  Map<String, bool> get selected => _selected;
  Map<String, TextEditingController> get qtyCtrl => _requiredCtrl;
  Map<String, TextEditingController> get stockCtrl => _stockCtrl;
  Map<String, String> get productNames => _productNames;
  Map<String, double> get prices => _prices;
  TextEditingController get searchCtrl => _searchCtrl;

  // ========== CONSTRUCTOR ==========
  StockProvider() {
    _loadStockCategories();
    _searchCtrl.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _requiredCtrl.forEach((_, c) => c.dispose());
    _stockCtrl.forEach((_, c) => c.dispose());
    super.dispose();
  }

  // ========== IP HELPERS ==========
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

  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  // ========== LOAD USER DATA ==========
  Future<void> _loadUserData(String token) async {
    try {
      final res = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/users/me?depth=2"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final user = data["user"] ?? data;

      _userRole = user["role"];

      if (_userRole == "company") {
        _companyId =
        user["company"] is Map ? user["company"]["id"] : user["company"];
      }

      if (_userRole == "branch") {
        _branchId =
        user["branch"] is Map ? user["branch"]["id"] : user["branch"];
        final comp = user["branch"]["company"];
        _companyId = comp is Map ? comp["id"] : comp;
      }

      if (_userRole == "waiter") {
        await _detectWaiterBranch(token);
      }

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _detectWaiterBranch(String token) async {
    final ip = await _deviceIp();
    if (ip == null) return;

    final res = await http.get(
      Uri.parse("https://admin.theblackforestcakes.com/api/branches?depth=1"),
      headers: {"Authorization": "Bearer $token"},
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

    notifyListeners();
  }

  Future<List<String>> _matchingCompanies(String token, String? ip) async {
    if (ip == null) return [];
    List<String> out = [];

    final res = await http.get(
      Uri.parse("https://admin.theblackforestcakes.com/api/branches?depth=1"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) return [];

    final docs = jsonDecode(res.body)["docs"] ?? [];

    for (var b in docs) {
      final range = b["ipAddress"]?.toString().trim();
      if (range != null && _ipInRange(ip, range)) {
        final comp = b["company"];
        final cid =
        comp is Map ? comp["id"] : comp?.toString();
        if (cid != null) out.add(cid);
      }
    }

    return out;
  }

  // ========== LOAD STOCK CATEGORIES ==========
  Future<void> _loadStockCategories() async {
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
      Uri.parse(
          "https://admin.theblackforestcakes.com/api/categories?$query&limit=100&depth=1"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      _categories = jsonDecode(res.body)["docs"] ?? [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // ========== LOAD PRODUCTS ==========
  Future<void> loadProducts() async {
    if (_selectedCategoryId == null) return;

    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token == null) return;

    final url =
        "https://admin.theblackforestcakes.com/api/products?where[category][equals]=$_selectedCategoryId&limit=200&depth=1";

    final res = await http.get(
      Uri.parse(url),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      final docs = jsonDecode(res.body)["docs"] ?? [];

      _products = docs;
      _filteredProducts = docs;

      for (var p in docs) {
        final id = p["id"];

        _productNames[id] = p["name"] ?? "Unknown";
        _prices[id] =
            (p['defaultPriceDetails']?['price'] as num?)?.toDouble() ?? 0.0;

        _requiredQty.putIfAbsent(id, () => null);
        _inStock.putIfAbsent(id, () => null);
        _selected.putIfAbsent(id, () => false);

        _requiredCtrl.putIfAbsent(id, () => TextEditingController());
        _stockCtrl.putIfAbsent(id, () => TextEditingController());
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // ========== FILTER PRODUCTS ==========
  void _filterProducts() {
    final q = _searchCtrl.text.toLowerCase();
    _filteredProducts = _products
        .where((p) =>
        p["name"].toString().toLowerCase().contains(q))
        .toList();

    notifyListeners();
  }

  // ========== HELPER METHODS FOR UI ==========
  void toggleSelection(String productId, bool value) {
    _selected[productId] = value;
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    _requiredQty[productId] = quantity;
    _selected[productId] = quantity > 0;
    notifyListeners();
  }

  void updateInStock(String productId, int stock) {
    _inStock[productId] = stock;
    final req = _requiredQty[productId] ?? 0;
    _selected[productId] = req > 0;
    notifyListeners();
  }

  // ========== SUBMIT STOCK ORDER ==========
  Future<bool> submitStockOrder(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token == null) return false;

    if (_deliveryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select delivery date & time")),
      );
      return false;
    }

    List<Map<String, dynamic>> items = [];

    for (var entry in _selected.entries) {
      if (entry.value) {
        final pid = entry.key;

        items.add({
          "product": pid,
          "inStock": _inStock[pid],
          "requiredQty": _requiredQty[pid],
        });
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No items selected"),
        ),
      );
      return false;
    }

    final body = jsonEncode({
      "branch": _branchId,
      "deliveryDate": _deliveryDate!.toIso8601String(),
      "items": items,
    });

    final res = await http.post(
      Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: body,
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Stock Order Submitted Successfully!")),
      );

      // RESET
      _requiredQty.clear();
      _inStock.clear();
      _selected.clear();
      _productNames.clear();
      _prices.clear();

      _requiredCtrl.forEach((_, c) => c.dispose());
      _requiredCtrl.clear();
      _stockCtrl.forEach((_, c) => c.dispose());
      _stockCtrl.clear();

      _deliveryDate = null;

      _step = "categories";
      _selectedCategoryId = null;
      _selectedCategoryName = null;

      await _loadStockCategories();
      notifyListeners();

      return true;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed: ${res.statusCode}")),
    );

    return false;
  }

  // ========== SELECT CATEGORY ==========
  Future<void> selectCategory(dynamic category) async {
    _selectedCategoryId = category["id"];
    _selectedCategoryName = category["name"];

    _step = "products";
    notifyListeners();

    await loadProducts();
  }

  // ========== GO BACK ==========
  void goBackToCategories() {
    _step = "categories";
    _selectedCategoryId = null;
    _selectedCategoryName = null;

    _products = [];
    _filteredProducts = [];

    _searchCtrl.clear();

    notifyListeners();
  }

  // ========== REPORT LOGIC ==========

  Future<void> fetchStockReports({DateTime? date}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return;

      if (_userRole == null) await _loadUserData(token);

      // Default to today if no date provided
      final now = date ?? DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

      String query = "where[createdAt][greater_than_equal]=$startOfDay&where[createdAt][less_than_equal]=$endOfDay";

      if (_branchId != null) {
        query += "&where[branch][equals]=$_branchId";
      }

      final res = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders?$query&limit=100&depth=2"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        _stockReports = jsonDecode(res.body)["docs"] ?? [];
      } else {
        _stockReports = [];
      }
    } catch (e) {
      print("Error fetching reports: $e");
      _stockReports = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updateStockOrderReceipt(String orderId, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return false;

      print("Updating stock order $orderId with items: ${jsonEncode(items)}");
      
      final res = await http.patch(
        Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders/$orderId"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"items": items}),
      );

      print("Response status: ${res.statusCode}");
      print("Response body: ${res.body}");

      if (res.statusCode == 200) {
        return true;
      }
    } catch (e) {
      print("Error updating receipt: $e");
    }
    return false;
  }
}

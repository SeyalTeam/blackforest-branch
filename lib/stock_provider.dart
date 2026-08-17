// UPDATED StockProvider.dart — qty → requiredQty + deliveryDate support
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:branch/api_config.dart';
import 'package:branch/auth_service.dart'; // ADDED

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
  bool _isSameDay = false;

  DateTime? get deliveryDate => _deliveryDate;
  bool get isSameDay => _isSameDay;

  set deliveryDate(DateTime? v) {
    _deliveryDate = v;
    notifyListeners();
  }

  void toggleSameDay() {
    _isSameDay = !_isSameDay;
    final now = DateTime.now();
    if (_isSameDay) {
      // No more 2-hour restriction for branch orders
      _deliveryDate = now;
    } else {
      // Default back to Tomorrow 10:00 AM if same-day is toggled off
      _deliveryDate = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1, hours: 10));
    }
    notifyListeners();
  }

  // Explicit setters for UI buttons
  void setStockMode() {
    _isSameDay = false;
    final now = DateTime.now();
    _deliveryDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1, hours: 10));
    notifyListeners();
  }

  void setLiveMode() {
    _isSameDay = true;
    _deliveryDate = DateTime.now();
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

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _userRole;
  String? _companyId;
  String? _branchId;
  String? get userRole => _userRole;
  String? get companyId => _companyId;
  String? get branchId =>
      _overrideBranchId ?? _branchId; // UPDATED: Return override if set

  // ========== SUPERADMIN BRANCH SELECTION ==========
  List<dynamic> _availableBranches = [];
  String? _overrideBranchId;

  List<dynamic> get availableBranches => _availableBranches;
  String? get overrideBranchId => _overrideBranchId;

  // ========== FIELD MAPS ==========
  final Map<String, double?> _requiredQty = {}; // UPDATED
  final Map<String, double?> _inStock = {};
  final Map<String, bool> _selected = {};
  final Map<String, TextEditingController> _requiredCtrl = {}; // UPDATED
  final Map<String, TextEditingController> _stockCtrl = {};
  final Map<String, String> _productNames = {};
  final Map<String, double> _prices = {};
  final Map<String, String> _units = {};
  final Map<String, double> _baseQuantities = {};

  final TextEditingController _searchCtrl = TextEditingController();

  Map<String, double?> get quantities => _requiredQty; // alias
  Map<String, double?> get inStock => _inStock;
  Map<String, bool> get selected => _selected;
  Map<String, TextEditingController> get qtyCtrl => _requiredCtrl;
  Map<String, TextEditingController> get stockCtrl => _stockCtrl;
  Map<String, String> get productNames => _productNames;
  Map<String, double> get prices => _prices;
  Map<String, String> get units => _units;
  Map<String, double> get baseQuantities => _baseQuantities;
  TextEditingController get searchCtrl => _searchCtrl;

  // ========== CONSTRUCTOR ==========
  StockProvider() {
    _loadStockCategories();
    _searchCtrl.addListener(_filterProducts);

    // Default to tomorrow 10:00 AM
    final now = DateTime.now();
    _deliveryDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1, hours: 10));
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
        Uri.parse("${ApiConfig.baseUrl}/users/me?depth=2"),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final user = data["user"] ?? data;

      _userRole = user["role"];

      if (_userRole == "company") {
        _companyId = user["company"] is Map
            ? user["company"]["id"]
            : user["company"];
      }

      if (user["branch"] != null) {
        _branchId = user["branch"] is Map
            ? user["branch"]["id"]
            : user["branch"];
        final comp = user["branch"] is Map ? user["branch"]["company"] : null;
        _companyId = comp is Map ? comp["id"] : comp;
      } else if (_userRole == "waiter" || _userRole == "kitchen" || _userRole == "chef" || _userRole == "manager" || _userRole == "cashier") {
        await _detectWaiterBranch(token);
      }

      if (_userRole == "superadmin") {
        await fetchBranches(token);
      }

      notifyListeners();
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

    notifyListeners();
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

  // ========== FETCH BRANCHES (SUPERADMIN) ==========
  Future<void> fetchBranches(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/branches?depth=1&limit=100"),
        headers: ApiConfig.getHeaders(token),
      );
      if (res.statusCode == 200) {
        _availableBranches = jsonDecode(res.body)["docs"] ?? [];
      }
    } catch (_) {}
  }

  // ========== SET OVERRIDE BRANCH ==========
  Future<void> setOverrideBranch(String? branchId) async {
    _overrideBranchId = branchId;
    notifyListeners();
    // Reload products to apply new branch pricing if a category is selected
    if (_selectedCategoryId != null) {
      await loadProducts();
    }
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
      } else if (_userRole == "waiter" || _userRole == "kitchen" || _userRole == "chef" || _userRole == "manager" || _userRole == "cashier") {
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

    if (res.statusCode == 401) {
      await AuthService.logout();
      return;
    }

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
        "${ApiConfig.baseUrl}/products?where[category][equals]=$_selectedCategoryId&limit=200&depth=1";

    final res = await http.get(
      Uri.parse(url),
      headers: ApiConfig.getHeaders(token),
    );

    if (res.statusCode == 401) {
      await AuthService.logout();
      return;
    }

    if (res.statusCode == 200) {
      final docs = jsonDecode(res.body)["docs"] ?? [];

      _products = docs;
      _filteredProducts = docs;

      for (var p in docs) {
        final id = p["id"];

        // APPLY BRANCH OVERRIDES
        dynamic priceDetails = p['defaultPriceDetails'];
        final currentBranch = _overrideBranchId ?? _branchId;

        if (currentBranch != null && p['branchOverrides'] != null) {
          for (var override in p['branchOverrides']) {
            var b = override['branch'];
            String bId = b is Map ? b['id'] ?? b['_id'] : b;
            if (bId == currentBranch) {
              priceDetails = override;
              break;
            }
          }
        }

        _productNames[id] = p["name"] ?? "Unknown";
        _prices[id] = (priceDetails['price'] as num?)?.toDouble() ?? 0.0;
        _units[id] =
            "${priceDetails['quantity'] ?? ''}${priceDetails['unit'] ?? ''}";
        _baseQuantities[id] =
            (priceDetails['quantity'] as num?)?.toDouble() ?? 1.0;
        if (_baseQuantities[id] == 0) _baseQuantities[id] = 1.0;

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
        .where((p) => p["name"].toString().toLowerCase().contains(q))
        .toList();

    notifyListeners();
  }

  // ========== HELPER METHODS FOR UI ==========
  void toggleSelection(String productId, bool value) {
    _selected[productId] = value;
    notifyListeners();
  }

  void updateQuantity(String productId, double quantity) {
    _requiredQty[productId] = quantity;
    _selected[productId] = quantity > 0;
    notifyListeners();
  }

  void updateInStock(String productId, double stock) {
    _inStock[productId] = stock;
    final req = _requiredQty[productId] ?? 0;
    _selected[productId] = req > 0;
    notifyListeners();
  }

  // ========== SUBMIT STOCK ORDER ==========
  Future<Map<String, dynamic>?> submitStockOrder(BuildContext context) async {
    if (_isSubmitting) return null;
    _isSubmitting = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");

      if (token == null) return null;

      final DateTime now = DateTime.now();

      if (_isSameDay) {
        // If same-day is active, force the date to Today, but keep the selected time
        final selectedTime = _deliveryDate ?? now;
        _deliveryDate = DateTime(
          now.year,
          now.month,
          now.day,
          selectedTime.hour,
          selectedTime.minute,
        );
      }

      if (_deliveryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select delivery date & time")),
        );
        return null;
      }

      // NEW: Prevent past date/time (allow 1 min buffer for network/latency)
      if (_deliveryDate!.isBefore(now.subtract(const Duration(minutes: 1)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cannot place order for a past date or time"),
            backgroundColor: Colors.redAccent,
          ),
        );
        return null;
      }

      // Validation (Removed 2-hour restriction globally)
      List<Map<String, dynamic>> items = [];

      // Create a temporary map to hold names and prices for injection later
      Map<String, String> tempNames = {};
      Map<String, double> tempPrices = {};

      for (var entry in _selected.entries) {
        if (entry.value) {
          final pid = entry.key;
          items.add({
            "product": pid,
            "inStock": _inStock[pid] ?? 0.0,
            "requiredQty": _requiredQty[pid] ?? 0.0,
          });
          tempNames[pid] = _productNames[pid] ?? "Item";
          tempPrices[pid] = _prices[pid] ?? 0.0;
        }
      }

      if (items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No items selected")));
        return null;
      }

      final cashierId = prefs.getString('user_id') ?? prefs.getString('employee_id');
      final cashierName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? prefs.getString('username');

      final body = jsonEncode({
        "branch": branchId,
        "cashierId": cashierId,
        "cashierName": cashierName,
        "deliveryDate": _deliveryDate!.toUtc().toIso8601String(),
        "items": items,
      });

      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/stock-orders"),
        headers: ApiConfig.getHeaders(token),
        body: body,
      );

      if (res.statusCode == 401) {
        await AuthService.logout();
        return null;
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        final jsonResponse = jsonDecode(res.body);
        // Payload CMS often wraps creation response in a 'doc' key
        Map<String, dynamic> orderDoc = jsonResponse['doc'] != null
            ? Map<String, dynamic>.from(jsonResponse['doc'])
            : Map<String, dynamic>.from(jsonResponse);

        // Inject names and prices into the response structure so the printer can use them
        if (orderDoc['items'] != null && orderDoc['items'] is List) {
          List<dynamic> respItems = orderDoc['items'];
          for (var i = 0; i < respItems.length; i++) {
            var item = respItems[i];
            String? pid;
            if (item['product'] is Map) {
              pid = item['product']['id'];
            } else {
              pid = item['product'];
            }

            if (pid != null) {
              // Create a new map to avoid modifying a locked map if any
              Map<String, dynamic> newItem = Map<String, dynamic>.from(item);
              if (tempNames.containsKey(pid)) newItem['name'] = tempNames[pid];
              if (tempPrices.containsKey(pid))
                newItem['price'] = tempPrices[pid];
              newItem['baseQuantity'] = _baseQuantities[pid] ?? 1.0;
              respItems[i] = newItem;
            }
          }
          orderDoc['items'] = respItems;
        }

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

        _isSameDay = false;
        final now = DateTime.now();
        _deliveryDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1, hours: 10));

        _step = "categories";
        _selectedCategoryId = null;
        _selectedCategoryName = null;

        _products = [];
        _filteredProducts = [];
        _overrideBranchId = null; // NEW: Reset branch selection

        await _loadStockCategories();
        notifyListeners();

        return orderDoc; // Return the confirmed order data with names
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed: ${res.statusCode}")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }

    return null;
  }

  // ========== CLEAR CART ==========
  void clearCart() {
    _requiredQty.clear();
    _inStock.clear();
    _selected.clear();
    _requiredCtrl.forEach((_, c) => c.dispose());
    _requiredCtrl.clear();
    _stockCtrl.forEach((_, c) => c.dispose());
    _stockCtrl.clear();
    notifyListeners();
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
      final startOfDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).toIso8601String();
      final endOfDay = DateTime(
        now.year,
        now.month,
        now.day,
        23,
        59,
        59,
      ).toIso8601String();

      String query =
          "where[deliveryDate][greater_than_equal]=$startOfDay&where[deliveryDate][less_than_equal]=$endOfDay";

      if (_branchId != null) {
        query += "&where[branch][equals]=$_branchId";
      }

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/stock-orders?$query&limit=100&depth=2"),
        headers: ApiConfig.getHeaders(token),
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

  Future<bool> updateStockOrderReceipt(
    String orderId,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return false;

      final res = await http.patch(
        Uri.parse("${ApiConfig.baseUrl}/stock-orders/$orderId"),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode({"items": items}),
      );

      if (res.statusCode == 200 || res.statusCode == 202) {
        return true;
      }
    } catch (e) {
      print("Error updating receipt: $e");
    }
    return false;
  }

  void updateOrderLocally(String orderId, List<dynamic> updatedItems) {
    // Find the order index
    final index = _stockReports.indexWhere((o) => o["id"] == orderId);
    if (index != -1) {
      // Create a new map to ensure change detection (though items list ref change might be enough)
      final newOrder = Map<String, dynamic>.from(_stockReports[index]);
      newOrder["items"] = updatedItems;
      _stockReports[index] = newOrder;
      notifyListeners();
    }
  }

  // Clear all data on logout
  void clearData() {
    _branchId = null;
    _companyId = null;
    _userRole = null;
    _categories = [];
    _products = [];
    _stockReports = [];
    _availableBranches = [];
    _selectedCategoryId = null;
    _overrideBranchId = null;
    _deliveryDate = null;

    // Clear cart data
    _requiredQty.clear();
    _inStock.clear();
    _selected.clear();
    _productNames.clear();
    _prices.clear();
    _units.clear();
    _baseQuantities.clear();

    _requiredCtrl.forEach((_, c) => c.dispose());
    _requiredCtrl.clear();
    _stockCtrl.forEach((_, c) => c.dispose());
    _stockCtrl.clear();

    _isLoading = false;
    _isSubmitting = false;
    _step = "categories";
    _selectedCategoryName = null;
    _filteredProducts = [];
    _searchCtrl.clear();

    notifyListeners();
  }
}

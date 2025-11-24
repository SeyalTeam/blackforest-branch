import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:branch/common_scaffold.dart';

class StockOrderPage extends StatefulWidget {
  const StockOrderPage({super.key});

  @override
  _StockOrderPageState createState() => _StockOrderPageState();
}

class _StockOrderPageState extends State<StockOrderPage> {
  // STEP SYSTEM
  String _step = "categories"; // categories → products

  // CATEGORY DATA
  List<dynamic> _categories = [];

  // PRODUCT DATA
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];

  bool _isLoading = true;

  String? _selectedCategoryId;
  String? _selectedCategoryName;

  String? _userRole;
  String? _companyId;
  String? _branchId;

  final Map<int, int?> _quantities = {};
  final Map<int, int?> _inStock = {};
  final Map<int, bool> _selected = {};
  final Map<int, TextEditingController> _qtyCtrl = {};
  final Map<int, TextEditingController> _stockCtrl = {};
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStockCategories();
    _searchCtrl.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.forEach((_, c) => c.dispose());
    _stockCtrl.forEach((_, c) => c.dispose());
    super.dispose();
  }

  // ========= IP HELPERS ==========
  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  bool _ipInRange(String ip, String range) {
    final parts = range.split("-");
    if (parts.length != 2) return false;
    final start = _ipToInt(parts[0].trim());
    final end = _ipToInt(parts[1].trim());
    final dev = _ipToInt(ip);
    return dev >= start && dev <= end;
  }

  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  // ========= USER DATA ==========
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

      setState(() {});
    } catch (_) {}
  }

  Future<void> _detectWaiterBranch(String token) async {
    final ip = await _deviceIp();
    if (ip == null) return;

    try {
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

      setState(() {});
    } catch (_) {}
  }

  Future<List<String>> _matchingCompanies(String token, String? ip) async {
    if (ip == null) return [];
    List<String> out = [];

    try {
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
          final cid = comp is Map ? comp["id"] : comp?.toString();
          if (cid != null) out.add(cid);
        }
      }
    } catch (_) {}

    return out;
  }

  // ========= CATEGORY LOADING ==========
  Future<void> _loadStockCategories() async {
    setState(() => _isLoading = true);

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
        if (matches.isNotEmpty) query += "&where[company][in]=${matches.join(",")}";
      }
    }

    try {
      final res = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/categories?$query&limit=100&depth=1"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        _categories = jsonDecode(res.body)["docs"] ?? [];
      }
    } catch (_) {}

    setState(() => _isLoading = false);
  }

  // ========= LOAD PRODUCTS ==========
  Future<void> _loadProducts() async {
    if (_selectedCategoryId == null) return;

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return;

      final url =
          "https://admin.theblackforestcakes.com/api/products?where[category][equals]=$_selectedCategoryId&limit=200&depth=1";

      final res = await http.get(Uri.parse(url),
          headers: {"Authorization": "Bearer $token"});

      if (res.statusCode == 200) {
        final docs = jsonDecode(res.body)["docs"] ?? [];
        _products = docs;
        _filteredProducts = docs;

        for (int i = 0; i < docs.length; i++) {
          _quantities[i] = null;
          _inStock[i] = null;
          _selected[i] = false;

          _qtyCtrl[i] = TextEditingController();
          _stockCtrl[i] = TextEditingController();
        }
      }
    } catch (_) {}

    setState(() => _isLoading = false);
  }

  // ========= FILTER ==========
  void _filterProducts() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredProducts = _products
          .where((p) => p["name"].toString().toLowerCase().contains(q))
          .toList();
    });
  }

  // ========= API SUBMIT ==========
  Future<void> _submitStockOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) return;

    List<Map<String, dynamic>> items = [];

    for (int i = 0; i < _filteredProducts.length; i++) {
      if (_selected[i] == true) {
        items.add({
          "product": _filteredProducts[i]["id"],
          "inStock": _inStock[i],
          "qty": _quantities[i],
        });
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items selected")),
      );
      return;
    }

    final body = jsonEncode({
      "branch": _branchId,
      "category": _selectedCategoryId,
      "items": items,
    });

    final res = await http.post(
      Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json"
      },
      body: body,
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      // SUCCESS
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Stock Order Submitted Successfully!")),
      );

      // CLEAR
      _quantities.clear();
      _inStock.clear();
      _selected.clear();
      _qtyCtrl.clear();
      _stockCtrl.clear();

      // GO BACK TO CATEGORY PAGE
      setState(() {
        _step = "categories";
        _selectedCategoryId = null;
        _selectedCategoryName = null;
      });

      _loadStockCategories();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: ${res.statusCode}")),
      );
    }
  }

  // ========= UI ==========
  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: _step == "categories"
          ? "Stock Categories"
          : "Products in $_selectedCategoryName",
      pageType: PageType.billsheet,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : _step == "categories"
          ? _buildCategories()
          : _buildProducts(),
    );
  }

  // ========= CATEGORY UI ==========
  Widget _buildCategories() {
    if (_categories.isEmpty) {
      return const Center(child: Text("No categories found"));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (_, i) {
        final c = _categories[i];

        String? img = c["image"]?["url"];
        if (img != null && img.startsWith("/")) {
          img = "https://admin.theblackforestcakes.com$img";
        }
        img ??= "https://via.placeholder.com/200?text=No+Image";

        return GestureDetector(
          onTap: () async {
            _selectedCategoryId = c["id"];
            _selectedCategoryName = c["name"];
            _step = "products";
            await _loadProducts();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.grey.withOpacity(0.15), blurRadius: 4)
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
                    child: Image.network(
                      img!,
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
                      bottom: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    c["name"] ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // ========= PRODUCTS UI ==========
  Widget _buildProducts() {
    return Column(
      children: [
        // SEARCH BAR
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
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

        // PRODUCT LIST
        Expanded(
          child: _filteredProducts.isEmpty
              ? const Center(child: Text("No products found"))
              : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _filteredProducts.length,
            itemBuilder: (_, i) {
              final p = _filteredProducts[i];

              bool enableCheckbox =
                  (_inStock[i] != null && _inStock[i]! > 0) &&
                      (_quantities[i] != null && _quantities[i]! > 0);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _selected[i] == true
                          ? Colors.green
                          : Colors.pink.shade300,
                      width: _selected[i] == true ? 3 : 1),
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

                    _buildInputBox(
                      i,
                      "In Stock",
                      _stockCtrl[i]!,
                          (v) {
                        _inStock[i] = int.tryParse(v);
                        setState(() {});
                      },
                    ),

                    const SizedBox(width: 10),

                    _buildInputBox(
                      i,
                      "Qty",
                      _qtyCtrl[i]!,
                          (v) {
                        _quantities[i] = int.tryParse(v);
                        setState(() {});
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Checkbox(
                        value: _selected[i],
                        onChanged: enableCheckbox
                            ? (v) {
                          setState(() {
                            _selected[i] = v ?? false;
                          });
                        }
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // CONFIRM BUTTON
        Padding(
          padding: const EdgeInsets.all(14),
          child: ElevatedButton(
            onPressed: _submitStockOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Confirm Stock Order",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // ========= INPUT BOX ==========
  Widget _buildInputBox(
      int index,
      String label,
      TextEditingController ctrl,
      Function(String) onChange,
      ) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold)),
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
            controller: ctrl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.only(bottom: 8),
            ),
            onChanged: (v) {
              onChange(v);
              setState(() {}); // refresh checkbox state
            },
          ),
        ),
      ],
    );
  }
}

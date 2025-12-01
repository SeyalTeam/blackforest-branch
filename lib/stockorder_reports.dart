// lib/stockorder_reports.dart (Adapted for Branch App - Shows only current logged-in branch)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'stockorder_detail.dart'; // Assuming this is also adapted if needed

class StockOrdersPage extends StatefulWidget {
  const StockOrdersPage({super.key});

  @override
  State<StockOrdersPage> createState() => _StockOrdersPageState();
}

class _StockOrdersPageState extends State<StockOrdersPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> orders = [];
  List<dynamic> filteredOrders = [];
  Map<String, String> branchNames = {};
  List<Map<String, dynamic>> allBranches = []; // May not need all, but kept for compatibility
  Map<String, String> companyNames = {};
  List<Map<String, dynamic>> allCompanies = [];
  Map<String, String> departmentNames = {};
  Map<String, List<String>> departmentCompanies = {};
  List<Map<String, dynamic>> allDepartments = [];
  Map<String, Map<String, dynamic>> productCache = {};
  bool isLoading = true;
  String? errorMessage;
  String? selectedBranchId; // Will be set to logged-in branch and fixed
  String? currentBranchName; // To display the current branch name
  String? selectedCompanyId;
  String? selectedDepartmentId;
  DateTimeRange? selectedDateRange;

  late AnimationController _fade;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedDateRange = DateTimeRange(start: now, end: now);
    _fade = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fade, curve: Curves.easeIn);
    _fade.forward();
    _loadCurrentBranch(); // Load the logged-in branch first
  }

  @override
  void dispose() {
    _fade.dispose(); // Dispose the controller to prevent ticker leak
    super.dispose();
  }

  Future<void> _loadCurrentBranch() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    selectedBranchId = prefs.getString("branchId"); // Changed to match billsheet.dart

    if (selectedBranchId == null || token == null) {
      // Handle no branch/token - perhaps redirect to login
      Navigator.pushReplacementNamed(context, "/login");
      return;
    }

    // Fetch the current branch name (optional, but for display)
    await _fetchBranch(selectedBranchId!, token);
    setState(() {
      currentBranchName = branchNames[selectedBranchId] ?? "Your Branch";
    });

    // Now fetch other data
    _fetchData();
  }

  Future<void> _fetchData() async {
    // No need to fetch all branches since branch is fixed
    // await _fetchBranches(); // Comment out or remove
    await _fetchCompanies();
    await _fetchDepartments();
    await _fetchOrders();
  }

  // ------------------ HELPERS ------------------
  // (Keep all helpers as-is, no changes needed)

  String? _getId(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;

    if (v is Map) {
      if (v["id"] != null) return v["id"].toString();
      if (v["_id"] != null) return v["_id"].toString();
      if (v[r"$oid"] != null) return v[r"$oid"].toString();

      if (v["value"] is Map) {
        final m = v["value"];
        if (m["id"] != null) return m["id"].toString();
      }
    }
    return null;
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String _formatDelivery(raw) {
    try {
      DateTime? d;
      if (raw is String) {
        d = DateTime.tryParse(raw);
      } else if (raw is Map && raw.containsKey("\$date")) {
        d = DateTime.tryParse(raw["\$date"]);
      }
      if (d != null) {
        d = d.toLocal();
        return "${d.day}/${d.month}/${d.year} "
            "${d.hour}:${d.minute.toString().padLeft(2, "0")}";
      }
    } catch (_) {}
    return "–";
  }

  DateTime? _parseDate(dynamic raw) {
    try {
      DateTime? d;
      if (raw is String) {
        d = DateTime.tryParse(raw);
      } else if (raw is Map && raw.containsKey("\$date")) {
        d = DateTime.tryParse(raw["\$date"]);
      }
      if (d != null) {
        return DateTime(d.year, d.month, d.day);
      }
    } catch (_) {}
    return null;
  }

  String _findDeptForCompany(dynamic order) {
    final cid = _getId(order["company"]) ?? "";
    for (var entry in departmentCompanies.entries) {
      if (entry.value.contains(cid)) {
        return departmentNames[entry.key] ?? "Dept";
      }
    }
    return "–";
  }

  String _abbrevBranch(String name) {
    return name.length >= 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
  }

  String _formatDateRange() {
    if (selectedDateRange == null) return 'NOV 30';
    final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final startMonth = months[selectedDateRange!.start.month - 1];
    final startDay = selectedDateRange!.start.day;
    final startFmt = '$startMonth $startDay';
    final endMonth = months[selectedDateRange!.end.month - 1];
    final endDay = selectedDateRange!.end.day;
    final endFmt = '$endMonth $endDay';
    return startFmt == endFmt ? startFmt : '$startFmt - $endFmt';
  }

  // ------------------ FETCH BRANCHES ------------------
  // Removed _fetchBranches() since we only need the current one
  // Use _fetchBranch() for the logged-in branch only

  // ------------------ FETCH COMPANIES ------------------
  Future<void> _fetchCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token == null) return;

    try {
      final res = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/companies?limit=100&depth=0"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        allCompanies = List<Map<String, dynamic>>.from(parsed["docs"] ?? []);
        for (var c in allCompanies) {
          final id = _getId(c["id"]) ?? "";
          final name = c["name"] ?? "Company";
          companyNames[id] = name;
        }
      }
    } catch (_) {}
  }

  // ------------------ FETCH DEPARTMENTS ------------------
  Future<void> _fetchDepartments() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token == null) return;

    try {
      final res = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/departments?limit=100&depth=1"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        allDepartments = List<Map<String, dynamic>>.from(parsed["docs"] ?? []);
        for (var d in allDepartments) {
          final id = _getId(d["id"]) ?? "";
          departmentNames[id] = d["name"] ?? "Department";
          List<String> compIds = [];
          if (d["company"] is List) {
            for (var c in d["company"]) {
              final cid = _getId(c);
              if (cid != null) compIds.add(cid);
            }
          }
          departmentCompanies[id] = compIds;
        }
      }
    } catch (_) {}
  }

  // ------------------ FETCH ORDERS ------------------
  Future<void> _fetchOrders() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token == null || selectedBranchId == null) {
      Navigator.pushReplacementNamed(context, "/login");
      return;
    }

    try {
      print("Fetching with token: $token"); // Debug print
      // Fetch all orders without branch filter, like in billsheet.dart
      final uri = Uri.parse(
          "https://admin.theblackforestcakes.com/api/stock-orders?limit=200&depth=1");
      final res = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception("Timeout");
      });

      print("Response: ${res.statusCode} - ${res.body.substring(0, 100)}"); // Debug print

      if (res.statusCode != 200) {
        setState(() {
          errorMessage = "Failed: ${res.statusCode}";
          isLoading = false;
        });
        return;
      }

      final parsed = jsonDecode(res.body);
      orders = parsed["docs"] ?? [];

      // Collect company IDs and product IDs (branch IDs not needed since fixed)
      Set<String> companyIds = {};
      Set<String> productIds = {};

      for (var o in orders) {
        final cid = _getId(o["company"]);
        if (cid != null) companyIds.add(cid);

        if (o["items"] is List) {
          for (var it in o["items"]) {
            final pid = _getId(it["product"]);
            if (pid != null) productIds.add(pid);
          }
        }
      }

      // Fetch company names if not already in cache
      await Future.wait(companyIds.where((id) => !companyNames.containsKey(id)).map((id) => _fetchCompany(id, token)));

      // Fetch product details
      await Future.wait(productIds.map((id) => _fetchProduct(id, token)));

      _applyFilters();

      setState(() => isLoading = false);
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Error: $e";
      });
    }
  }

  Future<void> _fetchBranch(String id, String token) async {
    try {
      final r = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/branches/$id"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (r.statusCode == 200) {
        final b = jsonDecode(r.body);
        branchNames[id] = b["name"] ?? b["title"] ?? "Branch";
      } else {
        branchNames[id] = "Branch";
      }
    } catch (_) {
      branchNames[id] = "Branch";
    }
  }

  Future<void> _fetchCompany(String id, String token) async {
    try {
      final r = await http.get(
        Uri.parse("https://admin.theblackforestcakes.com/api/companies/$id"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (r.statusCode == 200) {
        final c = jsonDecode(r.body);
        companyNames[id] = c["name"] ?? "Company";
      } else {
        companyNames[id] = "Company";
      }
    } catch (_) {
      companyNames[id] = "Company";
    }
  }

  Future<void> _fetchProduct(String id, String token) async {
    if (productCache.containsKey(id)) return;

    try {
      final r = await http.get(
        Uri.parse(
            "https://admin.theblackforestcakes.com/api/products/$id?depth=1"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (r.statusCode == 200) {
        productCache[id] = jsonDecode(r.body);
      } else {
        productCache[id] = {};
      }
    } catch (_) {
      productCache[id] = {};
    }
  }

  void _applyFilters() {
    filteredOrders = orders.where((o) {
      bool branchMatch = _getId(o["branch"]) == selectedBranchId; // Added back client-side branch filter
      bool companyMatch = true;
      bool departmentMatch = true;
      bool dateMatch = true;

      if (selectedCompanyId != null) {
        companyMatch = _getId(o["company"]) == selectedCompanyId;
      }

      if (selectedDepartmentId != null) {
        final compIds = departmentCompanies[selectedDepartmentId] ?? [];
        departmentMatch = compIds.contains(_getId(o["company"]));
      }

      if (selectedDateRange != null) {
        final deliveryDate = _parseDate(o["deliveryDate"]);
        if (deliveryDate != null) {
          final startOnly = DateTime(selectedDateRange!.start.year, selectedDateRange!.start.month, selectedDateRange!.start.day);
          final endOnly = DateTime(selectedDateRange!.end.year, selectedDateRange!.end.month, selectedDateRange!.end.day);
          dateMatch = !deliveryDate.isBefore(startOnly) && !deliveryDate.isAfter(endOnly);
        } else {
          dateMatch = false;
        }
      }

      return branchMatch && companyMatch && departmentMatch && dateMatch;
    }).toList();
  }

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: selectedDateRange,
    );
    if (picked != null) {
      setState(() {
        selectedDateRange = picked;
        _applyFilters();
      });
    }
  }

  // ------------------ TOTALS ------------------
  // (Keep as-is)

  int _totalItems(order) {
    return order["items"] is List ? order["items"].length : 0;
  }

  int _totalQty(order) {
    int t = 0;
    if (order["items"] is List) {
      for (var it in order["items"]) {
        t += _toInt(it["requiredQty"]);
      }
    }
    return t;
  }

  int _pendingItems(order) {
    int p = 0;
    if (order["items"] is List) {
      for (var it in order["items"]) {
        if (it["status"] == "pending") p++;
      }
    }
    return p;
  }

  double _totalAmount(order) {
    double t = 0.0;

    if (order["items"] is List) {
      for (var it in order["items"]) {
        final pid = _getId(it["product"]);
        double price = 0.0;

        if (pid != null && productCache[pid] != null) {
          final p = productCache[pid]!;
          if (p["defaultPriceDetails"] != null &&
              p["defaultPriceDetails"]["price"] != null) {
            price = _toDouble(p["defaultPriceDetails"]["price"]);
          } else if (p["price"] != null) {
            price = _toDouble(p["price"]);
          }
        }

        t += price * _toInt(it["requiredQty"]);
      }
    }

    return t;
  }

  // ------------------ UI ------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Stock Report",
          style: TextStyle(color: Colors.white),
        ),
        actions: const [], // Removed company and department filters
      ),
      body: Stack(children: [
        _bg(),
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _showDateRangePicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today, color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _formatDateRange(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Removed branch selector GestureDetector
                      // Instead, show static current branch abbr or name
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          _abbrevBranch(currentBranchName ?? 'BRN'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // _bg(), _body(), _glassCard(), _title(), _statusChip() remain as-is
  // No changes needed for these UI helpers

  Widget _bg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0A0C), Color(0xFF1E1E22)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _body() {
    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (errorMessage != null) {
      return Center(
          child: Text(errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 18)));
    }

    if (filteredOrders.isEmpty) {
      return const Center(
          child: Text("No data", style: TextStyle(color: Colors.white70)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filteredOrders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) {
        final o = filteredOrders[i];
        final orderId =
            _getId(o["_id"]) ?? o["id"]?.toString() ?? ""; // FIXED ID

        return GestureDetector(
          onTap: () {
            if (orderId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invalid Order ID")),
              );
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StockOrderDetailPage(orderId: orderId),
              ),
            ).then((_) => _fetchOrders());
          },
          child: _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // row 1
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _title("Branch",
                        _abbrevBranch(branchNames[_getId(o["branch"])] ?? "Branch")),
                    _title("Ord", _totalItems(o).toString()),
                    _title("Qty", _totalQty(o).toString()),
                    _title("Pen", _pendingItems(o).toString()),
                    _title("Amount", "₹${_totalAmount(o).toStringAsFixed(0)}"),
                  ],
                ),
                const SizedBox(height: 10),
                // row 2
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _title(
                        "Delivery", _formatDelivery(o["deliveryDate"] ?? "")),
                    _statusChip(o["status"] ?? "pending"),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: child,
    );
  }

  Widget _title(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _statusChip(String status) {
    Color c = Colors.orange;
    if (status == "approved") c = Colors.green;
    if (status == "cancelled") c = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: c.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12)),
      child: Text(status.toUpperCase(),
          style: TextStyle(color: c, fontWeight: FontWeight.bold)),
    );
  }
}
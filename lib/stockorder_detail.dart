// lib/stockorder_detail.dart (Adapted for Branch App - Optional branch check added)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum FilterTab { all, pending, approved }

class StockOrderDetailPage extends StatefulWidget {
  final String orderId;
  const StockOrderDetailPage({super.key, required this.orderId});

  @override
  State<StockOrderDetailPage> createState() => _StockOrderDetailPageState();
}

class _StockOrderDetailPageState extends State<StockOrderDetailPage> {
  Map<String, dynamic> order = {};
  bool loading = true;
  final Map<String, TextEditingController> sendQtyControllers = {}; // Renamed for clarity
  final Map<String, TextEditingController> resQtyControllers = {}; // New for Res
  final Map<String, bool> isEditingSend = {};
  final Map<String, bool> isEditingRes = {}; // New for Res
  FilterTab selectedTab = FilterTab.all;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _fetchOrder();
  }

  @override
  void dispose() {
    _searchController.dispose();
    sendQtyControllers.forEach((_, c) => c.dispose());
    resQtyControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  int _toInt(v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

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

  // -----------------------------------------------------------
  // FETCH ORDER
  // -----------------------------------------------------------
  Future<void> _fetchOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final loggedBranchId = prefs.getString("branchId"); // Updated to match casing

    if (token == null || loggedBranchId == null) {
      // Handle missing token or branch - redirect to login
      Navigator.pushReplacementNamed(context, "/login");
      return;
    }

    final res = await http.get(
      Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders/${widget.orderId}?depth=2"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      order = jsonDecode(res.body);

      // Removed branch check to prevent auto-pop

      sendQtyControllers.clear();
      resQtyControllers.clear();
      isEditingSend.clear();
      isEditingRes.clear();
      for (var it in order["items"] ?? []) {
        final id = it["id"].toString();
        final req = _toInt(it["requiredQty"]);
        final send = _toInt(it["sendingQty"]);
        final res = _toInt(it["receivedQty"]);
        final defaultSend = send == 0 ? req : send;
        final defaultRes = res; // No default change for res
        // preserve controller if exists, otherwise create for send
        if (!sendQtyControllers.containsKey(id)) {
          sendQtyControllers[id] = TextEditingController(text: defaultSend.toString());
        } else {
          sendQtyControllers[id]!.text = defaultSend.toString();
        }
        // For res
        if (!resQtyControllers.containsKey(id)) {
          resQtyControllers[id] = TextEditingController(text: defaultRes.toString());
        } else {
          resQtyControllers[id]!.text = defaultRes.toString();
        }
        isEditingSend[id] = false;
        isEditingRes[id] = false;
      }
      setState(() => loading = false);
    } else {
      setState(() {
        order = {};
        loading = false;
      });
    }
  }

  // -----------------------------------------------------------
  // UPDATE SINGLE ITEM
  // -----------------------------------------------------------
  Future<void> _updateItem(String itemId, {int? sendQty, int? resQty, String? status}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final items = order["items"] ?? [];
    int req = 0;
    int currentSend = 0;
    int currentRes = 0;
    String currentStatus = "pending";
    for (var it in items) {
      if (it["id"].toString() == itemId) {
        req = _toInt(it["requiredQty"]);
        currentSend = _toInt(it["sendingQty"]);
        currentRes = _toInt(it["receivedQty"]);
        currentStatus = it["status"] ?? "pending";
      }
    }
    int finalSend = sendQty ?? currentSend;
    int finalRes = resQty ?? currentRes;
    String finalStatus = status ?? currentStatus; // Do not change status unless explicitly provided
    List updated = [];
    for (var it in items) {
      if (it["id"].toString() == itemId) {
        updated.add({
          "id": it["id"],
          "sendingQty": finalSend,
          "receivedQty": finalRes,
          "status": finalStatus,
        });
      } else {
        updated.add({
          "id": it["id"],
          "sendingQty": it["sendingQty"],
          "receivedQty": it["receivedQty"],
          "status": it["status"],
        });
      }
    }
    try {
      await http.patch(
        Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders/${widget.orderId}"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"items": updated}),
      );
    } catch (_) {}
    await _fetchOrder();
  }

  // -----------------------------------------------------------
  // UPDATE ORDER STATUS
  // -----------------------------------------------------------
  Future<void> _updateOrderStatus(String newStatus) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    try {
      await http.patch(
        Uri.parse("https://admin.theblackforestcakes.com/api/stock-orders/${widget.orderId}"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"status": newStatus}),
      );
    } catch (_) {}
    await _fetchOrder();
  }

  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0A0C), Color(0xFF1C1C1E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Column(
            children: [
              _header(),
              if (_showSearch) _searchField(),
              _tabsRow(),
              Expanded(child: _itemList()),
              _orderStatusButton(),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // HEADER WITH SEARCH
  // -----------------------------------------------------------
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              order["invoiceNumber"] ?? "",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _searchController.clear();
              });
            },
            icon: const Icon(Icons.search, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // SEARCH FIELD
  // -----------------------------------------------------------
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search products...",
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {});
                },
                child: const Icon(Icons.close, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // FILTER TABS + COUNTS
  // -----------------------------------------------------------
  Widget _tabsRow() {
    int pending = 0, approved = 0;
    for (var it in order["items"] ?? []) {
      final s = (it["status"] ?? "").toString();
      if (s == "pending") pending++;
      if (s == "approved") approved++;
    }

    Widget pill(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white12 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24, width: selected ? 1 : 0.6),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          pill("All", selectedTab == FilterTab.all, () {
            setState(() => selectedTab = FilterTab.all);
          }),
          const SizedBox(width: 10),
          pill("Pending $pending", selectedTab == FilterTab.pending, () {
            setState(() => selectedTab = FilterTab.pending);
          }),
          const SizedBox(width: 10),
          pill("Approved $approved", selectedTab == FilterTab.approved, () {
            setState(() => selectedTab = FilterTab.approved);
          }),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // PRODUCT LIST
  // -----------------------------------------------------------
  Widget _itemList() {
    final items = List.from(order["items"] ?? []);
    items.sort((a, b) {
      final sa = (a["status"] ?? "").toString();
      final sb = (b["status"] ?? "").toString();
      if (sa == sb) return 0;
      return sa == "pending" ? -1 : 1;
    });

    List filtered = items.where((it) {
      final s = (it["status"] ?? "").toString();
      if (selectedTab == FilterTab.pending && s != "pending") return false;
      if (selectedTab == FilterTab.approved && s != "approved") return false;
      return true;
    }).toList();

    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((it) {
        final name = (it["name"] ?? "").toString().toLowerCase();
        return name.contains(q);
      }).toList();
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, index) {
        final it = filtered[index];
        final id = it["id"].toString();
        final name = it["name"] ?? "";
        final req = _toInt(it["requiredQty"]);
        final send = _toInt(it["sendingQty"]);
        final pick = _toInt(it["pickedQty"]);
        final res = _toInt(it["receivedQty"]);
        final stock = _toInt(it["inStock"]);
        final dif = req - res;
        final status = (it["status"] ?? "").toString();
        final editingSend = isEditingSend[id] ?? false;
        final editingRes = isEditingRes[id] ?? false;
        final sendController = sendQtyControllers[id]!;
        final resController = resQtyControllers[id]!;
        final displaySend = send == 0 ? req : send;
        final displayRes = res;

        return GestureDetector(
          onTap: () {
            if (editingSend || editingRes) {
              setState(() {
                isEditingSend[id] = false;
                isEditingRes[id] = false;
              });
              final newSend = int.tryParse(sendController.text) ?? displaySend;
              final newRes = int.tryParse(resController.text) ?? displayRes;
              bool changed = false;
              if (newSend != displaySend || newRes != displayRes) {
                changed = true;
              }
              if (changed) {
                // Removed status change
                _updateItem(id, sendQty: newSend, resQty: newRes);
              }
              return;
            }
            // Removed status toggle for confirm button
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FIRST ROW — with Req chip sized like Send chip
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Stock - $stock",
                      style: const TextStyle(
                        color: Color(0xFFC8C8C8),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Dif - $dif",
                      style: const TextStyle(
                        color: Color(0xFFC8C8C8),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Req chip (same size as Send chip)
                    Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          "Req - $req",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // SECOND ROW
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 20,
                        children: [
                          // Send is now non-editable, grey bg, white text
                          _chip("Send - $displaySend", bg: Colors.grey.shade700, textColor: Colors.white),
                          _chip("Pic - $pick", bg: Colors.grey.shade700, textColor: Colors.white),
                          GestureDetector(
                            onTap: () => setState(() => isEditingRes[id] = true),
                            child: editingRes
                                ? Container(
                              width: 55,
                              height: 26,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: TextField(
                                controller: resController,
                                autofocus: true,
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (value) {
                                  setState(() => isEditingRes[id] = false);
                                  final qty = int.tryParse(value) ?? displayRes;
                                  if (qty != displayRes) {
                                    // Removed status change
                                    _updateItem(id, resQty: qty);
                                  }
                                },
                              ),
                            )
                                : _chip("Res - $displayRes", bg: const Color(0xFFFFC107), textColor: Colors.black),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Confirm button - non-changeable, display only
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: status == "approved" ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // CHIP UI
  Widget _chip(String label, {required Color bg, required Color textColor}) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // ORDER STATUS BUTTON
  Widget _orderStatusButton() {
    final s = order["status"] ?? "pending";
    Color buttonColor = Colors.orange;
    if (s == "approved" || s == "fulfilled") buttonColor = Colors.green;
    if (s == "cancelled") buttonColor = Colors.red;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: null, // Disabled
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          disabledBackgroundColor: buttonColor, // Keep color when disabled
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          s.toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
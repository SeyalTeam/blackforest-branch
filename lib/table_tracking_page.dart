import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/billsheet.dart'; // To reuse Bill model and fetchBills
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

class TableTrackingPage extends StatefulWidget {
  const TableTrackingPage({super.key});

  @override
  State<TableTrackingPage> createState() => _TableTrackingPageState();
}

class _TableTrackingPageState extends State<TableTrackingPage> {
  List<Bill> _activeBills = [];
  bool _isLoading = true;
  String? _token;
  String? _branchId;
  Timer? _timer;

  // Printer & Branch Details
  String? _printerIp;
  int _printerPort = 9100;
  String? _branchName;
  String? _branchGst;
  String? _branchMobile;
  String? _companyName;

  // ─── Waiter Allocation Mode ────────────────────────────────────────────────
  bool _isAllocationMode = false;
  bool _isLoadingWaiters = false;
  bool _isSavingAllocation = false;
  List<Map<String, dynamic>> _liveWaiters = [];
  int? _selectedWaiterIndex;
  Set<String> _selectedTableKeys = {}; // "SectionName|tableNumber"

  // ─── Bulk Offline Mode ──────────────────────────────────────────────────────
  bool _isBulkOfflineMode = false;
  Set<String> _selectedBulkTables = {}; // "SectionName|tableNumber"
  // ─── Live Table Status (primary grid data from API) ───────────────────────
  List<Map<String, dynamic>> _liveSections = []; // sections with table data
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // Refresh both bills and live status every 10 s
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchActiveBills();
      _fetchLiveTableStatus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _branchId = prefs.getString("branchId");

    if (_token != null && _branchId != null) {
      await _fetchBranchDetails(_token!, _branchId!);
      // live-table-status is now the single source for the grid
      await Future.wait([_fetchActiveBills(), _fetchLiveTableStatus()]);
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchActiveBills() async {
    if (_branchId == null || _token == null) return;
    try {
      final result = await fetchBills(_branchId!, _token);
      if (mounted) {
        setState(() {
          // Filter only running (KOT) bills
          _activeBills = result.where((bill) {
            final status = bill.status.toLowerCase();
            final isFinalBill = status == 'completed' || status == 'settled';
            return !isFinalBill ||
                bill.invoiceNumber.toUpperCase().contains('KOT');
          }).toList();
        });
      }
    } catch (e) {
      print("Error fetching active bills: $e");
    }
  }

  Future<void> _fetchBranchDetails(String token, String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches/$branchId?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final branch = jsonDecode(response.body);
        _branchName = branch['name'] ?? 'Unknown Branch';
        _branchGst = branch['gst'];
        _branchMobile = branch['phone'];
        _printerIp = branch['printerIp'];
        _printerPort = branch['printerPort'] ?? 9100;

        if (branch['company'] != null && branch['company'] is Map) {
          _companyName = branch['company']['name'];
        }
      }
    } catch (_) {}
  }

  // ─── Allocation API methods ────────────────────────────────────────────────

  Future<void> _fetchLiveTableStatus({bool refresh = false}) async {
    if (_branchId == null || _token == null) return;
    try {
      final uri = Uri.parse(
        "${ApiConfig.baseUrl}/widgets/live-table-status?branchId=$_branchId${refresh ? '&refresh=true' : ''}",
      );
      final response = await http.get(uri, headers: ApiConfig.getHeaders(_token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Response: { branches: [ { branchId, sections: [ { sectionName, tables: [...] } ] } ] }
        final branches = data['branches'] as List? ?? [];

        // Find this branch's sections
        Map<String, dynamic>? myBranch;
        for (final b in branches) {
          if (b is Map && b['branchId']?.toString() == _branchId) {
            myBranch = Map<String, dynamic>.from(b);
            break;
          }
        }
        // Fallback: use first branch if branchId not matched (single-branch apps)
        if (myBranch == null && branches.isNotEmpty && branches.first is Map) {
          myBranch = Map<String, dynamic>.from(branches.first as Map);
        }

        final rawSections = (myBranch?['sections'] as List?) ?? [];
        final sections = rawSections
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();

        if (mounted) {
          setState(() {
            _liveSections = sections;
          });
        }
      }
    } catch (e) {
      print("Error fetching live table status: $e");
    }
  }

  Future<void> _fetchLiveWaiters() async {
    if (_branchId == null || _token == null) return;
    setState(() => _isLoadingWaiters = true);
    try {
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/widgets/live-logins?branchId=$_branchId"),
        headers: ApiConfig.getHeaders(_token),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Handle array or {users:[]} or {docs:[]} shapes
        List<dynamic> raw;
        if (data is List) {
          raw = data;
        } else if (data['users'] is List) {
          raw = data['users'];
        } else if (data['docs'] is List) {
          raw = data['docs'];
        } else {
          raw = [];
        }
        if (mounted) {
          setState(() {
            // Show ONLY logged-in users with the 'waiter' role
            _liveWaiters = raw
                .whereType<Map>()
                .map((u) => Map<String, dynamic>.from(u))
                .where((u) => u['role']?.toString().toLowerCase() == 'waiter')
                .toList();
          });
        }
      } else {
        print("live-logins error: HTTP ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      print("Error fetching live waiters: $e");
    } finally {
      if (mounted) setState(() => _isLoadingWaiters = false);
    }
  }

  Future<void> _saveTableAllocation() async {
    if (_selectedWaiterIndex == null || _selectedTableKeys.isEmpty) return;
    setState(() => _isSavingAllocation = true);

    final waiter = _liveWaiters[_selectedWaiterIndex!];
    final waiterId = (waiter['userId'] ?? waiter['id'] ?? waiter['_id'] ?? '').toString();
    final waiterName = (waiter['name'] ?? waiter['username'] ?? 'Unknown').toString();

    final List<Map<String, String>> tablesList = _selectedTableKeys.map((key) {
      final parts = key.split('|');
      return {
        "sectionName": parts[0],
        "tableNumber": parts[1],
      };
    }).toList();

    bool isSuccess = false;
    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/widgets/allocate-table-waiter"),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({
          "branchId": _branchId,
          "waiterId": waiterId,
          "tables": tablesList,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        isSuccess = true;
      } else {
        print("Allocate bulk error: HTTP ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      print("Error allocating tables: $e");
    }

    // Refresh table status to pick up new assignments
    await _fetchLiveTableStatus(refresh: true);

    if (mounted) {
      final count = _selectedTableKeys.length;
      setState(() {
        _isSavingAllocation = false;
        _isAllocationMode = false;
        _selectedWaiterIndex = null;
        _selectedTableKeys.clear();
        _liveWaiters.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSuccess
                ? '$count table${count > 1 ? "s" : ""} assigned to $waiterName'
                : 'Failed to assign tables. Please try again.',
          ),
          backgroundColor:
              isSuccess ? const Color(0xFF006C67) : Colors.red,
        ),
      );
    }
  }

  void _enterAllocationMode() {
    // Show allocation UI + loading spinner immediately, then fetch
    setState(() {
      _isAllocationMode = true;
      _selectedWaiterIndex = null;
      _selectedTableKeys.clear();
    });
    _fetchLiveWaiters();
  }

  void _exitAllocationMode() {
    setState(() {
      _isAllocationMode = false;
      _selectedWaiterIndex = null;
      _selectedTableKeys.clear();
      _liveWaiters.clear();
    });
  }

  void _toggleTableSelection(String sectionName, String tableNumber) {
    final key = '$sectionName|$tableNumber';
    setState(() {
      if (_selectedTableKeys.contains(key)) {
        _selectedTableKeys.remove(key);
      } else {
        _selectedTableKeys.add(key);
      }
    });
  }

  void _enterBulkOfflineMode() {
    setState(() {
      _isBulkOfflineMode = true;
      _selectedBulkTables.clear();
      _isAllocationMode = false;
    });
  }

  void _exitBulkOfflineMode() {
    setState(() {
      _isBulkOfflineMode = false;
      _selectedBulkTables.clear();
    });
  }

  void _toggleBulkTableSelection(String sectionName, String tableNumber) {
    final key = '$sectionName|$tableNumber';
    setState(() {
      if (_selectedBulkTables.contains(key)) {
        _selectedBulkTables.remove(key);
      } else {
        _selectedBulkTables.add(key);
      }
    });
  }

  void _showTableActionDialog(String sectionName, Map<String, dynamic> tableData) {
    final tableNumber = (tableData['tableNumber'] ?? tableData['tableKey'] ?? '').toString();
    final tableLabel = (tableData['tableLabel'] ?? 'Table $tableNumber').toString();
    final bool isOffline = tableData['isOffline'] == true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '$sectionName - $tableLabel',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This table is currently ${isOffline ? "OFFLINE" : "ONLINE"}.',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isOffline 
                  ? 'Making it online will allow customers and waiters to select it.' 
                  : 'Making it offline will hide/lock it from customer scans and waiter selections.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOffline ? const Color(0xFF006C67) : Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _toggleTableOfflineStatus(sectionName, tableNumber, !isOffline);
              },
              child: Text(isOffline ? 'Make Online' : 'Make Offline'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleTableOfflineStatus(String sectionName, String tableNumber, bool targetOffline) async {
    if (_branchId == null || _token == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/widgets/toggle-table-offline"),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({
          "branchId": _branchId,
          "sectionName": sectionName,
          "tableNumber": tableNumber,
          "isOffline": targetOffline,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Table $tableNumber is now ${targetOffline ? "offline" : "online"}'),
              backgroundColor: const Color(0xFF006C67),
            ),
          );
        }
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to update table offline status');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _fetchLiveTableStatus(refresh: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Normalise table identifier to match server logic (strip leading zeros, etc.)
  String normalizeTableKey(String value) {
    final trimmed = value.trim();
    final numeric = int.tryParse(trimmed);
    return numeric != null ? numeric.toString() : trimmed.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    // Primary source: live-table-status; fallback: table config (before first API response)
    final bool hasLiveSections = _liveSections.isNotEmpty;
    final bool canSave =
        _selectedWaiterIndex != null &&
        _selectedTableKeys.isNotEmpty &&
        !_isSavingAllocation;
    final bool canSaveBulk = _selectedBulkTables.isNotEmpty && !_isLoading;

    return CommonScaffold(
      title: _isAllocationMode
          ? "Assign Tables"
          : _isBulkOfflineMode
              ? "Bulk Status Edit"
              : "Live Tables",
      pageType: PageType.table,
      actions: [
        if (_isAllocationMode)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: "Cancel",
            onPressed: _exitAllocationMode,
          )
        else if (_isBulkOfflineMode)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: "Cancel",
            onPressed: _exitBulkOfflineMode,
          )
        else ...[
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: "Bulk toggle online/offline",
            onPressed: _enterBulkOfflineMode,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: "Assign waiter to tables",
            onPressed: _enterAllocationMode,
          ),
        ],
      ],
      body: Column(
        children: [
          // ── Waiter selector bar (visible only in allocation mode) ──
          if (_isAllocationMode) _buildWaiterChipBar(),

          // ── Table grid ──
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.black),
                      )
                    : !hasLiveSections
                    ? const Center(
                        child: Text(
                          "No tables configured. Please use Table Creation.",
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.wait([
                            _fetchActiveBills(),
                            _fetchLiveTableStatus(refresh: true),
                          ]);
                        },
                        child: ListView.builder(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16,
                            bottom: (_isAllocationMode || (_isBulkOfflineMode && _selectedBulkTables.isNotEmpty)) ? 100 : 16,
                          ),
                          itemCount: _liveSections.length,
                          itemBuilder: (context, index) {
                            return _buildSectionGrid(_liveSections[index]);
                          },
                        ),
                      ),

                // ── Floating Save Button (allocation mode only) ──
                if (_isAllocationMode)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildSaveButton(canSave),
                  ),

                // ── Floating Bulk Action Bar (bulk offline mode only) ──
                if (_isBulkOfflineMode && _selectedBulkTables.isNotEmpty)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildBulkActionBar(canSaveBulk),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Waiter Dropdown Panel ────────────────────────────────────────────────

  Widget _buildWaiterChipBar() {
    final selectedWaiterName = _selectedWaiterIndex != null
        ? (_liveWaiters[_selectedWaiterIndex!]['name'] ??
            _liveWaiters[_selectedWaiterIndex!]['username'] ??
            'Waiter')
        : null;

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Select Waiter",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          _isLoadingWaiters
              ? const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF006C67),
                      ),
                    ),
                  ),
                )
              : _liveWaiters.isEmpty
              ? Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    "No staff logged in today",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                )
              : Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedWaiterIndex != null
                          ? const Color(0xFF006C67)
                          : Colors.grey.shade300,
                      width: _selectedWaiterIndex != null ? 1.5 : 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _selectedWaiterIndex,
                      hint: const Text(
                        "Tap to choose a waiter...",
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _selectedWaiterIndex != null
                            ? const Color(0xFF006C67)
                            : Colors.grey,
                      ),
                      onChanged: (int? newIndex) {
                        setState(() {
                          _selectedWaiterIndex = newIndex;
                          _selectedTableKeys.clear();
                        });
                      },
                      items: List.generate(
                        _liveWaiters.length,
                        (i) {
                          final w = _liveWaiters[i];
                          final name =
                              w['name'] ?? w['username'] ?? 'Waiter ${i + 1}';
                          return DropdownMenuItem<int>(
                            value: i,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 18,
                                  color: Color(0xFF006C67),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
          if (_selectedWaiterIndex != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Now tap tables below to select them for $selectedWaiterName",
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF006C67),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Save Allocation Button ───────────────────────────────────────────────

  Widget _buildSaveButton(bool canSave) {
    final String label;
    if (_selectedWaiterIndex == null) {
      label = "Select a waiter first";
    } else if (_selectedTableKeys.isEmpty) {
      label = "Tap tables to select";
    } else {
      final waiterName = _liveWaiters[_selectedWaiterIndex!]['name'] ??
          _liveWaiters[_selectedWaiterIndex!]['username'] ??
          'Waiter';
      final count = _selectedTableKeys.length;
      label = "Save  ($count table${count > 1 ? 's' : ''} → $waiterName)";
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: canSave ? 1.0 : 0.5,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF006C67),
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: canSave ? _saveTableAllocation : null,
          child: _isSavingAllocation
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.save_alt_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ─── Section Grid ─────────────────────────────────────────────────────────

  Widget _buildSectionGrid(Map<String, dynamic> section) {
    // Live-table-status shape: { sectionName, tables: [...] }
    final sectionName =
        (section['sectionName'] ?? section['name'] ?? 'Section').toString();
    final tables =
        (section['tables'] as List? ?? []).whereType<Map>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(
            sectionName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final tableData = Map<String, dynamic>.from(tables[index]);
            return _buildTableCard(sectionName, tableData);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Table Card ───────────────────────────────────────────────────────────
  // Now driven by live-table-status data (occupied, elapsed, KOT, amount,
  // servedBy, assignedWaiterName, isOffline) — Bill objects only used for
  // the detail bottom sheet and printing.

  Widget _buildTableCard(String sectionName, Map<String, dynamic> tableData) {
    final tableNumber =
        (tableData['tableNumber'] ?? tableData['tableKey'] ?? '').toString();
    final tableLabel =
        (tableData['tableLabel'] ?? 'Table $tableNumber').toString();
    final bool isOccupied = tableData['occupied'] == true;
    final bool isOffline = tableData['isOffline'] == true;
    final String selectionKey = '$sectionName|$tableNumber';
    final bool isSelected = _selectedTableKeys.contains(selectionKey);
    final bool isBulkSelected = _selectedBulkTables.contains(selectionKey);

    // Waiter badge: prefer live assigned name from allocation
    final String? assignedWaiter =
        (tableData['assignedWaiterName'] ?? '').toString().trim().isEmpty
            ? null
            : tableData['assignedWaiterName'].toString().trim();

    // Occupied table info from live status
    final String? kotNumber = tableData['kotNumber']?.toString();
    final String? servedBy = (tableData['servedBy'] ?? '').toString().trim().isEmpty
        ? null
        : tableData['servedBy'].toString().trim();
    final double? totalAmount =
        (tableData['totalAmount'] as num?)?.toDouble();
    final int? elapsedSeconds = tableData['elapsedSeconds'] as int?;
    final String? billId = tableData['billId']?.toString();

    // Colour logic
    Color cardColor;
    Color borderColor;
    double borderWidth;

    if (_isBulkOfflineMode && isBulkSelected) {
      cardColor = const Color(0xFFE3F2FD);
      borderColor = Colors.blue;
      borderWidth = 2.5;
    } else if (isOffline) {
      cardColor = const Color(0xFFEEEEEE);
      borderColor = Colors.grey.shade400;
      borderWidth = 1;
    } else if (_isAllocationMode && isSelected) {
      cardColor = const Color(0xFFE0F5F0);
      borderColor = const Color(0xFF006C67);
      borderWidth = 2.5;
    } else if (isOccupied) {
      cardColor = const Color(0xFFFFF176);
      borderColor = Colors.orange.shade200;
      borderWidth = 1;
    } else {
      cardColor = const Color(0xFFEEEEEE);
      borderColor = Colors.grey.shade300;
      borderWidth = 1;
    }

    return GestureDetector(
      onTap: _isAllocationMode
          ? (isOffline ? null : () => _toggleTableSelection(sectionName, tableNumber))
          : _isBulkOfflineMode
              ? () => _toggleBulkTableSelection(sectionName, tableNumber)
              : () => _showTableActionDialog(sectionName, tableData),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Card body ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: (_isAllocationMode && isSelected) || (_isBulkOfflineMode && isBulkSelected)
                  ? [
                      BoxShadow(
                        color: _isBulkOfflineMode
                            ? Colors.blue.withOpacity(0.18)
                            : const Color(0xFF006C67).withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFF800000), // Maroon
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    tableLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      // Offline label
                      if (isOffline)
                        const Text(
                          'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),

                      // Elapsed timer (server-side seconds)
                      if (isOccupied && elapsedSeconds != null) ...[
                        Text(
                          _formatElapsed(elapsedSeconds),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Table label moved to cap

                      // Occupied details
                      if (isOccupied) ...[
                        const SizedBox(height: 4),
                        if (kotNumber != null && kotNumber.isNotEmpty)
                          Text(
                            kotNumber,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),

                        if (totalAmount != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Rs ${totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ],
                        ],
                      ),
                    ),
                  ),
                ),



                // ── Selected checkmark (allocation mode or bulk offline mode) ──
                if ((_isAllocationMode && isSelected) || (_isBulkOfflineMode && isBulkSelected))
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _isBulkOfflineMode ? Colors.blue : const Color(0xFF006C67),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),

                // ── Offline lock icon (top-right) ──
                if (isOffline)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                  ),
              ],
            ),
          ),
          if (assignedWaiter != null || servedBy != null)
            Container(
              color: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                (assignedWaiter ?? servedBy)!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    ),
  ],
),
);
}

  Future<void> _submitBulkToggleStatus(bool targetOffline) async {
    if (_branchId == null || _token == null || _selectedBulkTables.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final List<Map<String, String>> tablesList = _selectedBulkTables.map((key) {
      final parts = key.split('|');
      return {
        "sectionName": parts[0],
        "tableNumber": parts[1],
      };
    }).toList();

    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/widgets/toggle-table-offline"),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({
          "branchId": _branchId,
          "isOffline": targetOffline,
          "tables": tablesList,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          final count = _selectedBulkTables.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$count table${count > 1 ? "s are" : " is"} now ${targetOffline ? "offline" : "online"}'),
              backgroundColor: const Color(0xFF006C67),
            ),
          );
        }
        setState(() {
          _isBulkOfflineMode = false;
          _selectedBulkTables.clear();
        });
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to update tables offline status');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _fetchLiveTableStatus(refresh: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildBulkActionBar(bool canSave) {
    final count = _selectedBulkTables.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "$count selected",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF006C67),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onPressed: canSave ? () => _submitBulkToggleStatus(false) : null,
            child: const Text(
              "Make Online",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onPressed: canSave ? () => _submitBulkToggleStatus(true) : null,
            child: const Text(
              "Make Offline",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Format elapsed seconds from the server into a human-readable string.
  String _formatElapsed(int? seconds) {
    if (seconds == null || seconds < 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }



}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/api_config.dart';

class TableCreationPage extends StatefulWidget {
  const TableCreationPage({super.key});

  @override
  _TableCreationPageState createState() => _TableCreationPageState();
}

class _TableCreationPageState extends State<TableCreationPage> {
  Map<String, dynamic>? _tableConfig;
  bool _isLoading = true;
  String _errorMessage = '';
  String? _token;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _branchId = prefs.getString("branchId");
    _fetchTableConfig();
  }

  Future<void> _fetchTableConfig() async {
    if (_token == null || _branchId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/tables?where[branch][equals]=$_branchId&limit=1&depth=0",
        ),
        headers: ApiConfig.getHeaders(_token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data["docs"] as List;
        setState(() {
          if (docs.isNotEmpty) {
            _tableConfig = docs.first;
          } else {
            _tableConfig = null;
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to fetch config: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network error. Check connection.";
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfig(List<dynamic> sections) async {
    if (_token == null || _branchId == null) return;

    setState(() => _isLoading = true);

    try {
      http.Response response;
      if (_tableConfig == null) {
        response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/tables"),
          headers: ApiConfig.getHeaders(_token),
          body: jsonEncode({"branch": _branchId, "sections": sections}),
        );
      } else {
        response = await http.patch(
          Uri.parse("${ApiConfig.baseUrl}/tables/${_tableConfig!["id"]}"),
          headers: ApiConfig.getHeaders(_token),
          body: jsonEncode({"sections": sections}),
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        _fetchTableConfig();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Changes saved successfully!")),
        );
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed: ${response.statusCode}")),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Network error")));
    }
  }

  void _showSectionDialog({Map<String, dynamic>? existingSection, int? index}) {
    final nameController = TextEditingController(
      text: existingSection?["name"] ?? "",
    );
    final countController = TextEditingController(
      text: existingSection?["tableCount"]?.toString() ?? "",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingSection == null ? "Add Section" : "Edit Section"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: "Section Name (e.g. AC, Non-AC)",
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: "Number of Tables"),
            ),
          ],
        ),
        actions: [
          if (existingSection != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmDeleteSection(index!);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final count = int.tryParse(countController.text.trim());

              if (name.isNotEmpty && count != null && count > 0) {
                List<dynamic> currentSections = List.from(
                  _tableConfig?["sections"] ?? [],
                );
                if (index == null) {
                  currentSections.add({"name": name, "tableCount": count});
                } else {
                  currentSections[index] = {"name": name, "tableCount": count};
                }
                _saveConfig(currentSections);
                Navigator.pop(context);
              }
            },
            child: Text(existingSection == null ? "Add" : "Update"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSection(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Section"),
        content: const Text("Are you sure you want to delete this section?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              List<dynamic> currentSections = List.from(
                _tableConfig?["sections"] ?? [],
              );
              currentSections.removeAt(index);
              _saveConfig(currentSections);
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = (_tableConfig?["sections"] as List?) ?? [];

    if (_isLoading && _tableConfig == null) {
      return CommonScaffold(
        title: "Table Creation",
        pageType: PageType.table,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    }

    return DefaultTabController(
      length: sections.length + 1,
      child: CommonScaffold(
        title: "Table Creation",
        pageType: PageType.table,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showSectionDialog(),
          ),
        ],
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.redAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.redAccent,
          tabs: [
            const Tab(text: "All Tables"),
            ...sections.map((s) => Tab(text: s["name"] ?? "Section")),
          ],
        ),
        body: TabBarView(
          children: [
            // All Tables View
            RefreshIndicator(
              onRefresh: _fetchTableConfig,
              child: sections.isEmpty
                  ? const Center(
                      child: Text("No sections found. Tap + to add."),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: sections.length,
                      itemBuilder: (context, index) {
                        return _buildSectionGrid(sections[index], index);
                      },
                    ),
            ),
            // Individual Section Views
            ...sections.asMap().entries.map((entry) {
              return RefreshIndicator(
                onRefresh: _fetchTableConfig,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _buildSectionGrid(
                    entry.value,
                    entry.key,
                    showHeader: false,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionGrid(
    dynamic section,
    int sectionIndex, {
    bool showHeader = true,
  }) {
    final name = section["name"] ?? "Section";
    final count = section["tableCount"] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: Colors.blue,
                  ),
                  onPressed: () => _showSectionDialog(
                    existingSection: section,
                    index: sectionIndex,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            return _buildTableCard(index + 1);
          },
        ),
      ],
    );
  }

  Widget _buildTableCard(int number) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          "$number",
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w400,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';

class FavoriteRuleCategoriesPage extends StatefulWidget {
  final String ruleId;
  final String ruleName;
  final List<String> initialCategories;
  final String token;
  final String companyId;

  const FavoriteRuleCategoriesPage({
    Key? key,
    required this.ruleId,
    required this.ruleName,
    required this.initialCategories,
    required this.token,
    required this.companyId,
  }) : super(key: key);

  @override
  _FavoriteRuleCategoriesPageState createState() => _FavoriteRuleCategoriesPageState();
}

class _FavoriteRuleCategoriesPageState extends State<FavoriteRuleCategoriesPage> {
  List<Map<String, dynamic>> _allCategories = [];
  List<Map<String, dynamic>> _displayedCategories = [];
  Set<String> _selectedCategoryIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategoryIds = Set.from(widget.initialCategories);
    _fetchCategories();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/categories?limit=2000&depth=2'),
        headers: ApiConfig.getHeaders(widget.token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final docs = data['docs'] as List<dynamic>? ?? [];
        
        final List<Map<String, dynamic>> categoriesList = [];
        for (var doc in docs) {
          if (doc is Map) {
            bool belongsToCompany = false;
            
            // 1. Check doc.company directly
            final catCompanies = doc['company'];
            if (catCompanies is List) {
              for (var c in catCompanies) {
                final cId = c is Map ? (c['id'] ?? c['_id']) : c.toString();
                if (cId == widget.companyId) {
                  belongsToCompany = true;
                  break;
                }
              }
            }
            
            // 2. Check doc.department.company
            if (!belongsToCompany) {
              final department = doc['department'];
              if (department is Map) {
                final depCompanies = department['company'];
                if (depCompanies is List) {
                  for (var c in depCompanies) {
                    final cId = c is Map ? (c['id'] ?? c['_id']) : c.toString();
                    if (cId == widget.companyId) {
                      belongsToCompany = true;
                      break;
                    }
                  }
                }
              }
            }

            if (belongsToCompany) {
              categoriesList.add({
                'id': doc['id'] ?? doc['_id'],
                'name': doc['name'] ?? 'Unknown Category',
                'departmentName': (doc['department'] is Map) 
                    ? (doc['department']['name'] ?? '') 
                    : '',
              });
            }
          }
        }
        
        setState(() {
          _allCategories = categoriesList;
          _updateDisplayedCategories();
        });
      }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load categories')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged() {
    _updateDisplayedCategories();
  }

  void _updateDisplayedCategories() {
    final query = _searchController.text.trim().toLowerCase();
    
    // Filter by search query
    List<Map<String, dynamic>> filtered = _allCategories.where((c) {
      if (query.isEmpty) return true;
      final name = c['name'].toString().toLowerCase();
      final deptName = c['departmentName'].toString().toLowerCase();
      return name.contains(query) || deptName.contains(query);
    }).toList();

    // Sort: Selected first, then prefix match, then word prefix match, then alphabetical
    filtered.sort((a, b) {
      final aSelected = _selectedCategoryIds.contains(a['id']);
      final bSelected = _selectedCategoryIds.contains(b['id']);
      
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;

      final aName = a['name'].toString().toLowerCase();
      final bName = b['name'].toString().toLowerCase();
      
      if (query.isNotEmpty) {
        final aPrefix = aName.startsWith(query);
        final bPrefix = bName.startsWith(query);
        if (aPrefix && !bPrefix) return -1;
        if (!aPrefix && bPrefix) return 1;

        final aWordPrefix = aName.split(' ').any((w) => w.startsWith(query));
        final bWordPrefix = bName.split(' ').any((w) => w.startsWith(query));
        if (aWordPrefix && !bWordPrefix) return -1;
        if (!aWordPrefix && bWordPrefix) return 1;
      }

      return aName.compareTo(bName);
    });

    setState(() {
      _displayedCategories = filtered;
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/widgets/update-favorite-category-rule-categories'),
        headers: ApiConfig.getHeaders(widget.token),
        body: json.encode({
          'ruleId': widget.ruleId,
          'categories': _selectedCategoryIds.toList(),
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Categories updated successfully')),
          );
          Navigator.of(context).pop(true); // Return true to indicate update
        }
      } else {
        throw Exception('Failed to update categories');
      }
    } catch (e) {
      debugPrint('Error saving categories: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save changes')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontWeight: FontWeight.bold));
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final List<TextSpan> spans = [];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: const TextStyle(color: Colors.black)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: const TextStyle(color: Colors.black)));
      }

      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
      );

      start = index + query.length;
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: widget.ruleName,
      pageType: PageType.home,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search Categories...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedCategoryIds.length} Selected',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_selectedCategoryIds.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedCategoryIds.clear();
                              _updateDisplayedCategories();
                            });
                          },
                          child: const Text('Clear All'),
                        )
                    ],
                  ),
                ),
                Expanded(
                  child: _displayedCategories.isEmpty
                      ? const Center(child: Text('No categories found'))
                      : ListView.builder(
                          itemCount: _displayedCategories.length,
                          itemBuilder: (context, index) {
                            final category = _displayedCategories[index];
                            final categoryId = category['id'];
                            final isSelected = _selectedCategoryIds.contains(categoryId);

                            return CheckboxListTile(
                              value: isSelected,
                              title: _buildHighlightedText(category['name'], _searchController.text.trim()),
                              subtitle: category['departmentName'].isNotEmpty
                                  ? Text('Dept: ${category['departmentName']}', style: const TextStyle(fontSize: 12))
                                  : null,
                              onChanged: (bool? checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedCategoryIds.add(categoryId);
                                  } else {
                                    _selectedCategoryIds.remove(categoryId);
                                  }
                                  _updateDisplayedCategories();
                                });
                              },
                              activeColor: const Color(0xFFED8F03),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFED8F03),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Save Changes',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

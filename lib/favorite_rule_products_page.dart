import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';

class FavoriteRuleProductsPage extends StatefulWidget {
  final String ruleId;
  final String ruleName;
  final List<String> initialProducts;
  final String token;
  final String companyId;

  const FavoriteRuleProductsPage({
    Key? key,
    required this.ruleId,
    required this.ruleName,
    required this.initialProducts,
    required this.token,
    required this.companyId,
  }) : super(key: key);

  @override
  _FavoriteRuleProductsPageState createState() => _FavoriteRuleProductsPageState();
}

class _FavoriteRuleProductsPageState extends State<FavoriteRuleProductsPage> {
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _displayedProducts = [];
  Set<String> _selectedProductIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedProductIds = Set.from(widget.initialProducts);
    _fetchProducts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/products?limit=2000&depth=2'),
        headers: ApiConfig.getHeaders(widget.token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final docs = data['docs'] as List<dynamic>? ?? [];
        
        final List<Map<String, dynamic>> productsList = [];
        for (var doc in docs) {
          if (doc is Map) {
            bool belongsToCompany = false;
            final category = doc['category'];
            
            if (category is Map) {
              // 1. Check category.company directly
              final catCompanies = category['company'];
              if (catCompanies is List) {
                for (var c in catCompanies) {
                  final cId = c is Map ? (c['id'] ?? c['_id']) : c.toString();
                  if (cId == widget.companyId) {
                    belongsToCompany = true;
                    break;
                  }
                }
              }
              
              // 2. Check category.department.company
              if (!belongsToCompany) {
                final department = category['department'];
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
            }

            if (belongsToCompany) {
              productsList.add({
                'id': doc['id'] ?? doc['_id'],
                'name': doc['name'] ?? 'Unknown Product',
                'categoryName': (doc['category'] is Map) 
                    ? (doc['category']['name'] ?? '') 
                    : '',
              });
            }
          }
        }
        
        setState(() {
          _allProducts = productsList;
          _updateDisplayedProducts();
        });
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load products')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged() {
    _updateDisplayedProducts();
  }

  void _updateDisplayedProducts() {
    final query = _searchController.text.trim().toLowerCase();
    
    // Filter by search query and category
    List<Map<String, dynamic>> filtered = _allProducts.where((p) {
      final category = p['categoryName'].toString();
      if (_selectedCategory != 'All' && category != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      final name = p['name'].toString().toLowerCase();
      return name.contains(query) || category.toLowerCase().contains(query);
    }).toList();

    // Sort: Selected first, then prefix match, then word prefix match, then alphabetical
    filtered.sort((a, b) {
      final aSelected = _selectedProductIds.contains(a['id']);
      final bSelected = _selectedProductIds.contains(b['id']);
      
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;
      
      if (query.isNotEmpty) {
        final aName = a['name'].toString().toLowerCase();
        final bName = b['name'].toString().toLowerCase();

        // Exact startsWith priority
        final aStartsWith = aName.startsWith(query);
        final bStartsWith = bName.startsWith(query);
        if (aStartsWith && !bStartsWith) return -1;
        if (!aStartsWith && bStartsWith) return 1;

        // Word startsWith priority
        final aWordStartsWith = aName.split(' ').any((w) => w.startsWith(query));
        final bWordStartsWith = bName.split(' ').any((w) => w.startsWith(query));
        if (aWordStartsWith && !bWordStartsWith) return -1;
        if (!aWordStartsWith && bWordStartsWith) return 1;
      }

      return a['name'].toString().compareTo(b['name'].toString());
    });

    setState(() {
      _displayedProducts = filtered;
    });
  }

  Future<void> _saveProducts() async {
    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/widgets/update-favorite-rule-products'),
        headers: ApiConfig.getHeaders(widget.token),
        body: json.encode({
          'ruleId': widget.ruleId,
          'products': _selectedProductIds.toList(),
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favorite products updated successfully')),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      } else {
        throw Exception('Failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error saving rule products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save products')),
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
      return Text(text, style: const TextStyle(fontSize: 16));
    }
    
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    
    if (!lowerText.contains(lowerQuery)) {
      return Text(text, style: const TextStyle(fontSize: 16));
    }

    final spans = <TextSpan>[];
    int start = 0;
    int indexOfMatch;
    
    while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch)));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
      ));
      start = indexOfMatch + query.length;
    }
    
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black, fontSize: 16),
        children: spans,
      ),
    );
  }

  List<String> get _categories {
    final cats = _allProducts
        .map((p) => p['categoryName'].toString())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    cats.sort();
    return ['All', ...cats];
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: widget.ruleName,
      pageType: PageType.home,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          if (_allProducts.isNotEmpty)
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = _selectedCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = selected ? category : 'All';
                          _updateDisplayedProducts();
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _displayedProducts.length,
                    itemBuilder: (context, index) {
                      final product = _displayedProducts[index];
                      final isSelected = _selectedProductIds.contains(product['id']);
                      final categoryName = product['categoryName'];

                      return CheckboxListTile(
                        title: _buildHighlightedText(product['name'], _searchController.text.trim()),
                        subtitle: categoryName.isNotEmpty ? Text(categoryName) : null,
                        value: isSelected,
                        activeColor: Colors.green,
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedProductIds.add(product['id']);
                            } else {
                              _selectedProductIds.remove(product['id']);
                            }
                            _updateDisplayedProducts(); // Re-sort to keep selected at top
                          });
                        },
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProducts,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

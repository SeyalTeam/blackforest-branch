import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/favorite_rule_products_page.dart';
import 'package:branch/favorite_rule_categories_page.dart';

class FavoriteRulesPage extends StatefulWidget {
  const FavoriteRulesPage({Key? key}) : super(key: key);

  @override
  _FavoriteRulesPageState createState() => _FavoriteRulesPageState();
}

class _FavoriteRulesPageState extends State<FavoriteRulesPage> {
  List<dynamic> _branchRules = [];
  List<dynamic> _categoryRules = [];
  bool _isLoading = true;
  String? _branchId;
  String? _token;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _branchId = prefs.getString('branchId');
    _token = prefs.getString('token');

    if (_branchId == null || _token == null) {
      setState(() => _isLoading = false);
      return;
    }

    _fetchRules();
  }

  Future<void> _fetchRules() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch current branch details to get company ID
      final branchRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches/$_branchId'),
        headers: ApiConfig.getHeaders(_token),
      );
      if (branchRes.statusCode == 200) {
        final branchData = json.decode(branchRes.body);
        final company = branchData['company'];
        _companyId = company is Map ? (company['id'] ?? company['_id']) : company;
      }

      // 2. Fetch all rules
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/globals/widget-settings'),
        headers: ApiConfig.getHeaders(_token),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> allRules = data['favoriteProductsByBranchRules'] ?? [];
        final List<dynamic> allCategoryRules = data['favoriteCategoriesByBranchRules'] ?? [];

        // Filter strictly by checking if any branch assigned to the rule belongs to the current company
        final filteredRules = allRules.where((rule) {
          if (_companyId == null) return false;
          
          final List<dynamic> branches = rule['branches'] as List<dynamic>? ?? [];
          return branches.any((b) {
            if (b is Map && b['company'] != null) {
              final bComp = b['company'];
              final compId = bComp is Map ? (bComp['id'] ?? bComp['_id']) : bComp;
              return compId == _companyId;
            }
            return false;
          });
        }).toList();

        final filteredCategoryRules = allCategoryRules.where((rule) {
          if (_companyId == null) return false;
          
          final List<dynamic> branches = rule['branches'] as List<dynamic>? ?? [];
          return branches.any((b) {
            if (b is Map && b['company'] != null) {
              final bComp = b['company'];
              final compId = bComp is Map ? (bComp['id'] ?? bComp['_id']) : bComp;
              return compId == _companyId;
            }
            return false;
          });
        }).toList();

        // Just map over the filtered rules
        final rulesWithState = filteredRules.toList();
        final categoryRulesWithState = filteredCategoryRules.toList();

        setState(() {
          _branchRules = rulesWithState;
          _categoryRules = categoryRulesWithState;
        });
      }
    } catch (e) {
      debugPrint('Error fetching rules: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleRule(String ruleId, bool isEnabled, int index) async {
    // Optimistic UI Update
    setState(() {
      _branchRules[index]['enabled'] = isEnabled;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/widgets/toggle-favorite-rule'),
        headers: ApiConfig.getHeaders(_token),
        body: json.encode({
          'ruleId': ruleId,
          'enabled': isEnabled,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to update rule status: ${response.statusCode} - ${response.body}');
        // Revert UI if it fails
        setState(() {
          _branchRules[index]['enabled'] = !isEnabled;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update rule status')),
        );
      }
    } catch (e) {
      debugPrint('Network error in _toggleRule: $e');
      // Revert UI on network error
      setState(() {
        _branchRules[index]['enabled'] = !isEnabled;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Try again.')),
      );
    }
  }

  Future<void> _toggleCategoryRule(String ruleId, bool isEnabled, int index) async {
    // Optimistic UI Update
    setState(() {
      _categoryRules[index]['enabled'] = isEnabled;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/widgets/toggle-favorite-category-rule'),
        headers: ApiConfig.getHeaders(_token),
        body: json.encode({
          'ruleId': ruleId,
          'enabled': isEnabled,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to update category rule status: ${response.statusCode} - ${response.body}');
        // Revert UI if it fails
        setState(() {
          _categoryRules[index]['enabled'] = !isEnabled;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update category rule status')),
        );
      }
    } catch (e) {
      debugPrint('Network error in _toggleCategoryRule: $e');
      // Revert UI on network error
      setState(() {
        _categoryRules[index]['enabled'] = !isEnabled;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'QR Controller',
      pageType: PageType.home, // Or whatever matches your navigation
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_branchId == null)
              ? const Center(child: Text('Session expired. Please log in again.'))
              : _branchRules.isEmpty && _categoryRules.isEmpty
                  ? const Center(
                      child: Text(
                        'No QR Controller rules configured for this branch.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Favorite Products',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _branchRules.length,
                            itemBuilder: (context, index) {
                              final rule = _branchRules[index];
                              final ruleName = rule['ruleName'] ?? 'Unnamed Rule';
                              final isEnabled = rule['enabled'] ?? false;
                              final ruleId = rule['id'];

                              return Card(
                                elevation: 4,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    final products = rule['products'] as List<dynamic>? ?? [];
                                    final productIds = products.map((p) {
                                      if (p is Map) return (p['id'] ?? p['_id']).toString();
                                      return p.toString();
                                    }).toList();

                                    final bool? updated = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => FavoriteRuleProductsPage(
                                          ruleId: ruleId,
                                          ruleName: ruleName,
                                          initialProducts: productIds,
                                          token: _token!,
                                          companyId: _companyId!,
                                        ),
                                      ),
                                    );
                                    if (updated == true) {
                                      _fetchRules(); // Refresh if products were updated
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            ruleName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Switch(
                                          value: isEnabled,
                                          activeColor: Colors.green,
                                          onChanged: (newValue) =>
                                              _toggleRule(ruleId, newValue, index),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_categoryRules.isNotEmpty) ...[
                            const SizedBox(height: 32),
                            const Text(
                              'Favorite Categories',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _categoryRules.length,
                              itemBuilder: (context, index) {
                                final rule = _categoryRules[index];
                                final ruleName = rule['ruleName'] ?? 'Unnamed Rule';
                                final isEnabled = rule['enabled'] ?? false;
                                final ruleId = rule['id'];

                                return Card(
                                  elevation: 4,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      final categories = rule['categories'] as List<dynamic>? ?? [];
                                      final categoryIds = categories.map((c) {
                                        if (c is Map) return (c['id'] ?? c['_id']).toString();
                                        return c.toString();
                                      }).toList();

                                      final bool? updated = await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => FavoriteRuleCategoriesPage(
                                            ruleId: ruleId,
                                            ruleName: ruleName,
                                            initialCategories: categoryIds,
                                            token: _token!,
                                            companyId: _companyId!,
                                          ),
                                        ),
                                      );
                                      if (updated == true) {
                                        _fetchRules(); // Refresh if categories were updated
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              ruleName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Switch(
                                            value: isEnabled,
                                            activeColor: Colors.green,
                                            onChanged: (newValue) =>
                                                _toggleCategoryRule(ruleId, newValue, index),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

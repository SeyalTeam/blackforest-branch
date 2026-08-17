import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final branchId = '6906dc71896efbd4bc64d028';
  String companyId = '';

  // 1. Fetch branch
  final branchRes = await http.get(Uri.parse('https://blackforest.vseyal.com/api/branches/$branchId'));
  if (branchRes.statusCode == 200) {
    final branchData = json.decode(branchRes.body);
    final company = branchData['company'];
    companyId = company is Map ? (company['id'] ?? company['_id']) : company;
    print('Current Branch Company ID: $companyId');
  }

  final response = await http.get(Uri.parse('https://blackforest.vseyal.com/api/globals/widget-settings'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final allRules = data['favoriteProductsByBranchRules'] ?? [];
    
    final filteredRules = allRules.where((rule) {
      if (companyId.isEmpty) return false;

      // 1. Check branches
      final List<dynamic> branches = rule['branches'] as List<dynamic>? ?? [];
      bool hasMatchingBranch = branches.any((b) {
        if (b is Map && b['company'] != null) {
          final bComp = b['company'];
          final compId = bComp is Map ? (bComp['id'] ?? bComp['_id']) : bComp;
          if (compId == companyId) return true;
        }
        return false;
      });
      if (hasMatchingBranch) return true;

      // 2. Check rule.category
      final List<dynamic> categories = rule['category'] as List<dynamic>? ?? [];
      bool hasMatchingCategory = categories.any((c) {
        if (c is Map && c['company'] != null) {
          final companies = c['company'] as List<dynamic>? ?? [];
          return companies.any((comp) {
            final compId = comp is Map ? (comp['id'] ?? comp['_id']) : comp;
            return compId == companyId;
          });
        }
        return false;
      });
      if (hasMatchingCategory) return true;

      // 3. Check rule.products
      final List<dynamic> products = rule['products'] as List<dynamic>? ?? [];
      bool hasMatchingProduct = products.any((p) {
        if (p is Map && p['category'] is Map) {
          final cat = p['category'];
          final companies = cat['company'] as List<dynamic>? ?? [];
          return companies.any((c) {
            final compId = c is Map ? (c['id'] ?? c['_id']) : c;
            return compId == companyId;
          });
        }
        return false;
      });
      if (hasMatchingProduct) return true;

      return false;
    }).toList();

    print('Total matched rules for company: ${filteredRules.length}');
    for (var rule in filteredRules) {
        print(' - ${rule['ruleName']}');
    }
  }
}

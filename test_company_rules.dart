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
  } else {
    print('Failed to get branch');
    return;
  }

  final response = await http.get(Uri.parse('https://blackforest.vseyal.com/api/globals/widget-settings'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final allRules = data['favoriteProductsByBranchRules'] ?? [];
    
    final filteredRules = allRules.where((rule) {
      final branches = rule['branches'] as List? ?? [];
      return branches.any((b) {
        if (b is Map && b['company'] != null) {
          final bComp = b['company'];
          final compId = bComp is Map ? (bComp['id'] ?? bComp['_id']) : bComp;
          if (compId == companyId) return true;
        }
        return false;
      });
    }).toList();

    print('Total matched rules for company: ${filteredRules.length}');
  }
}

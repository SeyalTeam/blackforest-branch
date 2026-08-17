import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final branchId = '6906dc71896efbd4bc64d028';
  final response = await http.get(Uri.parse('https://blackforest.vseyal.com/api/globals/widget-settings'));
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final allRules = data['favoriteProductsByBranchRules'] ?? [];
    print('Total rules: ${allRules.length}');
    
    for (var rule in allRules) {
      final branches = rule['branches'] ?? [];
      bool matched = false;
      for (var b in branches) {
        final bId = (b is String) ? b : (b['id']?.toString() ?? b['_id']?.toString() ?? '');
        if (bId == branchId) matched = true;
      }
      print('Rule "${rule['ruleName']}" - Branches count: ${branches.length} - Matched for $branchId: $matched');
    }
  } else {
    print('Failed: ${response.statusCode}');
  }
}

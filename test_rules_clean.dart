import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(Uri.parse('https://blackforest.vseyal.com/api/globals/widget-settings'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final allRules = data['favoriteProductsByBranchRules'] ?? [];
    if (allRules.isNotEmpty) {
      final rule = allRules.first;
      print('Keys: ' + rule.keys.toList().toString());
      print('ruleName: ' + rule['ruleName'].toString());
      print('enabled: ' + rule['enabled'].toString());
      print('isActive: ' + rule['isActive'].toString());
      print('status: ' + rule['status'].toString());
    }
  }
}

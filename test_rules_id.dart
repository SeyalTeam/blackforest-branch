import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(Uri.parse('https://blackforest.vseyal.com/api/globals/widget-settings'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final allRules = data['favoriteProductsByBranchRules'] ?? [];
    print('Products Rules:');
    for (var rule in allRules) {
      print('id: ' + rule['id'].toString() + ', _id: ' + rule['_id'].toString() + ', name: ' + rule['ruleName'].toString());
    }
    final allCategoryRules = data['favoriteCategoriesByBranchRules'] ?? [];
    print('Category Rules:');
    for (var rule in allCategoryRules) {
      print('id: ' + rule['id'].toString() + ', _id: ' + rule['_id'].toString() + ', name: ' + rule['ruleName'].toString());
    }
  }
}

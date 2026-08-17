import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(Uri.parse('https://blackforest.vseyal.com/api/globals/widget-settings'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final allRules = data['favoriteProductsByBranchRules'] ?? [];
    if (allRules.isNotEmpty) {
      print(json.encode(allRules.first));
    }
  }
}

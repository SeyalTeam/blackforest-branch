import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class StockAlertHelper {
  static String _extractRefId(dynamic value) {
    if (value is Map) {
      return (value['id'] ?? value['_id'] ?? value[r'$oid'] ?? '')
          .toString()
          .trim();
    }
    return value?.toString().trim() ?? '';
  }

  static List<String> _extractBranchIds(dynamic value) {
    if (value is! List) return <String>[];

    final ids = <String>[];
    for (final entry in value) {
      final id = _extractRefId(entry);
      if (id.isNotEmpty && !ids.contains(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  static Future<List<Map<String, dynamic>>> fetchOpenAlerts({
    required String token,
    required String branchId,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${ApiConfig.baseUrl}/stock-alerts?limit=20&depth=1&sort=-createdAt&where[branch][equals]=$branchId&where[status][equals]=open',
      ),
      headers: ApiConfig.getHeaders(token),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch alerts (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final docs = (data['docs'] as List?) ?? const [];

    return docs
        .whereType<Map>()
        .map((doc) => Map<String, dynamic>.from(doc))
        .toList();
  }

  static Future<void> acknowledgeAlert({
    required String token,
    required String alertId,
  }) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/stock-alerts/$alertId'),
      headers: ApiConfig.getHeaders(token),
      body: jsonEncode({
        'status': 'acknowledged',
        'acknowledgedAt': DateTime.now().toIso8601String(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to acknowledge alert (${response.statusCode})');
    }
  }

  static String productId(Map<String, dynamic> alert) {
    return _extractRefId(alert['product']);
  }

  static Future<void> markProductOutOfStock({
    required String token,
    required String branchId,
    required Map<String, dynamic> alert,
  }) async {
    final productIdValue = productId(alert);
    if (productIdValue.isEmpty) {
      throw Exception('Product not found for this alert.');
    }

    final productResponse = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/products/$productIdValue?depth=0'),
      headers: ApiConfig.getHeaders(token),
    );

    if (productResponse.statusCode != 200) {
      throw Exception(
        'Failed to load product before stock update (${productResponse.statusCode})',
      );
    }

    final product = jsonDecode(productResponse.body) as Map<String, dynamic>;
    final outOfStockBranches = _extractBranchIds(product['outOfStockBranches']);
    if (!outOfStockBranches.contains(branchId)) {
      outOfStockBranches.add(branchId);
    }

    final updateResponse = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/products/$productIdValue'),
      headers: ApiConfig.getHeaders(token),
      body: jsonEncode({'outOfStockBranches': outOfStockBranches}),
    );

    if (updateResponse.statusCode != 200 && updateResponse.statusCode != 202) {
      throw Exception(
        'Failed to mark product out of stock (${updateResponse.statusCode})',
      );
    }

    final verifyResponse = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/products/$productIdValue?depth=0'),
      headers: ApiConfig.getHeaders(token),
    );

    if (verifyResponse.statusCode != 200) {
      throw Exception(
        'Failed to verify product stock update (${verifyResponse.statusCode})',
      );
    }

    final saved = jsonDecode(verifyResponse.body) as Map<String, dynamic>;
    final savedBranches = _extractBranchIds(saved['outOfStockBranches']);
    if (!savedBranches.contains(branchId)) {
      throw Exception('Product stock update was not saved for this branch.');
    }
  }

  static String productName(Map<String, dynamic> alert) {
    final product = alert['product'];
    if (product is Map && product['name'] != null) {
      return product['name'].toString();
    }
    return (alert['productName'] ?? 'Product').toString();
  }

  static String requesterName(Map<String, dynamic> alert) {
    final requestedBy = alert['requestedBy'];
    if (requestedBy is Map && requestedBy['name'] != null) {
      return requestedBy['name'].toString();
    }
    return (alert['requestedByName'] ?? 'Kitchen').toString();
  }
}

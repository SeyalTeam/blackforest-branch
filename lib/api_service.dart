import 'dart:convert';

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Singleton Pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  static ApiService get instance => _instance;

  static const String _baseUrl = 'https://dev1-blacforest.vseyal.com/api';
  static String get baseUrl => _baseUrl;
  static const storage = FlutterSecureStorage();

  // Cache Storage
  List<dynamic>? _cachedDepartments;
  List<dynamic>? _cachedBranches;
  final Map<String, List<dynamic>> _cachedCategories =
      {}; // Key: "onlyStock_deptId"
  final Map<String, List<dynamic>> _cachedStockOrders = {}; // Key: "start_end"

  void clearCache() {
    _cachedDepartments = null;
    _cachedBranches = null;
    _cachedCategories.clear();
    _cachedStockOrders.clear();
  }

  Future<String?> _getToken() async {
    final s = await storage.read(key: 'token');
    if (s != null && s.isNotEmpty) return s;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<List<dynamic>> fetchDepartments({bool forceRefresh = false}) async {
    if (_cachedDepartments != null && !forceRefresh) {
      return _cachedDepartments!;
    }

    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/departments?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _cachedDepartments = (data['docs'] as List?) ?? [];
        return _cachedDepartments!;
      } else {
        throw Exception('Failed to load departments');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchUserProfile() async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/users/me';
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        debugPrint('DEBUG: fetchUserProfile success. Data: ${res.body}');
        return data['user'] ?? {};
      } else {
        throw Exception('Failed to fetch user profile');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchCategories({
    bool onlyStock = false,
    String? departmentId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${onlyStock}_${departmentId ?? "ALL"}';
    if (_cachedCategories.containsKey(cacheKey) && !forceRefresh) {
      return _cachedCategories[cacheKey]!;
    }

    try {
      final token = await _getToken();
      // Added depth=1 to ensure department is populated in the response
      String url = '$_baseUrl/categories?limit=1000&depth=1';
      if (onlyStock) {
        url += '&where[isStock][equals]=true';
      }
      if (departmentId != null) {
        url += '&where[department][equals]=$departmentId';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['docs'] as List?) ?? [];
        _cachedCategories[cacheKey] = list;
        return list;
      } else {
        throw Exception('Failed to load categories');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchStockOrders({
    required DateTime fromDate,
    DateTime? toDate,
    String filterBy = 'deliveryDate',
    bool forceRefresh = false,
  }) async {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = toDate != null
        ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
        : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);

    final cacheKey =
        '${filterBy}_${start.toIso8601String()}_${end.toIso8601String()}';

    if (_cachedStockOrders.containsKey(cacheKey) && !forceRefresh) {
      return _cachedStockOrders[cacheKey]!;
    }

    try {
      final token = await _getToken();

      // Using deliveryDate as per recent requirement changes
      final url =
          '$_baseUrl/stock-orders?limit=1000&depth=2'
          '&where[$filterBy][greater_than]=${start.toUtc().toIso8601String()}'
          '&where[$filterBy][less_than]=${end.toUtc().toIso8601String()}';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['docs'] as List?) ?? [];
        _cachedStockOrders[cacheKey] = list;
        return list;
      } else {
        throw Exception('Failed to load stock orders');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchBranches({bool forceRefresh = false}) async {
    if (_cachedBranches != null && !forceRefresh) {
      return _cachedBranches!;
    }

    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/branches?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _cachedBranches = (data['docs'] as List?) ?? [];
        return _cachedBranches!;
      } else {
        throw Exception('Failed to load branches');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchBranchGeoSettings() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/globals/branch-geo-settings'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load branch geo settings: ${res.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchBranchBillingReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      String url = '$_baseUrl/reports/branch-billing';
      
      List<String> queryParams = [];
      if (startDate != null) queryParams.add('startDate=$startDate');
      if (endDate != null) queryParams.add('endDate=$endDate');
      
      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to fetch billing report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching branch billing report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchClosingEntryReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/closing-entry';
      url += '?startDate=$startStr&endDate=$endStr';

      debugPrint('Fetching closing entry report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load closing entry report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching closing entry report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchAttendanceReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/attendance';
      url += '?startDate=$startStr&endDate=$endStr';

      debugPrint('Fetching attendance report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load attendance report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching attendance report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchDealerReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/dealer';
      url += '?startDate=$startStr&endDate=$endStr';

      debugPrint('Fetching dealer report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load dealer report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching dealer report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchStockOrderReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/stock-order';
      url += '?startDate=$startStr&endDate=$endStr';

      debugPrint('Fetching stock order report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load stock order report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching stock order report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchExpenseReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/expense';
      url += '?startDate=$startStr&endDate=$endStr';

      debugPrint('Fetching expense report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load expense report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching expense report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchReturnOrderReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/return-order';
      url += '?startDate=$startStr&endDate=$endStr';

      debugPrint('Fetching return order report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load return order report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching return order report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchProductTimeReport({
    String? startDate,
    String? endDate,
    required String branchId,
  }) async {
    try {
      final token = await _getToken();
      Map<String, String> headers = {};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final now = DateTime.now();
      final startStr = startDate ?? DateFormat('yyyy-MM-dd').format(now);
      final endStr = endDate ?? DateFormat('yyyy-MM-dd').format(now);

      String url = '$_baseUrl/reports/product-preparation-bill-details';
      url += '?startDate=$startStr&endDate=$endStr&branch=$branchId';

      debugPrint('Fetching product time report from: $url');
      final res = await http.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) {
        return json.decode(res.body);
      } else {
        throw Exception('Failed to load product time report: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching product time report: $e');
      rethrow;
    }
  }

Future<List<dynamic>> fetchManagerClosingReplies({
    required String branchId,
    required String dateStr,
  }) async {
    try {
      final token = await _getToken();
      // Date format is yyyy-MM-dd. We can search exactly this date if we stored it as 'dayOnly' in Payload.
      // Payload stores dayOnly dates as strings like "2026-09-18T00:00:00.000Z".
      // We can use a like or contains, or just fetch all for the branch and filter locally, but it's better to filter by branch and date.
      // Actually, since there won't be many replies for a branch, we can just fetch by branch and sort by date descending, or limit by date prefix.
      final url = '$_baseUrl/manager-closing-replies?where[branch][equals]=$branchId&limit=50';
      
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['docs'] as List<dynamic>? ?? [];
        // Filter locally by date just to be safe
        return docs.where((doc) {
          final docDate = doc['date']?.toString() ?? '';
          return docDate.startsWith(dateStr);
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching replies: $e');
      return [];
    }
  }

  Future<void> updateBranchCashDrawerAccess(String branchId, bool isEnabled) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/branches/$branchId';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'isCashDrawerEnabled': isEnabled}),
      );
      if (res.statusCode != 200) {
        throw Exception('Failed to update cash drawer access. Status: ${res.statusCode}');
      }
    } catch (e) {
      print('Error updating cash drawer access: $e');
      rethrow;
    }
  }


  Future<void> updateBranchClosingAccess(String branchId, bool isEnabled) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/branches/$branchId';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'isClosingEntryEnabled': isEnabled}),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update branch access: ${res.statusCode}');
      }
      
      // Clear branch cache so UI updates next time it fetches branches
      _cachedBranches = null;
    } catch (e) {
      debugPrint('Error updating branch access: $e');
      rethrow;
    }
  }

Future<List<dynamic>> fetchEmployees() async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/employees?limit=2000&where[status][equals]=active';
      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['docs'] ?? [];
      } else {
        throw Exception('Failed to load employees: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      rethrow;
    }
  }

  Future<void> updateEmployeeRole(String id, String role) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/employees/$id';
      final res = await http.patch(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'team': role}),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update employee role: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating employee role: $e');
      rethrow;
    }
  }

  Future<void> submitManagerClosingReply (Map<String, dynamic> body) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/manager-closing-replies';
      
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );
      
      if (res.statusCode != 201 && res.statusCode != 200) {
        throw Exception('Failed to submit reply: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('Error submitting manager closing reply: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchBranchBills({
    required String branchId,
    required DateTime date,
    int page = 1,
  }) async {
    try {
      final token = await _getToken();
      
      final startOfDay = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toUtc().toIso8601String();
      
      final url = '$_baseUrl/billings?'
          'where[branch][equals]=$branchId&'
          'where[createdAt][greater_than_equal]=$startOfDay&'
          'where[createdAt][less_than_equal]=$endOfDay&'
          'limit=100&'
          'depth=1&'
          'page=$page&'
          'sort=-createdAt';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return {
          'docs': data['docs'] ?? [],
          'hasNextPage': data['hasNextPage'] ?? false,
        };
      } else {
        debugPrint('Bills API Error: ${res.statusCode} ${res.body}');
        throw Exception('Failed to fetch bills: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching bills: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> fetchReviews({
    DateTime? date, 
    String? branchId,
    List<String>? companyIds,
  }) async {
    try {
      final token = await _getToken();

      String url = '$_baseUrl/reviews?limit=100&depth=1&sort=-createdAt';

      if (branchId != null && branchId.isNotEmpty && branchId != 'ALL') {
        url += '&where[branch][equals]=$branchId';
      } else if (companyIds != null && companyIds.isNotEmpty) {
        // Payload doesn't support deep relationship filtering natively in REST without joins,
        // so we first fetch all branches and filter them by company locally.
        final allBranches = await fetchBranches();
        final validBranchIds = <String>[];
        for (var b in allBranches) {
          final c = b['company'];
          final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
          if (companyIds.contains(cId)) {
            final bId = (b['id'] ?? b['_id'])?.toString();
            if (bId != null) validBranchIds.add(bId);
          }
        }
        if (validBranchIds.isNotEmpty) {
          url += '&where[branch][in]=${validBranchIds.join(',')}';
        } else {
          // If manager has companies but no branches exist for those companies,
          // return empty by querying a non-existent branch
          url += '&where[branch][equals]=NONE';
        }
      }

      if (date != null) {
        final start = DateTime(
          date.year,
          date.month,
          date.day,
        ).toUtc().toIso8601String();
        final end = DateTime(
          date.year,
          date.month,
          date.day,
          23,
          59,
          59,
        ).toUtc().toIso8601String();
        url +=
            '&where[createdAt][greater_than]=$start&where[createdAt][less_than]=$end';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception(
          'Failed to load reviews: ${res.statusCode} ${res.body}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> replyToReview(
    String reviewId,
    String itemId,
    String replyText,
  ) async {
    try {
      final token = await _getToken();

      // 1. Fetch the specific review first to get current structure
      final getRes = await http.get(
        Uri.parse('$_baseUrl/reviews/$reviewId'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (getRes.statusCode != 200) {
        throw Exception('Failed to fetch review for update');
      }

      final reviewData = jsonDecode(getRes.body);
      final items = (reviewData['items'] as List?) ?? [];

      // 2. Find and update the specific item
      bool found = false;
      final updatedItems = items.map((item) {
        final currentId = item['id'] ?? item['_id'];
        if (currentId == itemId) {
          found = true;
          return {
            ...item,
            'chefReply': replyText,
            // 'status': 'replied' // Let backend hook handle status
          };
        }
        return item;
      }).toList();

      if (!found) {
        throw Exception('Review item not found');
      }

      // 3. Patch the review with updated items array
      final patchRes = await http.patch(
        Uri.parse('$_baseUrl/reviews/$reviewId'),
        headers: token != null
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'items': updatedItems}),
      );

      if (patchRes.statusCode != 200) {
        throw Exception('Failed to submit reply: ${patchRes.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchKitchenDetails(String kitchenId) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/kitchens/$kitchenId';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        throw Exception('Failed to load kitchen details');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchKitchens() async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/kitchens?limit=1000';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load kitchens');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchProducts({List<String>? categoryIds}) async {
    try {
      final token = await _getToken();
      String url = '$_baseUrl/products?limit=1000&depth=1';

      if (categoryIds != null && categoryIds.isNotEmpty) {
        for (int i = 0; i < categoryIds.length; i++) {
          url += '&where[category][in][$i]=${categoryIds[i]}';
        }
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load products');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchProductsByIds(
    List<String> productIds, {
    int depth = 1,
  }) async {
    final ids = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];

    try {
      final token = await _getToken();
      String url = '$_baseUrl/products?limit=${ids.length}&depth=$depth';
      for (int i = 0; i < ids.length; i++) {
        url += '&where[id][in][$i]=${Uri.encodeQueryComponent(ids[i])}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load products by ids');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchProductById(String productId) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/products/$productId?depth=0';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      } else {
        throw Exception('Failed to load product details');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchMediaById(String mediaId) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/media/$mediaId';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      } else {
        throw Exception('Failed to load media details');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchMediaByIds(List<String> mediaIds) async {
    final ids = mediaIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];

    try {
      final token = await _getToken();
      String url = '$_baseUrl/media?limit=${ids.length}';
      for (int i = 0; i < ids.length; i++) {
        url += '&where[id][in][$i]=${Uri.encodeQueryComponent(ids[i])}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load media by ids');
      }
    } catch (e) {
      rethrow;
    }
  }

  bool? _readIsOutOfStock(Map<String, dynamic> product) {
    final isStock = product['isStock'];
    if (isStock is bool) {
      return !isStock;
    }

    final isOutOfStock = product['isOutOfStock'];
    if (isOutOfStock is bool) {
      return isOutOfStock;
    }

    return null;
  }

  Future<bool> updateProductStockStatus(
    String productId,
    bool isOutOfStock,
  ) async {
    try {
      final token = await _getToken();
      final url = '$_baseUrl/products/$productId';

      final res = await http.patch(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'isStock': !isOutOfStock,
          'isOutOfStock': isOutOfStock,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to update product status: ${res.body}');
      }

      final refreshedProduct = await fetchProductById(productId);
      final savedValue = _readIsOutOfStock(refreshedProduct);
      final savedIsStock = refreshedProduct['isStock'];

      if (savedValue is! bool ||
          savedValue != isOutOfStock ||
          savedIsStock is! bool ||
          savedIsStock != !isOutOfStock) {
        throw Exception('Stock status was not saved. Please try again.');
      }

      return savedValue;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createStockAlert({
    required String productId,
    required String branchId,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/stock-alerts'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'product': productId, 'branch': branchId}),
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Failed to create stock alert: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchKitchenKOTs({
    required String branchId,
    required String kitchenId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final token = await _getToken();

      String url =
          '$_baseUrl/billings?limit=100&depth=3'
          '&where[branch][equals]=$branchId'
          '&where[status][in][0]=ordered'
          '&where[status][in][1]=confirmed'
          '&where[status][in][2]=prepared'
          '&where[status][in][3]=served'
          '&where[status][in][4]=delivered'
          '&sort=-createdAt';

      if (fromDate != null) {
        final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
        url +=
            '&where[createdAt][greater_than]=${start.toUtc().toIso8601String()}';

        final end = toDate != null
            ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
            : DateTime(fromDate.year, fromDate.month, fromDate.day, 23, 59, 59);
        url += '&where[createdAt][less_than]=${end.toUtc().toIso8601String()}';
      }

      debugPrint('DEBUG: Calling fetchKitchenKOTs with URL: $url');

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      debugPrint('DEBUG: fetchKitchenKOTs response status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['docs'] as List?) ?? [];
        debugPrint('DEBUG: fetchKitchenKOTs parsed ${list.length} docs');
        return list;
      } else {
        debugPrint('DEBUG: fetchKitchenKOTs failed: ${res.body}');
        throw Exception('Failed to load kitchen orders');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBillingItemStatus({
    required String billingId,
    required String itemId,
    String? status,
    int? preparingTime,
    int? preparationTime,
    String? actorUserId,
  }) async {
    try {
      final normalizedStatus = status?.trim();
      if (preparingTime != null && preparingTime < 0) {
        throw Exception('preparingTime must be a whole number >= 0');
      }
      if (preparationTime != null && preparationTime < 0) {
        throw Exception('preparationTime must be a whole number >= 0');
      }

      final payload = <String, dynamic>{'itemId': itemId};
      if (normalizedStatus != null && normalizedStatus.isNotEmpty) {
        payload['status'] = normalizedStatus;
        payload['kitchenStatus'] = normalizedStatus;
      }
      if (preparingTime != null) {
        payload['preparingTime'] = preparingTime;
      } else if (preparationTime != null) {
        payload['preparationTime'] = preparationTime;
      }

      // Send actorUserId so backend can record who performed the action
      if (actorUserId != null && actorUserId.isNotEmpty) {
        payload['actorUserId'] = actorUserId;
      }

      if (!payload.containsKey('status') &&
          !payload.containsKey('preparingTime') &&
          !payload.containsKey('preparationTime')) {
        throw Exception(
          'Either status or preparingTime/preparationTime must be provided',
        );
      }

      final token = await _getToken();
      final url = '$_baseUrl/billings/$billingId/items/status';

      final res = await http.patch(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        debugPrint(
          'DEBUG: updateBillingItemStatus failed. Status: ${res.statusCode}, Body: ${res.body}',
        );
        throw Exception('Failed to update item status: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchBillingItemPreparationTime({
    required String billingId,
    required String itemId,
  }) async {
    try {
      final token = await _getToken();
      final url =
          '$_baseUrl/billings/$billingId/items/preparation-time?itemId=$itemId';

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return null;
      }

      if (res.statusCode == 404 || res.statusCode == 204) {
        return null;
      }

      throw Exception('Failed to load preparation time: ${res.body}');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchBillings({
    String? status,
    DateTime? fromDate,
    String? createdBy,
    String? branchId,
    int depth = 1,
    int limit = 100,
  }) async {
    try {
      final token = await _getToken();
      String url =
          '$_baseUrl/billings?limit=$limit&depth=$depth&sort=-createdAt';

      if (status != null) {
        url += '&where[status][equals]=$status';
      }
      if (branchId != null) {
        url += '&where[branch][equals]=$branchId';
      }
      if (createdBy != null) {
        url += '&where[createdBy][equals]=$createdBy';
      }
      if (fromDate != null) {
        final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
        url +=
            '&where[createdAt][greater_than_equal]=${start.toUtc().toIso8601String()}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load billings');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchCompanies() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/companies?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load companies');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialCategories() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-categories?limit=1000'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material categories');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterialCategory({
    required String name,
    required List<String> companyIds,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/raw-material-categories'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'company': companyIds,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material category: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterial({
    required String name,
    required String categoryId,
    required String unit,
    double? minimumStockLevel,
    String? dealerId,
    List<String>? images,
  }) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/raw-materials'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'category': categoryId,
          'unit': unit,
          if (minimumStockLevel != null) 'minimumStockLevel': minimumStockLevel,
          if (dealerId != null) 'dealer': dealerId,
          if (images != null && images.isNotEmpty)
            'images': images.map((id) => {'image': id}).toList(),
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterials({int depth = 2}) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-materials?limit=1000&depth=$depth'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw materials');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchDealers() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/dealers?limit=1000&depth=1'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load dealers');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createDealer({
    required String companyName,
    required String address,
    required String phoneNumber,
    required String email,
    required String contactName,
    required List<String> allowedCompanies,
    String? gst,
    String? pan,
  }) async {
    try {
      final token = await _getToken();
      final bodyMap = {
        'companyName': companyName,
        'address': address,
        'phoneNumber': phoneNumber,
        'email': email,
        'contactPerson': {
          'name': contactName,
        },
        'allowedCompanies': allowedCompanies,
        'isGSTRegistered': gst != null && gst.isNotEmpty,
        if (gst != null && gst.isNotEmpty) 'gst': gst,
        if (pan != null && pan.isNotEmpty) 'pan': pan,
        'status': 'active',
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/dealers'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyMap),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create dealer: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialDealers() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-dealers?limit=1000&depth=1'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material dealers');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterialDealer({
    required String companyName,
    required String address,
    required String phoneNumber,
    required String email,
    required String contactName,
    required List<String> allowedCompanies,
    required bool isGSTRegistered,
    String? gst,
    String? pan,
    String? fssai,
    String? aadhar,
    String? contactDesignation,
    String? contactPhone,
    String? contactEmail,
    String? notes,
    required bool hasBankAccount,
    String? preferredPaymentMethod,
    String? bankName,
    String? accountNumber,
    String? ifscCode,
    String? bankBranch,
  }) async {
    try {
      final token = await _getToken();
      final bodyMap = {
        'companyName': companyName,
        'address': address,
        'phoneNumber': phoneNumber,
        'email': email,
        'contactPerson': {
          'name': contactName,
          if (contactDesignation != null && contactDesignation.isNotEmpty) 'designation': contactDesignation,
          if (contactPhone != null && contactPhone.isNotEmpty) 'phone': contactPhone,
          if (contactEmail != null && contactEmail.isNotEmpty) 'email': contactEmail,
        },
        'allowedCompanies': allowedCompanies,
        'isGSTRegistered': isGSTRegistered,
        if (isGSTRegistered && gst != null && gst.isNotEmpty) 'gst': gst,
        if (isGSTRegistered && pan != null && pan.isNotEmpty) 'pan': pan,
        if (isGSTRegistered && fssai != null && fssai.isNotEmpty) 'fssai': fssai,
        if (!isGSTRegistered && aadhar != null && aadhar.isNotEmpty) 'aadhar': aadhar,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'status': 'active',
        'hasBankAccount': hasBankAccount,
        if (!hasBankAccount && preferredPaymentMethod != null)
          'preferredPaymentMethod': preferredPaymentMethod,
        if (hasBankAccount)
          'bankDetails': {
            if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
            if (accountNumber != null && accountNumber.isNotEmpty) 'accountNumber': accountNumber,
            if (ifscCode != null && ifscCode.isNotEmpty) 'ifscCode': ifscCode,
            if (bankBranch != null && bankBranch.isNotEmpty) 'branch': bankBranch,
          },
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/raw-material-dealers'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyMap),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material dealer: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialBillings() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-billings?limit=1000&depth=2&sort=-date'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material billings');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createStockOrder(Map<String, dynamic> payload) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/stock-orders'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create stock order: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterialBilling(Map<String, dynamic> payload) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/raw-material-billings'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material billing: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRawMaterialInstockEntry(Map<String, dynamic> payload) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/raw-material-instock-entries'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create raw material instock entry: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchRawMaterialInstockEntries({int limit = 100, int depth = 2}) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/raw-material-instock-entries?limit=$limit&depth=$depth&sort=-date'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load raw material instock entries: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createProductionRequest(Map<String, dynamic> payload) async {
    try {
      final token = await _getToken();
      final res = await http.post(
        Uri.parse('$_baseUrl/production-requests'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create production request: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createDealerOrder(Map<String, dynamic> payload) async {
    try {
      final token = await _getToken();
      
      // Inject current company
      final currentCompanyId = await storage.read(key: 'userCompanyId');
      if (currentCompanyId != null && !payload.containsKey('company')) {
        payload['company'] = currentCompanyId;
      }
      
      final res = await http.post(
        Uri.parse('$_baseUrl/dealer-orders'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create dealer order: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchDealerOrders({int limit = 100}) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/dealer-orders?limit=$limit&sort=-createdAt'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['docs'] as List<dynamic>;
      } else {
        throw Exception('Failed to fetch dealer orders');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> fetchProductionRequests() async {
    try {
      final token = await _getToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/production-requests?limit=1000&sort=-date'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['docs'] as List?) ?? [];
      } else {
        throw Exception('Failed to load production requests');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProductionRequest(String id, Map<String, dynamic> payload) async {
    try {
      final token = await _getToken();
      final res = await http.patch(
        Uri.parse('$_baseUrl/production-requests/$id'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Failed to update production request: ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CCTV Report Methods (Watcher Role)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch all CCTV reports visible to the logged-in watcher.
  Future<List<Map<String, dynamic>>> fetchCctvReports({
    int limit = 50,
  }) async {
    try {
      final token = await _getToken();
      final uri = Uri.parse(
        '$_baseUrl/cctv-reports?limit=$limit&depth=1&sort=-createdAt',
      );
      final res = await http.get(
        uri,
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return ((data['docs'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
      } else {
        debugPrint('fetchCctvReports: ${res.statusCode} ${res.body}');
        return [];
      }
    } catch (e) {
      debugPrint('fetchCctvReports error: $e');
      return [];
    }
  }

  /// Create a new CCTV report with a screenshot uploaded as multipart/form-data.
  Future<void> createCctvReport({
    required File screenshotFile,
    required String branchId,
    required String message,
    required String status,
  }) async {
    final token = await _getToken();

    // 1. Upload screenshot to media collection
    final mediaUri = Uri.parse('$_baseUrl/media');
    final mediaReq = http.MultipartRequest('POST', mediaUri);
    if (token != null) mediaReq.headers['Authorization'] = 'Bearer $token';

    final mimeType = _guessMimeType(screenshotFile.path);
    mediaReq.files.add(
      await http.MultipartFile.fromPath(
        'file',
        screenshotFile.path,
        contentType: http_parser.MediaType.parse(mimeType),
      ),
    );

    final mediaStreamed = await mediaReq.send();
    final mediaRes = await http.Response.fromStream(mediaStreamed);
    
    if (mediaRes.statusCode != 200 && mediaRes.statusCode != 201) {
      throw Exception('Failed to upload screenshot to media (${mediaRes.statusCode}): ${mediaRes.body}');
    }

    final mediaData = jsonDecode(mediaRes.body);
    final mediaId = mediaData['doc'] != null ? mediaData['doc']['id'] : mediaData['id'];

    // 2. Create the CCTV report with the uploaded media ID
    final reportUri = Uri.parse('$_baseUrl/cctv-reports');
    final reportRes = await http.post(
      reportUri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'branch': branchId,
        'message': message,
        'status': status,
        'screenshot': mediaId,
      }),
    );

    if (reportRes.statusCode != 200 && reportRes.statusCode != 201) {
      throw Exception('createCctvReport failed (${reportRes.statusCode}): ${reportRes.body}');
    }
  }

  /// PATCH status on an existing CCTV report.
  Future<void> updateCctvReportStatus(String id, String status) async {
    try {
      final token = await _getToken();
      final res = await http.patch(
        Uri.parse('$_baseUrl/cctv-reports/$id'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('updateCctvReportStatus failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }


  /// Fetch a single CCTV report by ID with full depth
  Future<Map<String, dynamic>?> fetchCctvReportById(String id) async {
    try {
      final token = await _getToken();
      final uri = Uri.parse('$_baseUrl/cctv-reports/$id?depth=2');
      final res = await http.get(
        uri,
        headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['doc'] ?? data) as Map<String, dynamic>;
      } else {
        debugPrint('fetchCctvReportById: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('fetchCctvReportById error: $e');
    }
    return null;
  }
  /// Watcher reply to a CCTV report (after manager reply)
  Future<Map<String, dynamic>> submitWatcherReplyToCctvReport({
    required String id,
    required String watcherReplyMessage,
    File? watcherReplyScreenshot,
  }) async {
    final token = await _getToken();

    String? mediaId;
    Map<String, dynamic>? mediaDoc;
    if (watcherReplyScreenshot != null) {
      final mediaUri = Uri.parse('$_baseUrl/media');
      final mediaReq = http.MultipartRequest('POST', mediaUri);
      if (token != null) mediaReq.headers['Authorization'] = 'Bearer $token';

      final mimeType = _guessMimeType(watcherReplyScreenshot.path);
      mediaReq.files.add(
        await http.MultipartFile.fromPath(
          'file',
          watcherReplyScreenshot.path,
          contentType: http_parser.MediaType.parse(mimeType),
        ),
      );

      final mediaStream = await mediaReq.send();
      final mediaRes = await http.Response.fromStream(mediaStream);
      if (mediaRes.statusCode != 200 && mediaRes.statusCode != 201) {
        throw Exception('Failed to upload watcher screenshot (${mediaRes.statusCode}): ${mediaRes.body}');
      }
      final mediaData = jsonDecode(mediaRes.body);
      mediaDoc = (mediaData['doc'] ?? mediaData) as Map<String, dynamic>;
      mediaId = mediaDoc['id']?.toString() ?? mediaData['id']?.toString();
    }

    final bodyData = <String, dynamic>{
      'watcherReplyMessage': watcherReplyMessage,
      'status': 'watcher_replied',
    };
    if (mediaId != null) {
      bodyData['watcherReplyScreenshot'] = mediaId;
    }

    final res = await http.patch(
      Uri.parse('$_baseUrl/cctv-reports/$id?depth=2'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(bodyData),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final Map<String, dynamic> doc = Map<String, dynamic>.from((data['doc'] ?? data) as Map);
      if (mediaDoc != null) {
        if (doc['watcherReplyScreenshot'] == null || doc['watcherReplyScreenshot'] is String) {
          doc['watcherReplyScreenshot'] = mediaDoc;
        }
      }
      return doc;
    } else {
      throw Exception('Failed to send watcher reply (${res.statusCode}): ${res.body}');
    }
  }

  /// Manager reply to a CCTV report with optional proof photo
  Future<Map<String, dynamic>> replyToCctvReport({
    required String id,
    required String managerMessage,
    File? proofPhoto,
  }) async {
    try {
      final token = await _getToken();

      String? mediaId;
      Map<String, dynamic>? mediaDoc;

      if (proofPhoto != null) {
        final mediaUri = Uri.parse('$_baseUrl/media');
        final mediaReq = http.MultipartRequest('POST', mediaUri);
        if (token != null) mediaReq.headers['Authorization'] = 'Bearer $token';

        final mimeType = _guessMimeType(proofPhoto.path);
        mediaReq.files.add(
          await http.MultipartFile.fromPath(
            'file',
            proofPhoto.path,
            contentType: http_parser.MediaType.parse(mimeType),
          ),
        );

        final mediaStream = await mediaReq.send();
        final mediaRes = await http.Response.fromStream(mediaStream);
        if (mediaRes.statusCode != 200 && mediaRes.statusCode != 201) {
          throw Exception('Failed to upload proof photo (${mediaRes.statusCode}): ${mediaRes.body}');
        }

        final mediaData = jsonDecode(mediaRes.body);
        mediaDoc = (mediaData['doc'] ?? mediaData) as Map<String, dynamic>;
        mediaId = mediaDoc['id']?.toString() ?? mediaData['id']?.toString();
      }

      final bodyData = <String, dynamic>{
        'managerMessage': managerMessage,
        'status': 'closed',
      };
      if (mediaId != null) {
        bodyData['proofPhoto'] = mediaId;
      }

      final res = await http.patch(
        Uri.parse('$_baseUrl/cctv-reports/$id?depth=2'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(bodyData),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final Map<String, dynamic> doc = Map<String, dynamic>.from((data['doc'] ?? data) as Map);
        if (mediaDoc != null) {
          if (doc['proofPhoto'] == null || doc['proofPhoto'] is String) {
            doc['proofPhoto'] = mediaDoc;
          }
        }
        return doc;
      } else {
        throw Exception('Failed to send manager reply (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  String _guessMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<Map<String, dynamic>> fetchMyDailyTasks({String? dateString}) async {
    final token = await _getToken();
    final today = dateString ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    final endpoints = [
      '$_baseUrl/daily-tasks/my-tasks?dateString=$today',
      '$_baseUrl/my-daily-tasks?dateString=$today',
      '$_baseUrl/tasks/my-daily-tasks?dateString=$today',
    ];

    for (final url in endpoints) {
      try {
        final res = await http.get(
          Uri.parse(url),
          headers: {
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic> && data['tasks'] is List) {
            return data;
          }
        }
      } catch (_) {}
    }

    // Direct collection fallback (Guaranteed to return tasks even before server endpoint redeploy!)
    try {
      final userRole = ((await storage.read(key: 'userRole')) ?? '').toLowerCase().trim();
      final userId = await storage.read(key: 'userId');

      // Attempt to resolve employee info from profile
      String? empId;
      String empTeam = '';
      try {
        final profile = await fetchUserProfile();
        final userDoc = profile['user'] is Map ? profile['user'] : profile;
        final empObj = userDoc['employee'];
        if (empObj is Map) {
          empId = (empObj['id'] ?? empObj['_id'])?.toString();
          empTeam = (empObj['team']?.toString() ?? '').toLowerCase().trim();
        } else if (empObj != null) {
          empId = empObj.toString();
        }
      } catch (_) {}

      final tasksRes = await http.get(
        Uri.parse('$_baseUrl/tasks?limit=500&depth=1'),
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (tasksRes.statusCode == 200) {
        final tasksJson = jsonDecode(tasksRes.body);
        final docs = (tasksJson['docs'] as List?) ?? [];

        // Fetch completions for today if possible
        Map<String, dynamic> completionMap = {};
        try {
          final compRes = await http.get(
            Uri.parse('$_baseUrl/task-completions?where[dateString][equals]=$today&limit=500&depth=0'),
            headers: {
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          );
          if (compRes.statusCode == 200) {
            final compJson = jsonDecode(compRes.body);
            for (final c in (compJson['docs'] as List? ?? [])) {
              if (c['tasks'] is List) {
                final docUser = c['user'] is Map ? c['user']['id']?.toString() : c['user']?.toString();
                final docEmp = c['employee'] is Map ? c['employee']['id']?.toString() : c['employee']?.toString();
                final isMatch = (userId != null && (docUser == userId || docEmp == userId)) ||
                    (empId != null && (docEmp == empId || docUser == empId));
                if (isMatch) {
                  for (final item in (c['tasks'] as List)) {
                    final tId = item['task'] is Map ? item['task']['id']?.toString() : item['task']?.toString();
                    if (tId != null) {
                      completionMap[tId] = {
                        ...Map<String, dynamic>.from(item as Map),
                        'id': c['id'],
                      };
                    }
                  }
                }
              } else {
                final tId = c['task'] is Map ? c['task']['id'] : c['task']?.toString();
                if (tId != null) {
                  completionMap[tId] = c;
                }
              }
            }
          }
        } catch (_) {}

        final filteredTasks = docs.where((t) {
          if (t['isActive'] == false) return false;

          final col = t['column'];
          final colRole = col is Map ? (col['role']?.toString().toLowerCase().trim() ?? '') : '';
          final colTitle = col is Map ? (col['title']?.toString().toLowerCase().trim() ?? '') : '';
          final assignedRole = (t['assignedRole']?.toString() ?? '').toLowerCase().trim();
          final taskRole = assignedRole.isNotEmpty ? assignedRole : (colRole.isNotEmpty ? colRole : colTitle);

          final assignmentType = (t['assignmentType']?.toString() ?? 'role').toLowerCase();

          // Individual match
          final tEmp = t['assignedEmployee'];
          final tEmpId = tEmp is Map ? tEmp['id']?.toString() : tEmp?.toString();
          final tUser = t['assignedUser'];
          final tUserId = tUser is Map ? tUser['id']?.toString() : tUser?.toString();

          final matchesInd = (empId != null && tEmpId == empId) ||
              (userId != null && (tUserId == userId || tEmpId == userId));

          // Role match (supports ALL roles: kitchen, chef, waiter, cashier, manager, supervisor, delivery, driver, etc.)
          final matchesRole = taskRole == 'all' ||
              (userRole.isNotEmpty && taskRole == userRole) ||
              (empTeam.isNotEmpty && taskRole == empTeam) ||
              userRole == 'admin' ||
              userRole == 'superadmin';

          if (assignmentType == 'individual') {
            return matchesInd;
          }
          if (assignmentType == 'role') {
            return matchesRole;
          }
          if (assignmentType == 'both') {
            return matchesInd || matchesRole;
          }
          if (assignmentType == 'unassigned') {
            return true;
          }

          return matchesInd || matchesRole;
        }).map((t) {
          final id = t['id']?.toString() ?? '';
          final comp = completionMap[id];
          return {
            'id': id,
            'title': t['title'] ?? 'Task',
            'description': t['description'] ?? '',
            'priority': t['priority'] ?? 'medium',
            'frequency': t['frequency'] ?? (t['isDaily'] == false ? 'weekly' : 'daily'),
            'isDaily': (t['frequency'] ?? (t['isDaily'] == false ? 'weekly' : 'daily')) == 'daily',
            'assignedRole': t['assignedRole'] ?? (t['column'] is Map ? t['column']['title'] : null),
            'requiresPhoto': t['requiresPhoto'] == true,
            'completed': comp != null ? (comp['completed'] == true) : false,
            'completedAt': comp?['completedAt'],
            'completionId': comp?['id'],
            'photo': comp?['photo'],
            'photoUrl': comp?['photoUrl'],
            'notes': comp?['notes'] ?? '',
          };
        }).toList();

        return {
          'success': true,
          'dateString': today,
          'tasks': filteredTasks,
        };
      }
    } catch (e) {
      debugPrint('Fallback error in fetchMyDailyTasks: $e');
    }

    return {'success': false, 'tasks': []};
  }

  /// Upload task completion photo proof to Payload media collection
  Future<Map<String, dynamic>> uploadTaskProofImage(File imageFile) async {
    final token = await _getToken();
    final mediaUri = Uri.parse('$_baseUrl/media?prefix=tasks');
    final mediaReq = http.MultipartRequest('POST', mediaUri);
    if (token != null) mediaReq.headers['Authorization'] = 'Bearer $token';

    final mimeType = _guessMimeType(imageFile.path);
    mediaReq.files.add(
      await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
        contentType: http_parser.MediaType.parse(mimeType),
      ),
    );

    final mediaStreamed = await mediaReq.send();
    final mediaRes = await http.Response.fromStream(mediaStreamed);

    if (mediaRes.statusCode != 200 && mediaRes.statusCode != 201) {
      throw Exception('Failed to upload image (${mediaRes.statusCode}): ${mediaRes.body}');
    }

    final mediaData = jsonDecode(mediaRes.body);
    final doc = mediaData['doc'] is Map ? mediaData['doc'] : mediaData;
    final mediaId = doc['id']?.toString() ?? '';
    final mediaUrl = doc['url']?.toString() ?? doc['thumbnailURL']?.toString() ?? '';

    return {
      'id': mediaId,
      'url': mediaUrl,
      'doc': doc,
    };
  }

  Future<Map<String, dynamic>> toggleDailyTask({
    required String taskId,
    bool? completed,
    String? dateString,
    String? notes,
    String? photoId,
    String? photoUrl,
  }) async {
    final token = await _getToken();
    final today = dateString ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    final endpoints = [
      '$_baseUrl/daily-tasks/toggle',
      '$_baseUrl/toggle-daily-task',
      '$_baseUrl/tasks/toggle-daily-task',
    ];

    for (final url in endpoints) {
      try {
        final res = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'taskId': taskId,
            if (completed != null) 'completed': completed,
            'dateString': today,
            if (notes != null) 'notes': notes,
            if (photoId != null) 'photo': photoId,
            if (photoUrl != null) 'photoUrl': photoUrl,
          }),
        );
        if (res.statusCode == 200) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    // Direct collection fallback:
    try {
      final userId = await storage.read(key: 'userId');
      String? empId;
      try {
        final profile = await fetchUserProfile();
        final userDoc = profile['user'] is Map ? profile['user'] : profile;
        final empObj = userDoc['employee'];
        if (empObj is Map) {
          empId = (empObj['id'] ?? empObj['_id'])?.toString();
        } else if (empObj != null) {
          empId = empObj.toString();
        }
      } catch (_) {}

      final checkRes = await http.get(
        Uri.parse('$_baseUrl/task-completions?where[dateString][equals]=$today&limit=100&depth=0'),
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (checkRes.statusCode == 200) {
        final checkJson = jsonDecode(checkRes.body);
        final docs = (checkJson['docs'] as List?) ?? [];

        // Find existing doc for current user/employee today
        Map<String, dynamic>? existingDoc;
        for (final doc in docs) {
          final docUser = doc['user'] is Map ? doc['user']['id']?.toString() : doc['user']?.toString();
          final docEmp = doc['employee'] is Map ? doc['employee']['id']?.toString() : doc['employee']?.toString();
          if ((userId != null && (docUser == userId || docEmp == userId)) ||
              (empId != null && (docEmp == empId || docUser == empId))) {
            existingDoc = Map<String, dynamic>.from(doc as Map);
            break;
          }
        }

        if (existingDoc != null) {
          final docId = existingDoc['id'];
          final currentTasks = List<Map<String, dynamic>>.from(
            (existingDoc['tasks'] as List? ?? []).map((t) => Map<String, dynamic>.from(t as Map)),
          );

          final taskIdx = currentTasks.indexWhere((t) {
            final id = t['task'] is Map ? t['task']['id']?.toString() : t['task']?.toString();
            return id == taskId;
          });

          final bool isComp;
          final String? compAt;
          if (taskIdx != -1) {
            isComp = completed ?? !(currentTasks[taskIdx]['completed'] == true);
            compAt = isComp ? (currentTasks[taskIdx]['completedAt'] ?? DateTime.now().toIso8601String()) : null;
            currentTasks[taskIdx] = {
              ...currentTasks[taskIdx],
              'task': taskId,
              'completed': isComp,
              'completedAt': compAt,
              if (photoId != null) 'photo': photoId,
              if (photoUrl != null) 'photoUrl': photoUrl,
              if (notes != null) 'notes': notes,
            };
          } else {
            isComp = completed ?? true;
            compAt = isComp ? DateTime.now().toIso8601String() : null;
            currentTasks.add({
              'task': taskId,
              'completed': isComp,
              'completedAt': compAt,
              if (photoId != null) 'photo': photoId,
              if (photoUrl != null) 'photoUrl': photoUrl,
              'notes': notes ?? '',
            });
          }

          final patchRes = await http.patch(
            Uri.parse('$_baseUrl/task-completions/$docId'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'tasks': currentTasks,
            }),
          );
          if (patchRes.statusCode == 200) {
            return {'success': true, 'completed': isComp, 'completedAt': compAt, 'doc': jsonDecode(patchRes.body)};
          }
        } else {
          final isComp = completed ?? true;
          final compAt = isComp ? DateTime.now().toIso8601String() : null;
          final postRes = await http.post(
            Uri.parse('$_baseUrl/task-completions'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'user': userId,
              if (empId != null) 'employee': empId,
              'dateString': today,
              'date': DateTime.now().toIso8601String(),
              'tasks': [
                {
                  'task': taskId,
                  'completed': isComp,
                  'completedAt': compAt,
                  if (photoId != null) 'photo': photoId,
                  if (photoUrl != null) 'photoUrl': photoUrl,
                  'notes': notes ?? '',
                }
              ],
            }),
          );
          if (postRes.statusCode == 200 || postRes.statusCode == 201) {
            return {'success': true, 'completed': isComp, 'completedAt': compAt, 'doc': jsonDecode(postRes.body)};
          }
        }
      }
    } catch (e) {
      debugPrint('Fallback error in toggleDailyTask: $e');
    }

    return {'success': false};
  }
}


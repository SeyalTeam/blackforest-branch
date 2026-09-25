import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';

class ApiConfig {
  static const String domain = "https://dev1-blacforest.vseyal.com";
  static const String baseUrl = "$domain/api";

  static Map<String, String> getHeaders(String? token) {
    final headers = {"Content-Type": "application/json"};
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }

  static Future<Map<String, dynamic>> fetchUserProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/me'),
        headers: getHeaders(token),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('fetchUserProfile error: $e');
    }
    return {};
  }

  static Future<Map<String, dynamic>> fetchBranchGeoSettings(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/globals/branchGeoSettings'),
        headers: getHeaders(token),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('fetchBranchGeoSettings error: $e');
    }
    return {};
  }

}

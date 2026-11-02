import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:branch/app_http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class GeoSettingsManager {
  static Map<String, dynamic>? _memoryCache;
  static const String _storageKey = 'cached_branch_geo_settings';

  /// Returns cached settings directly from RAM/Disk.
  /// Zero background timer. Only fetches over network when:
  /// 1. `forceRefresh == true` (User pulls down to refresh)
  /// 2. First-time app open (Cache is completely empty)
  static Future<Map<String, dynamic>> getSettings({
    bool forceRefresh = false,
    String? token,
  }) async {
    // 1. If we already have it in memory and not forcing a refresh, return immediately
    if (!forceRefresh && _memoryCache != null && _memoryCache!.isNotEmpty) {
      return _memoryCache!;
    }

    // 2. Check persistent disk cache (SharedPreferences)
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_storageKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
            _memoryCache = decoded;
            return decoded;
          }
        }
      } catch (e) {
        debugPrint('GeoSettingsManager: Error reading disk cache: $e');
      }
    }

    // 3. Fetch from network ONLY on pull-to-refresh (forceRefresh) or if cache is completely empty
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveToken = token ?? prefs.getString('token');
      final headers = ApiConfig.getHeaders(effectiveToken);

      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/globals/branch-geo-settings'),
            headers: {
              ...headers,
              http.skipUnauthorizedLogoutHeaderName: 'true',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          _memoryCache = decoded;
          await prefs.setString(_storageKey, response.body);
          return decoded;
        }
      } else {
        debugPrint('GeoSettingsManager: Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('GeoSettingsManager: Network fetch failed: $e');
    }

    // 4. If network failed, fall back to whatever we have in memory or disk
    if (_memoryCache != null) return _memoryCache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _memoryCache = decoded;
          return decoded;
        }
      }
    } catch (_) {}

    return const <String, dynamic>{};
  }

  /// Get list of branch locations from settings
  static Future<List<dynamic>> getLocations({bool forceRefresh = false}) async {
    final settings = await getSettings(forceRefresh: forceRefresh);
    final locations = settings['locations'];
    if (locations is List) return locations;
    return const [];
  }

  /// Invalidate cache
  static void invalidateCache() {
    _memoryCache = null;
  }
}

import 'package:shared_preferences/shared_preferences.dart';

Future<void> clearSessionPreservingFavorites(SharedPreferences prefs) async {
  final Map<String, dynamic> backup = {};
  for (final key in prefs.getKeys()) {
    if (key.startsWith('favorite_')) {
      backup[key] = prefs.get(key);
    } else if (key == 'printerPort' ||
        key == 'branchIp' ||
        key == 'printerIp') {
      backup[key] = prefs.get(key);
    }
  }

  await prefs.clear();

  for (final entry in backup.entries) {
    if (entry.value is List<String>) {
      await prefs.setStringList(entry.key, entry.value as List<String>);
    } else if (entry.value is String) {
      await prefs.setString(entry.key, entry.value as String);
    } else if (entry.value is int) {
      await prefs.setInt(entry.key, entry.value as int);
    } else if (entry.value is bool) {
      await prefs.setBool(entry.key, entry.value as bool);
    }
  }
}

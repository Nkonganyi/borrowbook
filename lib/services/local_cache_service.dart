import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Generic JSON cache used to keep the last-fetched data on the device, so
/// screens have something to show when a fetch fails because there's no
/// internet, instead of a blank screen or a crash.
class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;
  LocalCacheService._internal();

  Future<void> saveList(String key, List<Map<String, dynamic>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>?> loadList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMap(String key, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> loadMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Convenience for optimistic writes: append one row to a cached list
  /// (or create the list if it doesn't exist yet), most-recent first.
  Future<void> prependToList(String key, Map<String, dynamic> row) async {
    final existing = await loadList(key) ?? [];
    existing.insert(0, row);
    await saveList(key, existing);
  }
}

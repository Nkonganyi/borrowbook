import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's theme choice (light / dark / follow system) and
/// persists it locally so it survives app restarts — entirely offline,
/// no server round-trip needed for a UI preference like this.
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();
  factory ThemeController() => instance;
  ThemeController._internal();

  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    switch (saved) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  Future<void> toggleDark(bool dark) => setMode(dark ? ThemeMode.dark : ThemeMode.light);
}

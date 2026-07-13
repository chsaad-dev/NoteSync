import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/di/injection_container.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final FlutterSecureStorage _secureStorage;
  static const _themeKey = 'notesync_theme_mode';

  ThemeNotifier(this._secureStorage) : super(ThemeMode.system) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final themeStr = await _secureStorage.read(key: _themeKey);
    if (themeStr == 'light') {
      state = ThemeMode.light;
    } else if (themeStr == 'dark') {
      state = ThemeMode.dark;
    } else {
      state = ThemeMode.system;
    }
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
      await _secureStorage.write(key: _themeKey, value: 'light');
    } else {
      state = ThemeMode.dark;
      await _secureStorage.write(key: _themeKey, value: 'dark');
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier(sl<FlutterSecureStorage>());
});

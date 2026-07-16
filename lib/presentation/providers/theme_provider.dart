import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/di/injection_container.dart';

class CustomThemeState {
  final ThemeMode themeMode;
  final String primaryColorKey;
  final String fontFamilyKey;
  final bool isPureBlack;

  const CustomThemeState({
    required this.themeMode,
    required this.primaryColorKey,
    required this.fontFamilyKey,
    required this.isPureBlack,
  });

  CustomThemeState copyWith({
    ThemeMode? themeMode,
    String? primaryColorKey,
    String? fontFamilyKey,
    bool? isPureBlack,
  }) {
    return CustomThemeState(
      themeMode: themeMode ?? this.themeMode,
      primaryColorKey: primaryColorKey ?? this.primaryColorKey,
      fontFamilyKey: fontFamilyKey ?? this.fontFamilyKey,
      isPureBlack: isPureBlack ?? this.isPureBlack,
    );
  }

  Color get primaryColor {
    switch (primaryColorKey) {
      case 'teal':
        return const Color(0xFF0D9488);
      case 'pink':
        return const Color(0xFFEC4899);
      case 'amber':
        return const Color(0xFFD97706);
      case 'purple':
        return const Color(0xFF8B5CF6);
      case 'indigo':
      default:
        return const Color(0xFF6366F1);
    }
  }

  String? get fontFamily {
    switch (fontFamilyKey) {
      case 'serif':
        return 'serif';
      case 'monospace':
        return 'monospace';
      case 'sansSerif':
      default:
        return null;
    }
  }
}

class ThemeNotifier extends StateNotifier<CustomThemeState> {
  final FlutterSecureStorage _secureStorage;

  static const _themeModeKey = 'notesync_theme_mode';
  static const _primaryColorKey = 'notesync_theme_primary_color';
  static const _fontFamilyKey = 'notesync_theme_font_family';
  static const _isPureBlackKey = 'notesync_theme_is_pure_black';

  ThemeNotifier(this._secureStorage)
      : super(const CustomThemeState(
          themeMode: ThemeMode.system,
          primaryColorKey: 'indigo',
          fontFamilyKey: 'sansSerif',
          isPureBlack: false,
        )) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final themeStr = await _secureStorage.read(key: _themeModeKey);
    final colorStr = await _secureStorage.read(key: _primaryColorKey);
    final fontStr = await _secureStorage.read(key: _fontFamilyKey);
    final pureBlackStr = await _secureStorage.read(key: _isPureBlackKey);

    ThemeMode loadedThemeMode = ThemeMode.system;
    if (themeStr == 'light') {
      loadedThemeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      loadedThemeMode = ThemeMode.dark;
    }

    state = CustomThemeState(
      themeMode: loadedThemeMode,
      primaryColorKey: colorStr ?? 'indigo',
      fontFamilyKey: fontStr ?? 'sansSerif',
      isPureBlack: pureBlackStr == 'true',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    String modeStr = 'system';
    if (mode == ThemeMode.light) {
      modeStr = 'light';
    } else if (mode == ThemeMode.dark) {
      modeStr = 'dark';
    }
    await _secureStorage.write(key: _themeModeKey, value: modeStr);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setPrimaryColor(String colorKey) async {
    await _secureStorage.write(key: _primaryColorKey, value: colorKey);
    state = state.copyWith(primaryColorKey: colorKey);
  }

  Future<void> setFontFamily(String fontKey) async {
    await _secureStorage.write(key: _fontFamilyKey, value: fontKey);
    state = state.copyWith(fontFamilyKey: fontKey);
  }

  Future<void> setPureBlack(bool pureBlack) async {
    await _secureStorage.write(key: _isPureBlackKey, value: pureBlack.toString());
    state = state.copyWith(isPureBlack: pureBlack);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, CustomThemeState>((ref) {
  return ThemeNotifier(sl<FlutterSecureStorage>());
});

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用主题状态：亮/暗、种子色、河流 shader 是否使用主题色。
/// 类似 [flutter_material_3_demo] 的 theme 能力，支持 ColorScheme.fromSeed。
class ThemeProvider extends ChangeNotifier {
  ThemeProvider._();
  static final ThemeProvider instance = ThemeProvider._();

  static const String _keyBrightness = 'theme_brightness'; // 'light' | 'dark'
  static const String _keySeedColor = 'theme_seed_color'; // 0xFFFFFFFF 整数
  static const String _keyUseThemeColorForRiver = 'theme_use_theme_color_for_river'; // bool

  Brightness _brightness = Brightness.light;
  Color _seedColor = const Color(0xFF0097A7); // 默认与原有底部导航主色一致
  bool _useThemeColorForRiver = false;

  Brightness get brightness => _brightness;
  Color get seedColor => _seedColor;
  bool get useThemeColorForRiver => _useThemeColorForRiver;
  bool get isDark => _brightness == Brightness.dark;

  /// 从 SharedPreferences 加载（启动时调用）
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final brightnessIndex = prefs.getString(_keyBrightness);
    instance._brightness = brightnessIndex == 'dark' ? Brightness.dark : Brightness.light;
    instance._seedColor = Color(prefs.getInt(_keySeedColor) ?? 0xFF0097A7);
    instance._useThemeColorForRiver = prefs.getBool(_keyUseThemeColorForRiver) ?? false;
  }

  Future<void> setBrightness(Brightness value) async {
    if (_brightness == value) return;
    _brightness = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBrightness, value == Brightness.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setSeedColor(Color value) async {
    if (_seedColor == value) return;
    _seedColor = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeedColor, value.toARGB32());
    notifyListeners();
  }

  Future<void> setUseThemeColorForRiver(bool value) async {
    if (_useThemeColorForRiver == value) return;
    _useThemeColorForRiver = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseThemeColorForRiver, value);
    notifyListeners();
  }

  /// 供 MaterialApp 使用的亮色 ThemeData（Material 3 + fromSeed）
  ThemeData get lightTheme => _buildTheme(Brightness.light);
  /// 供 MaterialApp 使用的暗色 ThemeData
  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
        primary: _seedColor,
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF9F9F9)
          : const Color(0xFF121212),
    );
  }
}

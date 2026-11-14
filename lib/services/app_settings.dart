import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static final instance = AppSettings._();
  AppSettings._();

  late SharedPreferences _prefs;
  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs.getString('theme_mode');
    themeMode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> cycleTheme() async {
    final next = switch (themeMode.value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    themeMode.value = next;
    await _prefs.setString('theme_mode', next.name);
  }

  IconData get themeIcon => switch (themeMode.value) {
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
    _ => Icons.brightness_auto,
  };

  String get themeLabel => switch (themeMode.value) {
    ThemeMode.light => '라이트 모드',
    ThemeMode.dark => '다크 모드',
    _ => '시스템',
  };
}

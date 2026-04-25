import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _boxKey = 'theme_mode';
  final Box<dynamic> _box;
  ThemeMode _mode;

  ThemeProvider(this._box) : _mode = _readMode(_box);

  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _box.put(_boxKey, _encodeMode(mode));
    notifyListeners();
  }

  static ThemeMode _readMode(Box<dynamic> box) {
    final raw = box.get(_boxKey);
    if (raw is String) {
      switch (raw) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        case 'system':
          return ThemeMode.system;
      }
    }
    return ThemeMode.dark;
  }

  static String _encodeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ThemeModeMenuButton extends StatelessWidget {
  const ThemeModeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ThemeProvider>();
    final mode = provider.mode;

    return IconButton(
      tooltip: 'Тема',
      icon: Icon(_iconFor(mode, theme.brightness)),
      onPressed: () {
        final next = _nextMode(mode, theme.brightness);
        provider.setMode(next);
      },
    );
  }

  IconData _iconFor(ThemeMode mode, Brightness brightness) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
      default:
        return brightness == Brightness.dark
          ? Icons.dark_mode_outlined
          : Icons.light_mode_outlined;
    }
  }

  ThemeMode _nextMode(ThemeMode current, Brightness brightness) {
    if (current == ThemeMode.light) return ThemeMode.dark;
    if (current == ThemeMode.dark) return ThemeMode.light;
    return brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

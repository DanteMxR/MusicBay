import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/api_service.dart';
import 'services/audio_player_service.dart';
import 'services/cache_service.dart';
import 'services/library_index_service.dart';
import 'providers/music_provider.dart';
import 'providers/audio_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/update_required_screen.dart';
import 'models/track.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  final api = ApiService(SecureSessionStore());
  await api.init();

  final settingsBox = await Hive.openBox('settings');
  Track.preferredQuality =
      settingsBox.get('stream_quality', defaultValue: 'normal') as String;

  final cacheService = CacheService();
  await cacheService.init();

  final libraryIndexService = LibraryIndexService();
  await libraryIndexService.init();

  final audioService = AudioPlayerService();
  await audioService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => MusicProvider(api, libraryIndexService)..bootstrap(),
        ),
        Provider<LibraryIndexService>.value(value: libraryIndexService),
        Provider<CacheService>.value(value: cacheService),
        Provider<AudioPlayerService>(
          create: (_) => audioService,
          dispose: (_, service) async {
            await service.dispose();
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final music = context.read<MusicProvider>();
            return AudioProvider(
              context.read<AudioPlayerService>(),
              context.read<CacheService>(),
              music.isTrackSaved,
              music.freshenTracks,
              music.reportPlay,
            );
          },
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider(settingsBox)),
      ],
      child: const MusicBayApp(),
    ),
  );
}

class MusicBayApp extends StatefulWidget {
  const MusicBayApp({super.key});

  @override
  State<MusicBayApp> createState() => _MusicBayAppState();
}

class _MusicBayAppState extends State<MusicBayApp> {
  static const _orangeAccent = Color(0xFFFF8A1A);
  static const _darkBackground = Color(0xFF0D0D0D);
  static const _darkSurface = Color(0xFF17191C);
  static const _darkSurfaceHigh = Color(0xFF202329);
  static const _darkSurfaceHighest = Color(0xFF2B2F36);
  static const _lightBackground = Color(0xFFF7F4EF);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHigh = Color(0xFFF1ECE4);
  static const _lightSurfaceHighest = Color(0xFFE6E0D6);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid || !mounted) return;

    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? _darkBackground : _lightBackground;
    final surface = isDark ? _darkSurface : _lightSurface;
    final surfaceHigh = isDark ? _darkSurfaceHigh : _lightSurfaceHigh;
    final surfaceHighest = isDark ? _darkSurfaceHighest : _lightSurfaceHighest;

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _orangeAccent,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: _orangeAccent,
          secondary: const Color(0xFFFFB15F),
          surface: surface,
          surfaceContainer: surface,
          surfaceContainerHigh: surfaceHigh,
          surfaceContainerHighest: surfaceHighest,
          onPrimary: Colors.black,
        );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 4,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.15),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: _orangeAccent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: _orangeAccent.withValues(alpha: 0.16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _orangeAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _orangeAccent,
        inactiveTrackColor: colorScheme.onSurface.withValues(
          alpha: isDark ? 0.14 : 0.2,
        ),
        thumbColor: _orangeAccent,
        overlayColor: _orangeAccent.withValues(alpha: 0.18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _orangeAccent, width: 1.2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = _buildTheme(Brightness.light);
    final darkTheme = _buildTheme(Brightness.dark);
    final themeMode = context.watch<ThemeProvider>().mode;

    return MaterialApp(
      title: 'MusicBay',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: Consumer<MusicProvider>(
        builder: (context, music, _) {
          if (music.clientOutdated) return const UpdateRequiredScreen();
          return music.isAuthorized ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}

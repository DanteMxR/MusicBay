import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/vk_api_service.dart';
import 'services/audio_player_service.dart';
import 'services/cache_service.dart';
import 'providers/vk_provider.dart';
import 'providers/audio_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  final vkApi = VkApiService();
  await vkApi.init();

  final cacheService = CacheService();
  await cacheService.init();

  final audioService = AudioPlayerService();
  await audioService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VkProvider(vkApi)),
        Provider<CacheService>.value(value: cacheService),
        Provider<AudioPlayerService>(
          create: (_) => audioService,
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider(
          create: (context) => AudioProvider(
            context.read<AudioPlayerService>(),
            context.read<CacheService>(),
            context.read<VkProvider>(),
          ),
        ),
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
  static const _background = Color(0xFF0D0D0D);
  static const _surface = Color(0xFF171717);
  static const _surfaceHigh = Color(0xFF202020);

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

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _orangeAccent,
          brightness: Brightness.dark,
          surface: _surface,
        ).copyWith(
          primary: _orangeAccent,
          secondary: const Color(0xFFFFB15F),
          surface: _surface,
          surfaceContainer: _surface,
          surfaceContainerHigh: _surfaceHigh,
          surfaceContainerHighest: const Color(0xFF2A2A2A),
          onPrimary: Colors.black,
        );

    return MaterialApp(
      title: 'MusicBay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _background,
        canvasColor: _surface,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _surface,
          indicatorColor: _orangeAccent.withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            );
          }),
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
          backgroundColor: _surfaceHigh,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: _orangeAccent,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
          thumbColor: _orangeAccent,
          overlayColor: _orangeAccent.withValues(alpha: 0.18),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceHigh,
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
      ),
      home: Consumer<VkProvider>(
        builder: (context, vk, _) {
          return vk.isAuthorized ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => VkProvider(vkApi),
        ),
        Provider.value(value: cacheService),
        ChangeNotifierProvider(
          create: (_) => AudioProvider(audioService, cacheService),
        ),
      ],
      child: const MusicBayApp(),
    ),
  );
}

class MusicBayApp extends StatelessWidget {
  const MusicBayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicBay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Consumer<VkProvider>(
        builder: (context, vk, _) {
          return vk.isAuthorized ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}

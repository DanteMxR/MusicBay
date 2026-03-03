import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vk_provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/mini_player.dart';
import 'tabs/my_music_tab.dart';
import 'tabs/search_tab.dart';
import 'tabs/playlists_tab.dart';
import 'tabs/downloads_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  final _tabs = const [
    MyMusicTab(),
    SearchTab(),
    PlaylistsTab(),
    DownloadsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vk = context.read<VkProvider>();
      vk.loadMyTracks(refresh: true);
      vk.loadPlaylists();
      vk.loadRecommendations(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _tabs[_currentTab]),
          if (audio.currentTrack != null) const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note),
            label: 'Моя музыка',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Поиск',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_play_outlined),
            selectedIcon: Icon(Icons.playlist_play),
            label: 'Плейлисты',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_done),
            label: 'Загрузки',
          ),
        ],
      ),
    );
  }
}

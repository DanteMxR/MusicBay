import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vk_provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/mini_player.dart';
import 'tabs/home_feed_tab.dart';
import 'tabs/my_music_tab.dart';
import 'tabs/search_tab.dart';
import 'tabs/playlists_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  final _tabs = const [
    HomeFeedTab(),
    MyMusicTab(),
    SearchTab(),
    PlaylistsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vk = context.read<VkProvider>();
      vk.loadMyTracks(refresh: true);
      vk.loadPlaylists();
      vk.loadDiscovery(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();
    final currentTab = _currentTab.clamp(0, _tabs.length - 1);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: currentTab,
              children: _tabs,
            ),
          ),
          if (audio.currentTrack != null) const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
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
        ],
      ),
    );
  }
}

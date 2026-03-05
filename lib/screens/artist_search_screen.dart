import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../widgets/mini_player.dart';
import 'tabs/search_tab.dart';

class ArtistSearchScreen extends StatelessWidget {
  final String artist;

  const ArtistSearchScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(artist)),
      body: Column(
        children: [
          Expanded(
            child: SearchTab(
              initialQuery: artist,
              artistOnly: true,
              showScaffold: false,
            ),
          ),
          if (audio.currentTrack != null) const MiniPlayer(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../providers/vk_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

class GeneratedAlbumScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Track> tracks;

  const GeneratedAlbumScreen({
    super.key,
    required this.title,
    required this.tracks,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tracks.isEmpty
          ? const Center(child: Text('Пустой альбом'))
          : ListView.builder(
              itemCount: tracks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle ?? 'Собрано локально из вашей медиатеки',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => audio.playPauseTrack(
                            tracks.first,
                            tracks,
                            startIndex: 0,
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Слушать'),
                        ),
                      ],
                    ),
                  );
                }

                final track = tracks[index - 1];
                final isPlaying =
                    audio.currentTrack?.id == track.id &&
                    audio.currentTrack?.ownerId == track.ownerId;

                return TrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  trailing: _buildAddToLibraryButton(context, track),
                  onTap: () =>
                      audio.playPauseTrack(track, tracks, startIndex: index - 1),
                );
              },
            ),
      bottomNavigationBar: audio.currentTrack != null ? const MiniPlayer() : null,
    );
  }

  Widget _buildAddToLibraryButton(BuildContext context, Track track) {
    final vk = context.read<VkProvider>();
    final isSaved = vk.isTrackSaved(track.id, ownerId: track.ownerId);

    return IconButton(
      tooltip: isSaved ? 'Уже в коллекции' : 'Добавить в коллекцию',
      icon: Icon(
        isSaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
      ),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final added = await vk.toggleSavedTrack(track);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              added ? 'Трек добавлен в коллекцию' : 'Трек удален из коллекции',
            ),
          ),
        );
      },
    );
  }
}


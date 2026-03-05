import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';
import '../providers/vk_provider.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import 'artist_search_screen.dart';
import '../widgets/artwork_image.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();
    final vk = context.watch<VkProvider>();
    final track = audio.currentTrack;
    final theme = Theme.of(context);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Нет трека')),
      );
    }

    final isSaved = vk.isTrackSaved(track.id, ownerId: track.ownerId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isSaved
                  ? Icons.library_add_check_rounded
                  : Icons.library_add_outlined,
            ),
            tooltip: isSaved ? 'Удалить из коллекции' : 'Добавить в коллекцию',
            onPressed: () => _toggleCurrentTrackSaved(context),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _downloadTrack(context),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.2),
              theme.scaffoldBackgroundColor,
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              ArtworkImage(
                track: track,
                width: 300,
                height: 300,
                borderRadius: BorderRadius.circular(20),
                placeholder: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note,
                    size: 80,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                track.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                track.artist,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _openArtistSearch(context, track.artist),
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: const Text('Найти исполнителя'),
              ),
              const SizedBox(height: 32),
              StreamBuilder<Duration>(
                stream: audio.positionStream,
                builder: (context, posSnap) {
                  return StreamBuilder<Duration?>(
                    stream: audio.durationStream,
                    builder: (context, durSnap) {
                      final position = posSnap.data ?? Duration.zero;
                      final duration = durSnap.data ?? Duration.zero;
                      final maxVal = duration.inMilliseconds.toDouble();

                      return Column(
                        children: [
                          Slider(
                            value: maxVal > 0
                                ? position.inMilliseconds.toDouble().clamp(
                                    0,
                                    maxVal,
                                  )
                                : 0,
                            max: maxVal > 0 ? maxVal : 1,
                            onChanged: (value) {
                              audio.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: audio.shuffle
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: audio.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    iconSize: 40,
                    onPressed: audio.previous,
                  ),
                  FilledButton(
                    onPressed: audio.playPause,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
                    ),
                    child: Icon(
                      audio.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 36,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    iconSize: 40,
                    onPressed: audio.next,
                  ),
                  IconButton(
                    icon: Icon(
                      _repeatIcon(audio.repeatMode),
                      color: audio.repeatMode != RepeatMode.off
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: audio.toggleRepeat,
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  IconData _repeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return Icons.repeat_rounded;
      case RepeatMode.all:
        return Icons.repeat_rounded;
      case RepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  void _downloadTrack(BuildContext context) async {
    final audio = context.read<AudioProvider>();
    final cache = context.read<CacheService>();
    final track = audio.currentTrack;
    if (track == null) return;

    if (cache.isTrackCached(track.id, ownerId: track.ownerId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Трек уже загружен')));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Загрузка...')));

    final path = await cache.cacheTrack(track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(path != null ? 'Трек загружен' : 'Ошибка загрузки'),
        ),
      );
    }
  }

  void _toggleCurrentTrackSaved(BuildContext context) async {
    final audio = context.read<AudioProvider>();
    final vk = context.read<VkProvider>();
    final track = audio.currentTrack;
    if (track == null) return;

    final added = await vk.toggleSavedTrack(track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added ? 'Трек добавлен в коллекцию' : 'Трек удален из коллекции',
          ),
        ),
      );
    }
  }

  void _openArtistSearch(BuildContext context, String artist) {
    final query = artist.trim();
    if (query.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistSearchScreen(artist: query),
      ),
    );
  }
}

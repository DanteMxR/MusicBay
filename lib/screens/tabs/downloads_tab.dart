import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/audio_provider.dart';
import '../../services/cache_service.dart';
import '../../widgets/track_tile.dart';
import '../../models/track.dart';

class DownloadsTab extends StatefulWidget {
  const DownloadsTab({super.key});

  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  List<Track> _cachedTracks = [];
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  void _loadCached() {
    final cache = context.read<CacheService>();
    setState(() {
      _cachedTracks = cache.getCachedTracks();
    });
    cache.getCacheSize().then((size) {
      if (mounted) setState(() => _cacheSize = size);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Загрузки'),
        actions: [
          if (_cachedTracks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _showClearDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_cachedTracks.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: theme.colorScheme.surfaceContainerLow,
              child: Text(
                '${_cachedTracks.length} треков, ${_formatSize(_cacheSize)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: _cachedTracks.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text('Нет загруженных треков'),
                        SizedBox(height: 8),
                        Text(
                          'Зажмите трек и выберите "Скачать"',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _cachedTracks.length,
                    itemBuilder: (context, index) {
                      final track = _cachedTracks[index];
                      final isPlaying = audio.isPlayingTrack(track);

                      return TrackTile(
                        track: track,
                        isPlaying: isPlaying,
                        isCached: true,
                        onTap: () {
                          audio.playPauseTrack(track, _cachedTracks, startIndex: index);
                        },
                        onLongPress: () => _showDeleteDialog(track),
                        trailing: const Icon(
                          Icons.download_done,
                          size: 20,
                          color: Color(0xFFFF8A1A),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(Track track) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить из загрузок'),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<CacheService>().removeFromCache(
                  track.id,
                  ownerId: track.ownerId,
                );
                _loadCached();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить кэш'),
        content: const Text('Удалить все загруженные треки?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<CacheService>().clearCache();
              _loadCached();
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }
}

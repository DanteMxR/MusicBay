import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/vk_provider.dart';
import '../../providers/audio_provider.dart';
import '../../services/cache_service.dart';
import '../../widgets/track_tile.dart';

enum _MyMusicFilter { all, downloaded }

class MyMusicTab extends StatefulWidget {
  const MyMusicTab({super.key});

  @override
  State<MyMusicTab> createState() => _MyMusicTabState();
}

class _MyMusicTabState extends State<MyMusicTab> {
  _MyMusicFilter _filter = _MyMusicFilter.all;

  @override
  Widget build(BuildContext context) {
    final vk = context.watch<VkProvider>();
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя музыка'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => vk.loadMyTracks(refresh: true),
        child: _buildBody(context, vk, audio),
      ),
    );
  }

  Widget _buildBody(BuildContext context, VkProvider vk, AudioProvider audio) {
    if (vk.myTracksLoading && vk.myTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vk.myTracksError != null && vk.myTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ошибка: ${vk.myTracksError}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => vk.loadMyTracks(refresh: true),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (vk.myTracks.isEmpty) {
      return const Center(child: Text('Нет треков'));
    }

    final cache = context.read<CacheService>();
    final theme = Theme.of(context);

    final allTracks = vk.myTracks;
    final cachedKeys = <String>{};
    for (final track in allTracks) {
      if (cache.isTrackCached(track.id, ownerId: track.ownerId)) {
        cachedKeys.add('${track.ownerId}_${track.id}');
      }
    }

    final visibleTracks = _filter == _MyMusicFilter.all
        ? allTracks
        : allTracks
              .where((t) => cachedKeys.contains('${t.ownerId}_${t.id}'))
              .toList(growable: false);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_filter == _MyMusicFilter.all &&
            notification.metrics.pixels >
                notification.metrics.maxScrollExtent - 200) {
          vk.loadMyTracks();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: visibleTracks.length + (vk.myTracksLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Все'),
                    selected: _filter == _MyMusicFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _MyMusicFilter.all),
                  ),
                  ChoiceChip(
                    label: const Text('Скачанные'),
                    selected: _filter == _MyMusicFilter.downloaded,
                    onSelected: (_) =>
                        setState(() => _filter = _MyMusicFilter.downloaded),
                  ),
                ],
              ),
            );
          }

          final dataIndex = index - 1;

          if (dataIndex >= visibleTracks.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final track = visibleTracks[dataIndex];
          final isPlaying =
              audio.currentTrack?.id == track.id &&
              audio.currentTrack?.ownerId == track.ownerId;
          final isCached = cachedKeys.contains('${track.ownerId}_${track.id}');

          return TrackTile(
            track: track,
            isPlaying: isPlaying,
            trailing: isCached
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.durationFormatted,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.download_done_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  )
                : null,
            onTap: () {
              audio.playPlaylist(visibleTracks, startIndex: dataIndex);
            },
            onLongPress: () => _showTrackMenu(context, track, vk),
          );
        },
      ),
    );
  }

  void _showTrackMenu(BuildContext context, dynamic track, VkProvider vk) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить из моей музыки'),
              onTap: () {
                Navigator.pop(ctx);
                vk.deleteTrack(track);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Выйти из аккаунта VK?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<VkProvider>().logout();
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

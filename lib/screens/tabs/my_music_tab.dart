import 'dart:async';
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
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool _isSearchMode = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vk = context.watch<VkProvider>();
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: _isSearchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '\u041f\u043e\u0438\u0441\u043a \u0432 \u043c\u043e\u0435\u0439 \u043c\u0443\u0437\u044b\u043a\u0435',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  final normalized = value.trim().toLowerCase();
                  setState(() => _searchQuery = normalized);
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                    if (!mounted || normalized.isEmpty) return;
                    context.read<VkProvider>().ensureMyTracksLoadedForSearch();
                  });
                },
              )
            : const Text('Моя музыка'),
        actions: [
          IconButton(
            icon: Icon(_isSearchMode ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearchMode) {
                  _isSearchMode = false;
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearchMode = true;
                }
              });
            },
          ),
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

    final filteredByType = _filter == _MyMusicFilter.all
        ? allTracks
        : allTracks
              .where((t) => cachedKeys.contains('${t.ownerId}_${t.id}'))
              .toList(growable: false);

    final visibleTracks = _searchQuery.isEmpty
        ? filteredByType
        : filteredByType
              .where((t) {
                final artist = t.artist.toLowerCase();
                final title = t.title.toLowerCase();
                final album = (t.albumTitle ?? '').toLowerCase();
                return artist.contains(_searchQuery) ||
                    title.contains(_searchQuery) ||
                    album.contains(_searchQuery);
              })
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
            onTap: () =>
                audio.playPauseTrack(track, visibleTracks, startIndex: dataIndex),
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



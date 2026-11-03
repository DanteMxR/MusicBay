import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/music_provider.dart';
import '../../services/cache_service.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/upload_button.dart';
import '../../widgets/track_dialogs.dart';
import '../account_screen.dart';

enum _MyMusicFilter { all, downloaded }

class MyMusicTab extends StatefulWidget {
  const MyMusicTab({super.key});

  @override
  State<MyMusicTab> createState() => _MyMusicTabState();
}

class _MyMusicTabState extends State<MyMusicTab> {
  _MyMusicFilter _filter = _MyMusicFilter.all;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool _isSearchMode = false;
  bool _prefetchScheduled = false;
  bool _chipsVisible = true;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _cancelSearchPrefetch();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _cancelSearchPrefetch() {
    context.read<MusicProvider>().cancelMyTracksSearchPrefetch();
  }

  void _scheduleSearchIndexSync(String normalizedQuery) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || normalizedQuery.isEmpty) return;
      context.read<MusicProvider>().ensureMyTracksLoadedForSearch();
    });
  }

  void _prefetchMyTracks(MusicProvider music, {ScrollMetrics? metrics}) {
    if (_filter != _MyMusicFilter.all) return;
    if (_searchQuery.isNotEmpty) return;
    if (music.myTracksLoading || !music.myTracksHasMore) return;
    if (music.myTracksError != null) return;

    final shouldLoad =
        metrics == null || metrics.extentAfter < kMyTracksPrefetchExtentPx;
    if (!shouldLoad) return;

    music.loadMyTracks();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleFilterTap(_MyMusicFilter filter) {
    if (_filter != filter) {
      setState(() => _filter = filter);
      return;
    }

    _scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: _isSearchMode
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Поиск в моей музыке',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  final normalized = value.trim().toLowerCase();
                  setState(() => _searchQuery = normalized);
                  if (normalized.isEmpty) {
                    _cancelSearchPrefetch();
                  } else {
                    _scheduleSearchIndexSync(normalized);
                  }
                },
              )
            : const Text('Моя музыка'),
        actions: [
          const UploadButton(),
          IconButton(
            icon: Icon(_isSearchMode ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearchMode) {
                  _isSearchMode = false;
                  _searchDebounce?.cancel();
                  _cancelSearchPrefetch();
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearchMode = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Аккаунт',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => music.loadMyTracks(refresh: true),
        child: _buildBody(context, music, audio),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MusicProvider music,
    AudioProvider audio,
  ) {
    if (!_prefetchScheduled &&
        _filter == _MyMusicFilter.all &&
        _searchQuery.isEmpty &&
        !music.myTracksLoading &&
        music.myTracksHasMore &&
        music.myTracksError == null &&
        music.myTracks.length < 120) {
      _prefetchScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prefetchScheduled = false;
        if (!mounted) return;
        _prefetchMyTracks(context.read<MusicProvider>());
      });
    }

    if (music.myTracksLoading && music.myTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final cache = context.read<CacheService>();
    final isOffline = music.myTracksError != null && music.myTracks.isEmpty;
    final List<Track> allTracks;

    if (isOffline) {
      final cachedTracks = cache.getCachedTracks();
      if (cachedTracks.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              const Text('Нет доступа к сети'),
              const SizedBox(height: 8),
              Text(
                'Скачанных треков нет',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => music.loadMyTracks(refresh: true),
                child: const Text('Повторить'),
              ),
            ],
          ),
        );
      }
      allTracks = cachedTracks;
    } else if (music.myTracks.isEmpty) {
      return const Center(child: Text('Нет треков'));
    } else {
      allTracks = music.myTracks;
    }

    final theme = Theme.of(context);
    final cachedKeys = <String>{
      for (final track in allTracks)
        if (cache.isTrackCached(track.id)) track.id,
    };

    final filteredByType = _filter == _MyMusicFilter.all
        ? allTracks
        : allTracks
              .where((t) => cachedKeys.contains(t.id))
              .toList(growable: false);

    final visibleTracks = _searchQuery.isEmpty
        ? filteredByType
        : _filter == _MyMusicFilter.downloaded || isOffline
        ? _filterTracks(filteredByType, _searchQuery)
        : music.searchMyTracksLocally(_searchQuery);

    final visibleCachedKeys = <String>{
      for (final track in visibleTracks)
        if (cache.isTrackCached(track.id)) track.id,
    };

    final isIndexingLibrary =
        _searchQuery.isNotEmpty && !isOffline && music.myTracksIndexSyncing;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _chipsVisible
              ? SizedBox(
                  width: double.infinity,
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isOffline)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_off,
                                    size: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Нет сети. Показаны скачанные треки',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        music.loadMyTracks(refresh: true),
                                    child: const Text('Повторить'),
                                  ),
                                ],
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Все'),
                                selected: _filter == _MyMusicFilter.all,
                                onSelected: (_) =>
                                    _handleFilterTap(_MyMusicFilter.all),
                              ),
                              ChoiceChip(
                                label: const Text('Скачанные'),
                                selected: _filter == _MyMusicFilter.downloaded,
                                onSelected: (_) =>
                                    _handleFilterTap(_MyMusicFilter.downloaded),
                              ),
                              if (!isOffline && allTracks.isNotEmpty)
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.download_for_offline_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Скачать оффлайн'),
                                  onPressed: () =>
                                      _showOfflineCacheOptions(context, music),
                                ),
                              if (cachedKeys.isNotEmpty)
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Очистить кэш'),
                                  onPressed: () =>
                                      _showClearCacheDialog(context),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (isIndexingLibrary)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Индексируем медиатеку для точного локального поиска',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                final delta = notification.scrollDelta ?? 0;
                if (delta > 4 && _chipsVisible) {
                  setState(() => _chipsVisible = false);
                } else if (delta < -4 && !_chipsVisible) {
                  setState(() => _chipsVisible = true);
                }
                _prefetchMyTracks(music, metrics: notification.metrics);
              } else if (notification is UserScrollNotification) {
                _prefetchMyTracks(music, metrics: notification.metrics);
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              itemCount: visibleTracks.length + (music.myTracksLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= visibleTracks.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final track = visibleTracks[index];
                final isPlaying = audio.currentTrack?.id == track.id;
                final isCached = visibleCachedKeys.contains(track.id);

                return TrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  isCached: isCached,
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
                  onTap: () => audio.playPauseTrack(
                    track,
                    visibleTracks,
                    startIndex: index,
                  ),
                  onLongPress: () => _showTrackMenu(context, track, music),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Track> _filterTracks(List<Track> tracks, String query) {
    return tracks
        .where((track) {
          final artist = track.artist.toLowerCase();
          final title = track.title.toLowerCase();
          final album = (track.albumTitle ?? '').toLowerCase();
          return artist.contains(query) ||
              title.contains(query) ||
              album.contains(query);
        })
        .toList(growable: false);
  }

  List<Track> _offlineSourceTracks(MusicProvider music) {
    final source = music.myTracksIndex.isNotEmpty
        ? music.myTracksIndex
        : music.myTracks;
    return source
        .where((track) => track.url.trim().isNotEmpty)
        .toList(growable: false);
  }

  void _showOfflineCacheOptions(BuildContext context, MusicProvider music) {
    final source = _offlineSourceTracks(music);
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пока нет доступных треков для оффлайн-кэша'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Загрузка в оффлайн-кэш может занять некоторое время и зависит от скорости сети.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Скачать первые 50'),
              subtitle: Text(
                'Будут сохранены ${source.length < 50 ? source.length : 50} треков',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _cacheFirstTracks(context, music, 50);
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('Скачать первые 100'),
              subtitle: Text(
                'Будут сохранены ${source.length < 100 ? source.length : 100} треков',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _cacheFirstTracks(context, music, 100);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cacheFirstTracks(
    BuildContext context,
    MusicProvider music,
    int count,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final cache = context.read<CacheService>();
    final source = _offlineSourceTracks(music);
    final tracksToCache = source.take(count).toList(growable: false);

    if (tracksToCache.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Нет треков, доступных для оффлайн-кэша')),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Скачиваем первые ${tracksToCache.length} треков. Это может занять некоторое время...',
        ),
      ),
    );

    final cached = await cache.cacheTracksIfNeeded(
      tracksToCache,
      maxToDownload: count,
    );

    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Оффлайн доступно: $cached из ${tracksToCache.length} треков',
        ),
      ),
    );
  }

  void _showTrackMenu(BuildContext context, Track track, MusicProvider music) {
    final cache = context.read<CacheService>();
    final isCached = cache.isTrackCached(track.id);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...ownTrackActions(ctx, track),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Убрать из медиатеки'),
              onTap: () async {
                Navigator.pop(ctx);
                await music.deleteTrack(track);
              },
            ),
            if (isCached)
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Удалить скачанный трек (кэш)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await cache.removeFromCache(track.id);
                  if (!context.mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Кэш трека очищен')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить кэш'),
        content: const Text('Удалить все скачанные треки с устройства?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<CacheService>().clearCache();
              if (!context.mounted) return;
              setState(() {});
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Кэш очищен')));
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }
}

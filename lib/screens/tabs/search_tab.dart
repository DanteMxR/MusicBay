import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/music_provider.dart';
import '../../services/cache_service.dart';
import '../../widgets/track_tile.dart';

class SearchTab extends StatefulWidget {
  final String? initialQuery;
  final bool artistOnly;
  final bool showScaffold;

  const SearchTab({
    super.key,
    this.initialQuery,
    this.artistOnly = false,
    this.showScaffold = true,
  });

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _initialSearchDone = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final music = context.read<MusicProvider>();
      if (widget.artistOnly) {
        music.searchArtistTracks(query);
      } else {
        music.searchAudio(query);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialSearchDone) return;

    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isEmpty) {
      _initialSearchDone = true;
      return;
    }

    _initialSearchDone = true;
    _searchController.text = initial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final music = context.read<MusicProvider>();
      if (widget.artistOnly) {
        music.searchArtistTracks(initial);
      } else {
        music.searchAudio(initial);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    final audio = context.watch<AudioProvider>();

    if (widget.showScaffold) {
      return Scaffold(
        appBar: AppBar(title: _buildSearchField(context)),
        body: _buildBody(music, audio),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _buildSearchField(context),
          ),
          Expanded(child: _buildBody(music, audio)),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Поиск музыки...',
        border: InputBorder.none,
        prefixIcon: Icon(
          Icons.search,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        isDense: true,
      ),
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildBody(MusicProvider music, AudioProvider audio) {
    if (music.searchQuery.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await music.loadRecommendations(refresh: true);
          await music.loadNewReleases(refresh: true);
          await music.loadPlaylists();
        },
        child: _buildSuggestions(music, audio),
      );
    }

    if (music.searchLoading && music.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (music.searchError != null && music.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text('Не удалось выполнить поиск'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (widget.artistOnly) {
                  music.searchArtistTracks(music.searchQuery);
                } else {
                  music.searchAudio(music.searchQuery);
                }
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (music.searchResults.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }

    final cache = context.read<CacheService>();
    final cachedKeys = <String>{
      for (final t in music.searchResults)
        if (cache.isTrackCached(t.id)) t.id,
    };

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >
            notification.metrics.maxScrollExtent -
                kSearchPaginationThresholdPx) {
          music.loadMoreSearch();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: music.searchResults.length,
        itemBuilder: (_, index) {
          final track = music.searchResults[index];
          final isPlaying = audio.isPlayingTrack(track);

          return TrackTile(
            track: track,
            isPlaying: isPlaying,
            isCached: cachedKeys.contains(track.id),
            trailing: _buildAddToLibraryButton(track),
            onTap: () => audio.playPauseTrack(
              track,
              music.searchResults,
              startIndex: index,
            ),
            onLongPress: () => _showAddDialog(track),
          );
        },
      ),
    );
  }

  Widget _buildSuggestions(MusicProvider music, AudioProvider audio) {
    final theme = Theme.of(context);

    if (music.recommendationsLoading &&
        music.newReleasesLoading &&
        music.recommendations.isEmpty &&
        music.newTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final cache = context.read<CacheService>();
    final newTracksLimit = music.newTracks.length < 20
        ? music.newTracks.length
        : 20;
    final recsLimit = music.recommendations.length < 30
        ? music.recommendations.length
        : 30;
    final cachedKeys = <String>{
      for (var i = 0; i < newTracksLimit; i++)
        if (cache.isTrackCached(music.newTracks[i].id)) music.newTracks[i].id,
      for (var i = 0; i < recsLimit; i++)
        if (cache.isTrackCached(music.recommendations[i].id))
          music.recommendations[i].id,
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (music.newTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Новые треки',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (var i = 0; i < newTracksLimit; i++)
            TrackTile(
              track: music.newTracks[i],
              isPlaying: audio.isPlayingTrack(music.newTracks[i]),
              isCached: cachedKeys.contains(music.newTracks[i].id),
              trailing: _buildAddToLibraryButton(music.newTracks[i]),
              onTap: () => audio.playPauseTrack(
                music.newTracks[i],
                music.newTracks,
                startIndex: i,
              ),
              onLongPress: () => _showAddDialog(music.newTracks[i]),
            ),
        ],
        if (music.recommendations.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Text(
              'Из твоей медиатеки',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (var i = 0; i < recsLimit; i++)
            TrackTile(
              track: music.recommendations[i],
              isPlaying: audio.isPlayingTrack(music.recommendations[i]),
              isCached: cachedKeys.contains(music.recommendations[i].id),
              trailing: _buildAddToLibraryButton(music.recommendations[i]),
              onTap: () => audio.playPauseTrack(
                music.recommendations[i],
                music.recommendations,
                startIndex: i,
              ),
              onLongPress: () => _showAddDialog(music.recommendations[i]),
            ),
        ],
        if (music.recommendations.isEmpty && music.newTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('Пока пусто. Загрузи музыку на вкладке «Моя музыка»'),
            ),
          ),
      ],
    );
  }

  void _showAddDialog(Track track) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.library_add),
              title: const Text('Добавить в мою музыку'),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<MusicProvider>().addTrack(track);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Трек добавлен')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Добавить в плейлист'),
              onTap: () async {
                Navigator.pop(ctx);
                await _showPlaylistPicker(track);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPlaylistPicker(Track track) async {
    final rootContext = context;
    final music = rootContext.read<MusicProvider>();
    if (music.playlists.isEmpty) {
      await music.loadPlaylists();
    }
    if (!mounted) return;

    if (music.playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Плейлисты не найдены')));
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 360,
          child: ListView.builder(
            itemCount: music.playlists.length,
            itemBuilder: (_, index) {
              final playlist = music.playlists[index];
              return ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(
                  playlist.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${playlist.count} треков'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final musicProvider = rootContext.read<MusicProvider>();
                  final messenger = ScaffoldMessenger.of(rootContext);
                  try {
                    await musicProvider.addTrackToPlaylist(track, playlist);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Добавлено в "${playlist.title}"'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Не удалось добавить: $e')),
                    );
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAddToLibraryButton(Track track) {
    final music = context.watch<MusicProvider>();
    final isSaved = music.isTrackSaved(track.id);

    return IconButton(
      tooltip: isSaved ? 'Уже в коллекции' : 'Добавить в коллекцию',
      icon: Icon(
        isSaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
      ),
      onPressed: () async {
        final added = await context.read<MusicProvider>().toggleSavedTrack(
          track,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
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

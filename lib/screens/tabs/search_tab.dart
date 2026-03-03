import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/vk_provider.dart';
import '../../providers/audio_provider.dart';
import '../../widgets/track_tile.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      context.read<VkProvider>().searchAudio(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vk = context.watch<VkProvider>();
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
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
        ),
      ),
      body: _buildBody(vk, audio),
    );
  }

  Widget _buildBody(VkProvider vk, AudioProvider audio) {
    if (vk.searchQuery.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await vk.loadRecommendations(refresh: true);
          await vk.loadNewReleases(refresh: true);
          await vk.loadPlaylists();
        },
        child: _buildSuggestions(vk, audio),
      );
    }

    if (vk.searchLoading && vk.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vk.searchResults.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >
            notification.metrics.maxScrollExtent - 200) {
          vk.loadMoreSearch();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: vk.searchResults.length,
        itemBuilder: (_, index) {
          final track = vk.searchResults[index];
          final isPlaying = audio.currentTrack?.id == track.id;

          return TrackTile(
            track: track,
            isPlaying: isPlaying,
            trailing: _buildAddToLibraryButton(track),
            onTap: () {
              audio.playPlaylist(vk.searchResults, startIndex: index);
            },
            onLongPress: () => _showAddDialog(track),
          );
        },
      ),
    );
  }

  Widget _buildSuggestions(VkProvider vk, AudioProvider audio) {
    final theme = Theme.of(context);

    if (vk.recommendationsLoading &&
        vk.newReleasesLoading &&
        vk.recommendations.isEmpty &&
        vk.newTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (vk.newTracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Новые треки',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...vk.newTracks.take(20).map((track) {
            final index = vk.newTracks.indexOf(track);
            final isPlaying = audio.currentTrack?.id == track.id;
            return TrackTile(
              track: track,
              isPlaying: isPlaying,
              trailing: _buildAddToLibraryButton(track),
              onTap: () => audio.playPlaylist(vk.newTracks, startIndex: index),
              onLongPress: () => _showAddDialog(track),
            );
          }),
        ],
        if (vk.recommendations.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Text(
              'Рекомендации для тебя',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...vk.recommendations.take(30).map((track) {
            final index = vk.recommendations.indexOf(track);
            final isPlaying = audio.currentTrack?.id == track.id;
            return TrackTile(
              track: track,
              isPlaying: isPlaying,
              trailing: _buildAddToLibraryButton(track),
              onTap: () =>
                  audio.playPlaylist(vk.recommendations, startIndex: index),
              onLongPress: () => _showAddDialog(track),
            );
          }),
        ],
        if (vk.recommendations.isEmpty && vk.newTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('Пока нет рекомендаций')),
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
                await context.read<VkProvider>().addTrack(track);
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
    final vk = rootContext.read<VkProvider>();
    if (vk.playlists.isEmpty) {
      await vk.loadPlaylists();
    }
    if (!mounted) return;

    if (vk.playlists.isEmpty) {
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
            itemCount: vk.playlists.length,
            itemBuilder: (_, index) {
              final playlist = vk.playlists[index];
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
                  final vkProvider = rootContext.read<VkProvider>();
                  final messenger = ScaffoldMessenger.of(rootContext);
                  try {
                    await vkProvider.addTrackToPlaylist(track, playlist);
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
    final vk = context.watch<VkProvider>();
    final isSaved = vk.isTrackSaved(track.id, ownerId: track.ownerId);

    return IconButton(
      tooltip: isSaved ? 'Уже в коллекции' : 'Добавить в коллекцию',
      icon: Icon(
        isSaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
      ),
      onPressed: () async {
        final added = await context.read<VkProvider>().toggleSavedTrack(track);
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

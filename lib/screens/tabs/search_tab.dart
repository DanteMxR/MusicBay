import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    _debounce = Timer(const Duration(milliseconds: 500), () {
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
          decoration: const InputDecoration(
            hintText: 'Поиск музыки...',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      body: _buildBody(vk, audio),
    );
  }

  Widget _buildBody(VkProvider vk, AudioProvider audio) {
    // Show recommendations when no search
    if (vk.searchQuery.isEmpty) {
      return _buildRecommendations(vk, audio);
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
        itemBuilder: (context, index) {
          final track = vk.searchResults[index];
          final isPlaying = audio.currentTrack?.id == track.id;

          return TrackTile(
            track: track,
            isPlaying: isPlaying,
            onTap: () {
              audio.playPlaylist(vk.searchResults, startIndex: index);
            },
            onLongPress: () => _showAddDialog(track),
          );
        },
      ),
    );
  }

  Widget _buildRecommendations(VkProvider vk, AudioProvider audio) {
    if (vk.recommendationsLoading && vk.recommendations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vk.recommendations.isEmpty) {
      return const Center(child: Text('Нет рекомендаций'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Рекомендации',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: vk.recommendations.length,
            itemBuilder: (context, index) {
              final track = vk.recommendations[index];
              final isPlaying = audio.currentTrack?.id == track.id;

              return TrackTile(
                track: track,
                isPlaying: isPlaying,
                onTap: () {
                  audio.playPlaylist(vk.recommendations, startIndex: index);
                },
                onLongPress: () => _showAddDialog(track),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddDialog(dynamic track) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Добавить в мою музыку'),
              onTap: () {
                Navigator.pop(ctx);
                context.read<VkProvider>().addTrack(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Трек добавлен')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

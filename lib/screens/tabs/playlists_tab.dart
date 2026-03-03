import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/vk_provider.dart';
import '../../models/playlist.dart';
import '../playlist_detail_screen.dart';

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vk = context.watch<VkProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Плейлисты')),
      body: RefreshIndicator(
        onRefresh: () => vk.loadPlaylists(),
        child: _buildBody(context, vk),
      ),
    );
  }

  Widget _buildBody(BuildContext context, VkProvider vk) {
    if (vk.playlistsLoading && vk.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vk.playlists.isEmpty) {
      return const Center(child: Text('Нет плейлистов'));
    }

    return ListView.builder(
      itemCount: vk.playlists.length,
      itemBuilder: (context, index) {
        final playlist = vk.playlists[index];
        return _PlaylistTile(
          playlist: playlist,
          onTap: () => _openPlaylist(context, playlist),
        );
      },
    );
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlist: playlist),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: playlist.photo != null
              ? CachedNetworkImage(imageUrl: playlist.photo!, fit: BoxFit.cover)
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.playlist_play, size: 28),
                ),
        ),
      ),
      title: Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${playlist.count} треков'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_provider.dart';
import '../../models/playlist.dart';
import '../playlist_detail_screen.dart';
import '../../widgets/track_dialogs.dart';

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Плейлисты')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Новый плейлист',
        onPressed: () => _createPlaylist(context),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => music.loadPlaylists(),
        child: _buildBody(context, music),
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final music = context.read<MusicProvider>();
    final title = await askText(
      context,
      title: 'Новый плейлист',
      label: 'Название',
      action: 'Создать',
    );
    if (title == null || !context.mounted) return;
    await runAndReport(context, () => music.createPlaylist(title));
  }

  void _showPlaylistMenu(BuildContext context, Playlist playlist) {
    final music = context.read<MusicProvider>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () async {
                Navigator.pop(ctx);
                final title = await askText(
                  context,
                  title: 'Переименовать',
                  label: 'Название',
                  action: 'Сохранить',
                  initial: playlist.title,
                );
                if (title == null || !context.mounted) return;
                await runAndReport(
                  context,
                  () => music.renamePlaylist(playlist, title),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await askConfirmation(
                  context,
                  title: 'Удалить плейлист',
                  message: 'Удалить плейлист «${playlist.title}»?',
                  action: 'Удалить',
                );
                if (!confirmed || !context.mounted) return;
                await runAndReport(
                  context,
                  () => music.deletePlaylist(playlist),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MusicProvider music) {
    if (music.playlistsLoading && music.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: music.playlists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            leading: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.favorite, size: 28),
            ),
            title: const Text('Любимые'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPlaylist(context, Playlist.liked()),
          );
        }
        final playlist = music.playlists[index - 1];
        return _PlaylistTile(
          playlist: playlist,
          onTap: () => _openPlaylist(context, playlist),
          onLongPress: () => _showPlaylistMenu(context, playlist),
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
  final VoidCallback onLongPress;

  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
    required this.onLongPress,
  });

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
      onLongPress: onLongPress,
    );
  }
}

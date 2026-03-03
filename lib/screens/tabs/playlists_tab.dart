import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/vk_provider.dart';
import '../../providers/audio_provider.dart';
import '../../models/playlist.dart';
import '../../widgets/track_tile.dart';
import '../../models/track.dart';

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
        builder: (_) => _PlaylistDetailScreen(playlist: playlist),
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
              ? CachedNetworkImage(
                  imageUrl: playlist.photo!,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.playlist_play, size: 28),
                ),
        ),
      ),
      title: Text(
        playlist.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${playlist.count} треков'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const _PlaylistDetailScreen({required this.playlist});

  @override
  State<_PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<_PlaylistDetailScreen> {
  List<Track> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final vk = context.read<VkProvider>();
    try {
      final tracks = await vk.loadPlaylistTracks(
        widget.playlist.ownerId,
        widget.playlist.id,
      );
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? const Center(child: Text('Плейлист пуст'))
              : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final track = _tracks[index];
                    final isPlaying = audio.currentTrack?.id == track.id;

                    return TrackTile(
                      track: track,
                      isPlaying: isPlaying,
                      onTap: () {
                        audio.playPlaylist(_tracks, startIndex: index);
                      },
                    );
                  },
                ),
    );
  }
}

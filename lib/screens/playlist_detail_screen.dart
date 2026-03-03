import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/audio_provider.dart';
import '../providers/vk_provider.dart';
import '../services/cache_service.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
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
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.title),
        actions: [
          IconButton(
            tooltip: 'Сохранить альбом',
            icon: const Icon(Icons.library_add),
            onPressed: _loading || _tracks.isEmpty ? null : _saveAlbumToLibrary,
          ),
          IconButton(
            tooltip: 'Скачать 100',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: _loading || _tracks.isEmpty
                ? null
                : _downloadLatestHundred,
          ),
        ],
      ),
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
                  trailing: IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    onPressed: () => _saveSingleTrack(track),
                    tooltip: 'Сохранить трек',
                  ),
                );
              },
            ),
    );
  }

  Future<void> _saveSingleTrack(Track track) async {
    final vk = context.read<VkProvider>();
    await vk.addTrack(track);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Трек сохранен')));
  }

  Future<void> _saveAlbumToLibrary() async {
    final vk = context.read<VkProvider>();
    final added = await vk.saveTracksToMyLibrary(_tracks);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Сохранено треков: $added')));
  }

  Future<void> _downloadLatestHundred() async {
    final cache = context.read<CacheService>();
    final latest = _tracks.take(100).toList();
    final cached = await cache.cacheTracksIfNeeded(latest, maxToDownload: 100);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Скачано треков: $cached')));
  }
}

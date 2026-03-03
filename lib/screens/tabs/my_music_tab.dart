import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/vk_provider.dart';
import '../../providers/audio_provider.dart';
import '../../widgets/track_tile.dart';

class MyMusicTab extends StatelessWidget {
  const MyMusicTab({super.key});

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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >
            notification.metrics.maxScrollExtent - 200) {
          vk.loadMyTracks();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: vk.myTracks.length + (vk.myTracksLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= vk.myTracks.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final track = vk.myTracks[index];
          final isPlaying = audio.currentTrack?.id == track.id;

          return TrackTile(
            track: track,
            isPlaying: isPlaying,
            onTap: () {
              audio.playPlaylist(vk.myTracks, startIndex: index);
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

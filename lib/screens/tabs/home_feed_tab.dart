import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/vk_provider.dart';
import '../../screens/playlist_detail_screen.dart';
import '../../widgets/artwork_image.dart';
import '../../widgets/track_tile.dart';

class HomeFeedTab extends StatefulWidget {
  const HomeFeedTab({super.key});

  @override
  State<HomeFeedTab> createState() => _HomeFeedTabState();
}

class _HomeFeedTabState extends State<HomeFeedTab> {
  String? _selectedArtist;

  @override
  Widget build(BuildContext context) {
    final vk = context.watch<VkProvider>();
    final audio = context.watch<AudioProvider>();
    final theme = Theme.of(context);

    final dailyTracks = _uniqueTracks(vk.recommendations).take(24).toList();
    final freshTracks = _uniqueTracks(vk.newTracks).take(30).toList();
    final allForArtists = _uniqueTracks([...dailyTracks, ...freshTracks]);

    final artistMap = <String, List<Track>>{};
    for (final track in allForArtists) {
      artistMap.putIfAbsent(track.artist, () => []).add(track);
    }
    final artists = artistMap.keys.toList();
    final artistTracks = _selectedArtist != null
        ? (artistMap[_selectedArtist!] ?? const <Track>[])
        : const <Track>[];

    // Альбомы скрыты, т.к. VK API не возвращает информацию об альбомах
    // final releaseCards = <Track>[];
    // final releaseSeen = <String>{};
    // for (final t in freshTracks) {
    //   final key = '${t.artist}_${t.albumId ?? t.id}_${t.albumThumb ?? ''}';
    //   if (releaseSeen.add(key)) {
    //     releaseCards.add(t);
    //   }
    //   if (releaseCards.length >= 12) break;
    // }

    return Scaffold(
      appBar: AppBar(title: const Text('Главная')),
      body: RefreshIndicator(
        onRefresh: () async {
          await vk.loadRecommendations(refresh: true);
          await vk.loadNewReleases(refresh: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.26),
                    theme.colorScheme.surfaceContainerHigh,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Рекомендации дня',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Подборка под твой вкус на сегодня',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (artists.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text(
                  'Выбор по артистам',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: artists.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final artist = artists[i];
                    return ChoiceChip(
                      label: Text(artist),
                      selected: _selectedArtist == artist,
                      onSelected: (_) {
                        setState(() {
                          _selectedArtist = _selectedArtist == artist
                              ? null
                              : artist;
                        });
                      },
                    );
                  },
                ),
              ),
              if (_selectedArtist != null)
                ...artistTracks.take(8).map((track) {
                  final index = artistTracks.indexOf(track);
                  return TrackTile(
                    track: track,
                    isPlaying:
                        audio.currentTrack?.id == track.id &&
                        audio.currentTrack?.ownerId == track.ownerId,
                    trailing: _buildAddToLibraryButton(context, track),
                    onTap: () =>
                        audio.playPauseTrack(track, artistTracks, startIndex: index),
                  );
                }),
            ],
            // Альбомы скрыты, т.к. VK API не возвращает информацию об альбомах в рекомендациях
            // if (releaseCards.isNotEmpty) ...[
            //   Padding(
            //     padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            //     child: Text(
            //       'Новые альбомы и релизы',
            //       style: theme.textTheme.titleMedium?.copyWith(
            //         fontWeight: FontWeight.bold,
            //       ),
            //     ),
            //   ),
            //   SizedBox(
            //     height: 218,
            //     child: ListView.separated(
            //       scrollDirection: Axis.horizontal,
            //       padding: const EdgeInsets.symmetric(horizontal: 16),
            //       itemCount: releaseCards.length,
            //       separatorBuilder: (_, _) => const SizedBox(width: 12),
            //       itemBuilder: (_, i) {
            //         final track = releaseCards[i];
            //         final title = track.title;
            //         final subtitle = track.artist;
            //         return InkWell(
            //           borderRadius: BorderRadius.circular(14),
            //           onTap: () {
            //             if (track.albumId != null && track.albumOwnerId != null) {
            //               Navigator.of(context).push(
            //                 MaterialPageRoute(
            //                   builder: (_) => PlaylistDetailScreen(
            //                     playlist: Playlist(
            //                       id: track.albumId!,
            //                       ownerId: track.albumOwnerId!,
            //                       title: track.albumTitle ?? track.title,
            //                       count: 0,
            //                       createTime: 0,
            //                       updateTime: 0,
            //                       photo: track.albumThumb,
            //                     ),
            //                   ),
            //                 ),
            //               );
            //             } else {
            //               final list = freshTracks
            //                   .where((t) => t.artist == track.artist)
            //                   .toList();
            //               final start = list.indexWhere(
            //                 (t) => t.id == track.id && t.ownerId == track.ownerId,
            //               );
            //               audio.playPauseTrack(
            //                 track,
            //                 list.isNotEmpty ? list : freshTracks,
            //                 startIndex: start >= 0 ? start : 0,
            //               );
            //             }
            //           },
            //           child: SizedBox(
            //             width: 150,
            //             child: Column(
            //               crossAxisAlignment: CrossAxisAlignment.start,
            //               children: [
            //                 ClipRRect(
            //                   borderRadius: BorderRadius.circular(14),
            //                   child: SizedBox(
            //                     width: 150,
            //                     height: 150,
            //                     child: ArtworkImage(
            //                       track: track,
            //                       width: 150,
            //                       height: 150,
            //                       placeholder: Container(
            //                         color: theme
            //                             .colorScheme
            //                             .surfaceContainerHighest,
            //                         child: const Icon(
            //                           Icons.album_outlined,
            //                           size: 34,
            //                         ),
            //                       ),
            //                     ),
            //                   ),
            //                 ),
            //                 const SizedBox(height: 8),
            //                 Text(
            //                   title,
            //                   maxLines: 1,
            //                   overflow: TextOverflow.ellipsis,
            //                   style: theme.textTheme.bodyMedium?.copyWith(
            //                     fontWeight: FontWeight.w700,
            //                   ),
            //                 ),
            //                 const SizedBox(height: 2),
            //                 Text(
            //                   subtitle,
            //                   maxLines: 1,
            //                   overflow: TextOverflow.ellipsis,
            //                   style: theme.textTheme.bodySmall?.copyWith(
            //                     color: theme.colorScheme.onSurfaceVariant,
            //                   ),
            //                 ),
            //               ],
            //             ),
            //           ),
            //         );
            //       },
            //     ),
            //   ),
            // ],
            if (dailyTracks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Text(
                  'Для тебя сегодня',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...dailyTracks.take(10).map((track) {
                final index = dailyTracks.indexOf(track);
                return TrackTile(
                  track: track,
                  isPlaying:
                      audio.currentTrack?.id == track.id &&
                      audio.currentTrack?.ownerId == track.ownerId,
                  trailing: _buildAddToLibraryButton(context, track),
                  onTap: () =>
                      audio.playPauseTrack(track, dailyTracks, startIndex: index),
                );
              }),
            ],
            if (dailyTracks.isEmpty && freshTracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('Пока нет рекомендаций')),
              ),
          ],
        ),
      ),
    );
  }

  List<Track> _uniqueTracks(List<Track> tracks) {
    final byKey = <String, Track>{};
    for (final track in tracks) {
      byKey['${track.ownerId}_${track.id}'] = track;
    }
    return byKey.values.toList();
  }

  Widget _buildAddToLibraryButton(BuildContext context, Track track) {
    final vk = context.read<VkProvider>();
    final isSaved = vk.isTrackSaved(track.id, ownerId: track.ownerId);

    return IconButton(
      tooltip: isSaved ? 'Уже в коллекции' : 'Добавить в коллекцию',
      icon: Icon(
        isSaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
      ),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final added = await vk.toggleSavedTrack(track);
        if (!mounted) return;
        messenger.showSnackBar(
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

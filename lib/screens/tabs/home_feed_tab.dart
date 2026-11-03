import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/music_provider.dart';
import '../../screens/generated_album_screen.dart';
import '../../services/cache_service.dart';
import '../../widgets/artwork_image.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/theme_mode_menu.dart';

class HomeFeedTab extends StatefulWidget {
  const HomeFeedTab({super.key});

  @override
  State<HomeFeedTab> createState() => _HomeFeedTabState();
}

class _HomeFeedTabState extends State<HomeFeedTab> {
  String? _selectedArtist;
  int _albumSeed = DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    final audio = context.watch<AudioProvider>();
    final cache = context.read<CacheService>();
    final theme = Theme.of(context);

    final dailyMix = _uniqueTracks(
      music.dailyMix.isNotEmpty ? music.dailyMix : music.recommendations,
    );
    final freshTracks = _uniqueTracks(music.newTracks);
    final allForArtists = _uniqueTracks([...dailyMix, ...freshTracks]);
    final forToday = _uniqueTracks([
      ...dailyMix,
      ...music.recommendations,
      ...freshTracks,
      ...music.myTracks,
    ]).take(50).toList(growable: false);

    final cachedKeys = <String>{
      for (final t in forToday)
        if (cache.isTrackCached(t.id)) t.id,
    };

    final generatedAlbums = _buildGeneratedAlbums([
      ...music.myTracks,
      ...music.recommendations,
    ], _albumSeed);

    final artistMap = <String, List<Track>>{};
    for (final track in allForArtists) {
      artistMap.putIfAbsent(track.artist, () => []).add(track);
    }
    final artists = artistMap.keys.take(12).toList(growable: false);
    final artistTracks = _selectedArtist != null
        ? (artistMap[_selectedArtist!] ?? const <Track>[])
        : const <Track>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: const [ThemeModeMenuButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () => music.loadDiscovery(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _buildHero(theme, forToday.length),
            if (generatedAlbums.isNotEmpty) ...[
              const _SectionTitle(
                title: 'Альбомы дня',
                subtitle: 'Собрано из ваших треков',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _albumSeed = DateTime.now().millisecondsSinceEpoch,
                    ),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Пересобрать'),
                  ),
                ),
              ),
              SizedBox(
                height: 214,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: generatedAlbums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final album = generatedAlbums[i];
                    final firstTrack = album.tracks.first;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GeneratedAlbumScreen(
                            title: album.title,
                            subtitle: album.subtitle,
                            tracks: album.tracks,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        width: 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                width: 150,
                                height: 150,
                                child: ArtworkImage(
                                  track: firstTrack,
                                  width: 150,
                                  height: 150,
                                  placeholder: Container(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: const Icon(
                                      Icons.album_outlined,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${album.tracks.length} треков',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (dailyMix.isNotEmpty) ...[
              _SectionTitle(
                title: 'Микс дня',
                subtitle:
                    'Собрано из твоей медиатеки и публичных треков твоих артистов',
              ),
              SizedBox(
                height: 210,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: dailyMix.length < 12 ? dailyMix.length : 12,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final track = dailyMix[i];
                    return _MixTrackCard(
                      track: track,
                      onTap: () =>
                          audio.playPauseTrack(track, dailyMix, startIndex: i),
                    );
                  },
                ),
              ),
            ],
            if (artists.isNotEmpty) ...[
              const _SectionTitle(
                title: 'По артистам',
                subtitle: 'Выберите настроение через любимых исполнителей',
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
                for (var i = 0; i < artistTracks.length && i < 8; i++)
                  TrackTile(
                    track: artistTracks[i],
                    isPlaying: audio.currentTrack?.id == artistTracks[i].id,
                    isCached: cachedKeys.contains(artistTracks[i].id),
                    trailing: _buildAddToLibraryButton(
                      context,
                      artistTracks[i],
                    ),
                    onTap: () => audio.playPauseTrack(
                      artistTracks[i],
                      artistTracks,
                      startIndex: i,
                    ),
                  ),
            ],
            if (forToday.isNotEmpty) ...[
              const _SectionTitle(
                title: 'Для тебя сегодня',
                subtitle: 'Полный список микса дня',
              ),
              for (var i = 0; i < forToday.length; i++)
                TrackTile(
                  track: forToday[i],
                  isPlaying: audio.currentTrack?.id == forToday[i].id,
                  isCached: cachedKeys.contains(forToday[i].id),
                  trailing: _buildAddToLibraryButton(context, forToday[i]),
                  onTap: () => audio.playPauseTrack(
                    forToday[i],
                    forToday,
                    startIndex: i,
                  ),
                ),
            ],
            if (music.discoveryLoading && dailyMix.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!music.discoveryLoading &&
                dailyMix.isEmpty &&
                freshTracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Пока пусто. Загрузи музыку на вкладке «Моя музыка»',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_GeneratedAlbum> _buildGeneratedAlbums(List<Track> rawTracks, int seed) {
    final tracks = _uniqueTracks(
      rawTracks,
    ).where((t) => t.url.isNotEmpty).toList();
    if (tracks.length < 6) return const [];

    final result = <_GeneratedAlbum>[];
    final random = Random(seed);

    final randomTracks = List<Track>.from(tracks)..shuffle(random);
    for (var i = 0; i < 3; i++) {
      final start = i * 18;
      if (start >= randomTracks.length) break;
      final end = (start + 18).clamp(0, randomTracks.length);
      final part = randomTracks.sublist(start, end);
      if (part.length >= 8) {
        result.add(
          _GeneratedAlbum(
            title: 'Альбом дня ${i + 1}',
            subtitle: 'Автосборка из вашей медиатеки',
            tracks: part,
          ),
        );
      }
    }

    final byArtist = <String, List<Track>>{};
    for (final track in tracks) {
      byArtist.putIfAbsent(track.artist, () => []).add(track);
    }
    final artistEntries = byArtist.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    for (final entry in artistEntries) {
      if (entry.value.length < 3) continue;
      final list = List<Track>.from(entry.value)
        ..shuffle(Random(seed ^ entry.key.hashCode));
      result.add(
        _GeneratedAlbum(
          title: 'Подборка: ${entry.key}',
          subtitle: 'Собрано по исполнителю',
          tracks: list.toList(growable: false),
        ),
      );
    }

    return result;
  }

  Widget _buildHero(ThemeData theme, int mixCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.30),
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
            'Твой музыкальный день',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Обновляемый ежедневный микс и локальные альбомы',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Chip(
            avatar: const Icon(Icons.auto_awesome, size: 16),
            label: Text('Микс: $mixCount'),
          ),
        ],
      ),
    );
  }

  List<Track> _uniqueTracks(List<Track> tracks) {
    final byKey = <String, Track>{};
    for (final track in tracks) {
      byKey[track.id] = track;
    }
    return byKey.values.toList(growable: false);
  }

  Widget _buildAddToLibraryButton(BuildContext context, Track track) {
    final music = context.read<MusicProvider>();
    final isSaved = music.isTrackSaved(track.id);

    return IconButton(
      tooltip: isSaved ? 'Уже в коллекции' : 'Добавить в коллекцию',
      icon: Icon(
        isSaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
      ),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final added = await music.toggleSavedTrack(track);
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

class _GeneratedAlbum {
  final String title;
  final String subtitle;
  final List<Track> tracks;

  const _GeneratedAlbum({
    required this.title,
    required this.subtitle,
    required this.tracks,
  });
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MixTrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  const _MixTrackCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 150,
                height: 150,
                child: ArtworkImage(
                  track: track,
                  width: 150,
                  height: 150,
                  placeholder: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.music_note, size: 30),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

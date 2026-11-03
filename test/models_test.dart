import 'package:flutter_test/flutter_test.dart';
import 'package:musicbay/models/playlist.dart';
import 'package:musicbay/models/track.dart';

void main() {
  const id = '01a19df4-0230-7574-b8fa-2341f1305f59';

  Map<String, dynamic> readyTrack({int? expires}) => {
    'id': id,
    'title': 'Tone',
    'artist': {'id': 'a1', 'name': 'Artist'},
    'album': {'id': 'b1', 'name': 'Album'},
    'duration_ms': 185400,
    'status': 'ready',
    'error': null,
    'visibility': 'public',
    'plays': 3,
    'streams': {
      'low': {'url': 'https://s/stream/$id?q=low&exp=1&sig=a'},
      'normal': {
        'url': 'https://s/stream/$id?q=normal&exp=${expires ?? 1}&sig=b',
      },
    },
    'covers': {'128': 'https://s/covers/128', '600': 'https://s/covers/600'},
  };

  group('Track', () {
    test('reads an answer of the server and prefers normal quality', () {
      final track = Track.fromJson(readyTrack());

      expect(track.id, id);
      expect(track.artist, 'Artist');
      expect(track.albumId, 'b1');
      expect(track.albumTitle, 'Album');
      expect(track.duration, 185);
      expect(track.url, contains('q=normal'));
      expect(track.albumThumb, 'https://s/covers/600');
      expect(track.plays, 3);
    });

    test('plays the preferred quality or the closest it has', () {
      addTearDown(() => Track.preferredQuality = 'normal');
      final track = Track.fromJson(readyTrack());

      Track.preferredQuality = 'low';
      expect(track.url, contains('q=low'));
      Track.preferredQuality = 'lossless';
      expect(track.url, startsWith('https://s/stream'));
      expect(track.copyWithUrl('/data/a.audio').url, '/data/a.audio');
    });

    test('a track being processed has nothing to play yet', () {
      final track = Track.fromJson({
        'id': id,
        'title': 'Tone',
        'artist': null,
        'album': null,
        'duration_ms': null,
        'status': 'pending',
        'streams': null,
        'covers': null,
      });

      expect(track.url, isEmpty);
      expect(track.albumThumb, isNull);
      expect(track.duration, 0);
      expect(track.status, 'pending');
      expect(track.isProcessing, true);
    });

    test('survives being kept on disk', () {
      final track = Track.fromJson(readyTrack());
      final restored = Track.fromCache(track.toJson());

      expect(restored.id, track.id);
      expect(restored.url, track.url);
      expect(restored.artistId, track.artistId);
      expect(restored.albumTitle, track.albumTitle);
      expect(restored.visibility, track.visibility);
    });

    test('knows when its link has run out', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(
        Track.fromJson(readyTrack(expires: now + 3600)).isLinkStale,
        false,
      );
      expect(Track.fromJson(readyTrack(expires: now + 60)).isLinkStale, true);
      expect(
        Track.fromJson(
          readyTrack(),
        ).copyWithUrl('/data/track.audio').isLinkStale,
        false,
      );
    });
  });

  test('Playlist reads an answer of the server', () {
    final playlist = Playlist.fromJson({
      'id': 'p1',
      'owner_id': 'u1',
      'title': 'Road',
      'track_count': 7,
    });

    expect(playlist.id, 'p1');
    expect(playlist.count, 7);
    expect(playlist.isOwn, true);
  });
}

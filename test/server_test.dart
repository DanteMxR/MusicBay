// Goes through a real server with the code of the app. It needs a running server and a file:
//   flutter test test/server_test.dart --dart-define=TEST_SERVER=http://localhost:8080 --dart-define=TEST_AUDIO=path/to/file.mp3
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicbay/models/track.dart';
import 'package:musicbay/services/api_service.dart';

const server = String.fromEnvironment('TEST_SERVER');
const audio = String.fromEnvironment('TEST_AUDIO');

class MemoryStore implements SessionStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}

Future<Track> waitUntilReady(ApiService api, String id) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final track = await api.getTrack(id);
    if (track.status == 'ready') return track;
    if (track.status == 'failed') fail('the track failed');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('the track is not ready in time');
}

void main() {
  final skip = server.isEmpty || audio.isEmpty
      ? 'needs TEST_SERVER and TEST_AUDIO'
      : null;

  test(
    'the way of a user',
    () async {
      final store = MemoryStore();
      final api = ApiService(store);
      final name = 'app${DateTime.now().millisecondsSinceEpoch}';
      const password = 'long-enough-password';

      await expectLater(
        api.login(server, name, password),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );

      await api.register('$server/', name, password);
      expect(api.isAuthorized, true);
      expect(store.values['server_url'], server);

      final accepted = await api.uploadFile(
        File(audio),
        visibility: 'public',
        onProgress: (progress) => expect(progress, inInclusiveRange(0, 1)),
      );
      final track = await waitUntilReady(api, accepted.id);
      expect(track.url, startsWith('http'));
      expect(track.isLinkStale, false);
      expect(track.duration, greaterThan(0));

      final stream = await Dio().get<List<int>>(
        track.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-1023'},
        ),
      );
      expect(stream.statusCode, 206);
      expect(stream.data, hasLength(1024));

      await api.addToLibrary(track.id);
      final library = await api.getLibrary();
      expect(library.items.map((t) => t.id), contains(track.id));

      await api.reportPlay(track.id);

      expect(await api.getMe(), name);
      final quota = await api.getQuota();
      expect(quota.usedBytes, greaterThanOrEqualTo(0));
      expect(quota.quotaBytes, greaterThan(0));
      final devices = await api.getDevices();
      expect(devices.single.current, true);

      await api.like(track.id);
      expect((await api.getLikes()).single.id, track.id);
      expect((await api.getTrack(track.id)).liked, true);
      await api.unlike(track.id);
      expect(await api.getLikes(), isEmpty);

      final renamed = await api.updateTrack(
        track.id,
        title: 'Title $name',
        artist: 'Artist $name',
        album: 'Album $name',
      );
      expect(renamed.title, 'Title $name');
      expect(renamed.artist, 'Artist $name');
      expect(renamed.albumTitle, 'Album $name');
      final album = await api.getAlbumTracks(renamed.albumId!);
      expect(album.single.id, track.id);

      final playlist = await api.createPlaylist('Road');
      await api.addTrackToPlaylist(playlist.id, track.id);
      expect(
        (await api.getPlaylists()).map((p) => p.id),
        contains(playlist.id),
      );
      final inPlaylist = await api.getPlaylistTracks(playlist.id);
      expect(inPlaylist.single.id, track.id);
      await api.renamePlaylist(playlist.id, 'Home');
      expect((await api.getPlaylists()).single.title, 'Home');
      await api.removeFromPlaylist(playlist.id, track.id);
      expect(await api.getPlaylistTracks(playlist.id), isEmpty);
      await api.deletePlaylist(playlist.id);
      expect(await api.getPlaylists(), isEmpty);

      // A new track takes up to 5 s to show up in search.
      await Future<void>.delayed(const Duration(seconds: 6));
      final found = await api.search('Title $name');
      expect(found.items.map((t) => t.id), contains(track.id));

      await api.removeFromLibrary(track.id);
      expect((await api.getLibrary()).items, isEmpty);

      // A dead access token is replaced without anyone noticing, also by requests at once.
      store.values['access_token'] = 'not-a-token';
      final restarted = ApiService(store);
      await restarted.init();
      expect(restarted.isAuthorized, true);
      final together = await Future.wait([
        restarted.getLibrary(),
        restarted.getPlaylists(),
        restarted.getTrack(track.id),
      ]);
      expect(together, hasLength(3));
      expect(store.values['access_token'], isNot('not-a-token'));

      // A session that the server has ended sends the user to the login screen.
      var expired = false;
      final oldRefresh = store.values['refresh_token']!;
      await restarted.getTrack(track.id);
      store.values['access_token'] = 'not-a-token';
      store.values['refresh_token'] = '$oldRefresh-broken';
      final ended = ApiService(store)..onSessionExpired = () => expired = true;
      await ended.init();
      await expectLater(ended.getLibrary(), throwsA(isA<ApiException>()));
      expect(expired, true);
      expect(ended.isAuthorized, false);
      expect(store.values.containsKey('refresh_token'), false);

      // Logging in again, and logging out ends the session on the server too.
      final again = ApiService(store);
      await again.init();
      await again.login(server, name, password);
      final other = await again.getTrack(track.id);
      await again.updateTrack(other.id, visibility: 'private');
      expect((await again.getTrack(track.id)).visibility, 'private');
      final refresh = store.values['refresh_token']!;
      await expectLater(
        ApiService(MemoryStore()).login(server, 'x', 'y'),
        throwsA(isA<ApiException>()),
      );
      await again.deleteTrack(track.id);
      await expectLater(
        again.getTrack(track.id),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
      await again.logout();
      expect(again.isAuthorized, false);
      await expectLater(
        Dio().post(
          '$server/api/v1/auth/refresh',
          data: {'refresh_token': refresh},
        ),
        throwsA(isA<DioException>()),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

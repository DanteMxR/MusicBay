import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/vk_api_service.dart';

class VkProvider extends ChangeNotifier {
  final VkApiService _api;

  VkProvider(this._api);

  VkApiService get api => _api;

  bool get isAuthorized => _api.isAuthorized;

  // My Audio
  List<Track> _myTracks = [];
  final Set<String> _savedTrackKeys = {};
  bool _myTracksLoading = false;
  bool _myTracksHasMore = true;
  String? _myTracksError;

  List<Track> get myTracks => _myTracks;
  bool get myTracksLoading => _myTracksLoading;
  bool get myTracksHasMore => _myTracksHasMore;
  String? get myTracksError => _myTracksError;
  bool isTrackSaved(int trackId, {int? ownerId}) {
    if (ownerId == null) {
      return _savedTrackKeys.any((k) => k.endsWith('_$trackId'));
    }
    return _savedTrackKeys.contains(_trackKey(trackId, ownerId));
  }

  // Search
  List<Track> _searchResults = [];
  bool _searchLoading = false;
  String _searchQuery = '';

  List<Track> get searchResults => _searchResults;
  bool get searchLoading => _searchLoading;
  String get searchQuery => _searchQuery;

  // Recommendations
  List<Track> _recommendations = [];
  bool _recommendationsLoading = false;

  List<Track> get recommendations => _recommendations;
  bool get recommendationsLoading => _recommendationsLoading;

  // Fresh recommendations
  List<Track> _newTracks = [];
  List<Playlist> _newAlbums = [];
  bool _newReleasesLoading = false;

  List<Track> get newTracks => _newTracks;
  List<Playlist> get newAlbums => _newAlbums;
  bool get newReleasesLoading => _newReleasesLoading;

  // Discovery
  List<Track> _dailyMix = [];
  Playlist? _albumOfDay;
  bool _discoveryLoading = false;
  String? _discoveryDateKey;
  List<Playlist> _popularAlbums = [];
  final Map<String, List<Playlist>> _artistAlbumsCache = {};
  final Set<String> _artistAlbumsLoading = {};

  List<Track> get dailyMix => _dailyMix;
  Playlist? get albumOfDay => _albumOfDay;
  bool get discoveryLoading => _discoveryLoading;
  List<Playlist> get popularAlbums => _popularAlbums;
  List<Playlist> artistAlbums(String artist) =>
      _artistAlbumsCache[artist] ?? const <Playlist>[];
  bool isArtistAlbumsLoading(String artist) =>
      _artistAlbumsLoading.contains(artist);

  // Playlists
  List<Playlist> _playlists = [];
  bool _playlistsLoading = false;

  List<Playlist> get playlists => _playlists;
  bool get playlistsLoading => _playlistsLoading;

  // Auth
  bool _loginLoading = false;
  String? _loginError;
  bool _needs2FA = false;
  bool _needsCaptcha = false;
  String? _captchaSid;
  String? _captchaImg;

  bool get loginLoading => _loginLoading;
  String? get loginError => _loginError;
  bool get needs2FA => _needs2FA;
  bool get needsCaptcha => _needsCaptcha;
  String? get captchaSid => _captchaSid;
  String? get captchaImg => _captchaImg;

  Future<bool> login(
    String username,
    String password, {
    String? captchaSid,
    String? captchaKey,
  }) async {
    _loginLoading = true;
    _loginError = null;
    if (captchaSid == null) {
      _needs2FA = false;
      _needsCaptcha = false;
    }
    notifyListeners();

    final result = await _api.login(
      username,
      password,
      captchaSid: captchaSid,
      captchaKey: captchaKey,
    );

    _loginLoading = false;

    if (result['success'] == true) {
      _needsCaptcha = false;
      notifyListeners();
      return true;
    }

    if (result['need_2fa'] == true) {
      _needs2FA = true;
      notifyListeners();
      return false;
    }

    if (result['need_captcha'] == true) {
      _needsCaptcha = true;
      _captchaSid = result['captcha_sid'];
      _captchaImg = result['captcha_img'];
      notifyListeners();
      return false;
    }

    _loginError = result['error'];
    notifyListeners();
    return false;
  }

  Future<bool> login2FA(String username, String password, String code) async {
    _loginLoading = true;
    _loginError = null;
    notifyListeners();

    final result = await _api.login2FA(username, password, code);

    _loginLoading = false;

    if (result['success'] == true) {
      _needs2FA = false;
      notifyListeners();
      return true;
    }

    _loginError = result['error'];
    notifyListeners();
    return false;
  }

  Future<void> loginWithToken(String token, int userId) async {
    await _api.loginWithToken(token, userId);
    _loginError = null;
    _needs2FA = false;
    _needsCaptcha = false;
    notifyListeners();
  }

  Future<void> logout() async {
    await _api.logout();
    _myTracks = [];
    _savedTrackKeys.clear();
    _searchResults = [];
    _recommendations = [];
    _newTracks = [];
    _newAlbums = [];
    _popularAlbums = [];
    _artistAlbumsCache.clear();
    _artistAlbumsLoading.clear();
    _playlists = [];
    notifyListeners();
  }

  Future<void> loadMyTracks({bool refresh = false}) async {
    if (_myTracksLoading) return;
    if (!refresh && !_myTracksHasMore) return;
    _myTracksLoading = true;
    _myTracksError = null;
    if (refresh) {
      _myTracks = [];
      _myTracksHasMore = true;
    }
    notifyListeners();

    try {
      final tracks = await _api.getMyAudio(
        offset: refresh ? 0 : _myTracks.length,
      );
      _myTracksHasMore = tracks.isNotEmpty;
      if (refresh) {
        _myTracks = _dedupeTracks(tracks);
        _savedTrackKeys
          ..clear()
          ..addAll(_myTracks.map((t) => _trackKey(t.id, t.ownerId)));
      } else {
        _myTracks = _dedupeTracks([..._myTracks, ...tracks]);
        _savedTrackKeys.addAll(_myTracks.map((t) => _trackKey(t.id, t.ownerId)));
      }
    } catch (e) {
      _myTracksError = e.toString();
    }

    _myTracksLoading = false;
    notifyListeners();
  }

  Future<void> ensureMyTracksLoadedForSearch({int maxBatches = 20}) async {
    var loaded = 0;
    while (_myTracksHasMore && !_myTracksLoading && loaded < maxBatches) {
      await loadMyTracks();
      loaded++;
      if (_myTracksError != null) break;
    }
  }

  Future<void> searchAudio(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      _searchQuery = '';
      notifyListeners();
      return;
    }

    _searchQuery = query;
    _searchLoading = true;
    notifyListeners();

    try {
      _searchResults = await _api.searchAudio(query);
    } catch (e) {
      _searchResults = [];
    }

    _searchLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreSearch() async {
    if (_searchLoading || _searchQuery.isEmpty) return;
    _searchLoading = true;
    notifyListeners();

    try {
      final more = await _api.searchAudio(
        _searchQuery,
        offset: _searchResults.length,
      );
      _searchResults.addAll(more);
    } catch (_) {}

    _searchLoading = false;
    notifyListeners();
  }

  Future<void> loadRecommendations({bool refresh = false}) async {
    if (_recommendationsLoading) return;
    _recommendationsLoading = true;
    notifyListeners();

    try {
      final tracks = await _api.getRecommendations(
        offset: refresh ? 0 : _recommendations.length,
      );
      if (refresh) {
        _recommendations = tracks;
      } else {
        _recommendations.addAll(tracks);
      }
    } catch (_) {}

    _recommendationsLoading = false;
    notifyListeners();
  }

  Future<void> loadDiscovery({bool refresh = false}) async {
    final now = DateTime.now();
    final dateKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (!refresh &&
        _discoveryDateKey == dateKey &&
        _dailyMix.isNotEmpty &&
        _albumOfDay != null) {
      return;
    }

    if (_discoveryLoading) return;
    _discoveryLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        loadRecommendations(refresh: refresh || _recommendations.isEmpty),
        loadNewReleases(refresh: refresh || _newTracks.isEmpty),
      ]);
      _popularAlbums = await _api.getPopularAlbums(count: 24);

      if (_myTracks.isEmpty) {
        await loadMyTracks(refresh: false);
      }

      final baseRecommendations = _dedupeTracks(_recommendations);
      final baseFresh = _dedupeTracks(_newTracks);
      final allMy = _dedupeTracks(_myTracks);

      final topArtists = _topArtists(allMy, limit: 6);
      final artistPicks = <Track>[];
      for (final artist in topArtists.take(3)) {
        try {
          final found = await _api.searchAudio(artist, count: 20);
          final normalizedArtist = artist.toLowerCase();
          final filtered = found.where((t) {
            final trackArtist = t.artist.toLowerCase();
            return trackArtist.contains(normalizedArtist) ||
                normalizedArtist.contains(trackArtist);
          });
          artistPicks.addAll(filtered);
        } catch (_) {}
      }

      final mixPool = _dedupeTracks([
        ...baseRecommendations.take(50),
        ...baseFresh.take(40),
        ...artistPicks.take(40),
      ]);

      final seed = now.year * 10000 + now.month * 100 + now.day;
      final shuffled = _stableShuffle(mixPool, seed);
      _dailyMix = shuffled.take(30).toList(growable: false);

      _albumOfDay = _pickAlbumOfDay(
        tracks: [...baseRecommendations, ...baseFresh, ...artistPicks],
        seed: seed + 17,
      );

      if (topArtists.isNotEmpty) {
        await loadArtistAlbums(topArtists.first);
      }

      _discoveryDateKey = dateKey;
    } catch (_) {
      if (_dailyMix.isEmpty) {
        _dailyMix = _dedupeTracks([
          ..._recommendations,
          ..._newTracks,
          ..._myTracks,
        ]).take(30).toList(growable: false);
      }
    }

    _discoveryLoading = false;
    notifyListeners();
  }

  Future<void> loadPlaylists() async {
    if (_playlistsLoading) return;
    _playlistsLoading = true;
    notifyListeners();

    try {
      _playlists = await _api.getPlaylists();
    } catch (_) {}

    _playlistsLoading = false;
    notifyListeners();
  }

  Future<List<Track>> loadPlaylistTracks(int ownerId, int playlistId) async {
    return await _api.getPlaylistTracks(ownerId, playlistId);
  }

  Future<void> addTrack(Track track) async {
    await _api.addTrack(track.id, track.ownerId);
    if (_myTracks.indexWhere(
          (t) => t.id == track.id && t.ownerId == track.ownerId,
        ) ==
        -1) {
      _myTracks.insert(0, track);
    }
    _savedTrackKeys.add(_trackKey(track.id, track.ownerId));
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(Track track, Playlist playlist) async {
    await _api.addTrackToPlaylist(
      playlistOwnerId: playlist.ownerId,
      playlistId: playlist.id,
      audioId: track.id,
      audioOwnerId: track.ownerId,
    );
  }

  Future<void> deleteTrack(Track track) async {
    await _api.deleteTrack(track.id, track.ownerId);
    _myTracks.removeWhere(
      (t) => t.id == track.id && t.ownerId == track.ownerId,
    );
    _savedTrackKeys.remove(_trackKey(track.id, track.ownerId));
    notifyListeners();
  }

  Future<bool> toggleSavedTrack(Track track) async {
    final saved = isTrackSaved(track.id, ownerId: track.ownerId);
    if (saved) {
      await deleteTrack(track);
      return false;
    } else {
      await addTrack(track);
      return true;
    }
  }

  Future<void> loadNewReleases({bool refresh = false}) async {
    if (_newReleasesLoading) return;
    _newReleasesLoading = true;
    notifyListeners();

    try {
      final tracks = await _api.getNewTracks(
        offset: refresh ? 0 : _newTracks.length,
        count: 40,
      );
      final albums = await _api.getNewAlbums(offset: 0, count: 25);

      if (refresh) {
        _newTracks = tracks;
        _newAlbums = albums;
      } else {
        _newTracks.addAll(tracks);
        _newAlbums = _dedupePlaylists([..._newAlbums, ...albums]);
      }
    } catch (_) {}

    _newReleasesLoading = false;
    notifyListeners();
  }

  Future<void> loadArtistAlbums(String artist, {bool refresh = false}) async {
    final key = artist.trim();
    if (key.isEmpty) return;
    if (!refresh && _artistAlbumsCache.containsKey(key)) return;
    if (_artistAlbumsLoading.contains(key)) return;

    _artistAlbumsLoading.add(key);
    notifyListeners();

    try {
      final albums = await _api.getAlbumsByArtist(key, count: 24);
      _artistAlbumsCache[key] = albums;
    } catch (_) {
      _artistAlbumsCache.putIfAbsent(key, () => const <Playlist>[]);
    }

    _artistAlbumsLoading.remove(key);
    notifyListeners();
  }

  Future<int> saveTracksToMyLibrary(
    Iterable<Track> tracks, {
    int? maxCount,
  }) async {
    var added = 0;
    var processed = 0;
    for (final track in tracks) {
      if (maxCount != null && processed >= maxCount) break;
      processed++;
      if (_savedTrackKeys.contains(_trackKey(track.id, track.ownerId))) {
        continue;
      }
      try {
        await _api.addTrack(track.id, track.ownerId);
        _savedTrackKeys.add(_trackKey(track.id, track.ownerId));
        if (_myTracks.indexWhere((t) => t.id == track.id) == -1) {
          _myTracks.insert(0, track);
        }
        added++;
      } catch (_) {}
    }
    notifyListeners();
    return added;
  }

  String _trackKey(int trackId, int ownerId) => '${ownerId}_$trackId';

  List<Track> _dedupeTracks(Iterable<Track> tracks) {
    final byKey = <String, Track>{};
    for (final track in tracks) {
      byKey[_trackKey(track.id, track.ownerId)] = track;
    }
    return byKey.values.toList(growable: false);
  }

  List<Playlist> _dedupePlaylists(Iterable<Playlist> playlists) {
    final byKey = <String, Playlist>{};
    for (final playlist in playlists) {
      byKey['${playlist.ownerId}_${playlist.id}'] = playlist;
    }
    return byKey.values.toList(growable: false);
  }

  List<String> _topArtists(List<Track> tracks, {int limit = 5}) {
    final counts = <String, int>{};
    for (final track in tracks) {
      final name = track.artist.trim();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList(growable: false);
  }

  List<Track> _stableShuffle(List<Track> tracks, int seed) {
    final copy = List<Track>.from(tracks);
    final random = Random(seed);
    for (var i = copy.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final t = copy[i];
      copy[i] = copy[j];
      copy[j] = t;
    }
    return copy;
  }

  Playlist? _pickAlbumOfDay({required List<Track> tracks, required int seed}) {
    final byAlbum = <String, List<Track>>{};
    for (final track in tracks) {
      if (track.albumId == null || track.albumOwnerId == null) continue;
      final key = '${track.albumOwnerId}_${track.albumId}';
      byAlbum.putIfAbsent(key, () => []).add(track);
    }
    if (byAlbum.isEmpty) return _newAlbums.isNotEmpty ? _newAlbums.first : null;

    final albums = byAlbum.entries.map((entry) {
      final first = entry.value.first;
      return Playlist(
        id: first.albumId!,
        ownerId: first.albumOwnerId!,
        title: first.albumTitle ?? first.title,
        count: entry.value.length,
        createTime: 0,
        updateTime: 0,
        photo: first.albumThumb,
      );
    }).toList(growable: false);

    final random = Random(seed);
    return albums[random.nextInt(albums.length)];
  }
}

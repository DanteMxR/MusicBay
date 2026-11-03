import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';
import '../services/library_index_service.dart';

class MusicProvider extends ChangeNotifier {
  static const int _kMaxSearchResults = 500;
  static const int _kFreshenAhead = 30;
  static const int _kFreshenAtOnce = 6;

  final ApiService _api;
  final LibraryIndexService _libraryIndex;

  MusicProvider(this._api, this._libraryIndex) {
    _api.onSessionExpired = _clearAfterLogout;
    _api.onClientOutdated = () {
      _clientOutdated = true;
      notifyListeners();
    };
  }

  ApiService get api => _api;

  bool get isAuthorized => _api.isAuthorized;

  bool _clientOutdated = false;
  bool get clientOutdated => _clientOutdated;

  final Set<String> _likedTrackIds = {};
  bool isTrackLiked(String trackId) => _likedTrackIds.contains(trackId);

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  // My Audio
  List<Track> _myTracks = [];
  List<Track> _myTracksIndex = [];
  final Set<String> _savedTrackIds = {};
  bool _myTracksLoading = false;
  bool _myTracksHasMore = true;
  String? _myTracksCursor;
  bool _myTracksIndexSyncing = false;
  bool _myTracksIndexComplete = false;
  String? _myTracksError;
  int _myTracksSearchRequestId = 0;
  DateTime? _myTracksIndexUpdatedAt;

  List<Track> get myTracks => _myTracks;
  List<Track> get myTracksIndex => _myTracksIndex;
  bool get myTracksLoading => _myTracksLoading;
  bool get myTracksHasMore => _myTracksHasMore;
  bool get myTracksIndexSyncing => _myTracksIndexSyncing;
  String? get myTracksError => _myTracksError;
  bool get myTracksFullyLoaded => !_myTracksHasMore && !_myTracksLoading;
  bool get hasMyTracksIndex => _myTracksIndex.isNotEmpty;
  bool get myTracksIndexReady => _myTracksIndexComplete;
  DateTime? get myTracksIndexUpdatedAt => _myTracksIndexUpdatedAt;
  bool isTrackSaved(String trackId) => _savedTrackIds.contains(trackId);

  // Search
  List<Track> _searchResults = [];
  bool _searchLoading = false;
  String _searchQuery = '';
  String? _searchCursor;
  int _searchRequestId = 0;
  String? _searchError;

  List<Track> get searchResults => _searchResults;
  bool get searchLoading => _searchLoading;
  String get searchQuery => _searchQuery;
  String? get searchError => _searchError;

  // The server has no recommendations, so these are made from the library of the user.
  List<Track> _recommendations = [];
  bool _recommendationsLoading = false;

  List<Track> get recommendations => _recommendations;
  bool get recommendationsLoading => _recommendationsLoading;

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
  final Map<String, _ArtistAlbumsCacheEntry> _artistAlbumsCache = {};
  final Set<String> _artistAlbumsLoading = {};

  List<Track> get dailyMix => _dailyMix;
  Playlist? get albumOfDay => _albumOfDay;
  bool get discoveryLoading => _discoveryLoading;
  List<Playlist> get popularAlbums => _popularAlbums;
  List<Playlist> artistAlbums(String artist) =>
      _artistAlbumsCache[artist]?.albums ?? const <Playlist>[];
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

  bool get loginLoading => _loginLoading;
  String? get loginError => _loginError;
  String get serverUrl => _api.serverUrl;

  // Uploads
  bool _uploading = false;
  double _uploadProgress = 0;

  bool get uploading => _uploading;
  double get uploadProgress => _uploadProgress;
  String? _lastUploadError;
  String? get lastUploadError => _lastUploadError;

  void bootstrap() {
    _restoreMyTracksIndexFromDisk();
    if (isAuthorized) {
      _startMyTracksIndexSync();
    }
  }

  Future<bool> login(String server, String username, String password) =>
      _enter(() => _api.login(server, username, password));

  Future<bool> register(String server, String username, String password) =>
      _enter(() => _api.register(server, username, password));

  Future<bool> _enter(Future<void> Function() enter) async {
    _loginLoading = true;
    _loginError = null;
    notifyListeners();

    try {
      await enter();
    } on ApiException catch (e) {
      _loginError = e.message;
      _loginLoading = false;
      notifyListeners();
      return false;
    }

    _loginLoading = false;
    _restoreMyTracksIndexFromDisk();
    _startMyTracksIndexSync();
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await _api.logout();
    _clearAfterLogout();
  }

  void _clearAfterLogout() {
    _myTracksSearchRequestId++;
    _myTracks = [];
    _myTracksIndex = [];
    _myTracksCursor = null;
    _myTracksHasMore = true;
    _savedTrackIds.clear();
    _likedTrackIds.clear();
    _myTracksIndexSyncing = false;
    _myTracksIndexComplete = false;
    _myTracksIndexUpdatedAt = null;
    _searchResults = [];
    _recommendations = [];
    _newTracks = [];
    _newAlbums = [];
    _dailyMix = [];
    _albumOfDay = null;
    _discoveryDateKey = null;
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
      _myTracksCursor = null;
      _myTracksHasMore = true;
    }
    notifyListeners();

    try {
      final page = await _api.getLibrary(cursor: _myTracksCursor);
      _myTracksCursor = page.nextCursor;
      _myTracksHasMore = page.nextCursor != null;
      _myTracks = _dedupeTracks([..._myTracks, ...page.items]);
      if (refresh) {
        _savedTrackIds.clear();
      }
      _savedTrackIds.addAll(_myTracks.map((t) => t.id));
      _noteTracks(page.items);
      _mergeTracksIntoMyTracksIndex(page.items);
      await _persistMyTracksIndex();
    } catch (e) {
      _myTracksError = e.toString();
    }

    _myTracksLoading = false;
    notifyListeners();
  }

  Future<void> ensureMyTracksLoadedForSearch() async {
    await syncMyTracksIndex();
  }

  void cancelMyTracksSearchPrefetch() {
    _myTracksSearchRequestId++;
  }

  List<Track> searchMyTracksLocally(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _myTracksIndex.isNotEmpty ? _myTracksIndex : _myTracks;
    }

    final source = _myTracksIndex.isNotEmpty ? _myTracksIndex : _myTracks;
    return source
        .where((track) {
          final artist = track.artist.toLowerCase();
          final title = track.title.toLowerCase();
          final album = (track.albumTitle ?? '').toLowerCase();
          return artist.contains(normalized) ||
              title.contains(normalized) ||
              album.contains(normalized);
        })
        .toList(growable: false);
  }

  Future<void> syncMyTracksIndex({bool force = false}) async {
    if (!isAuthorized) return;
    if (_myTracksIndexSyncing) return;
    if (!force &&
        _myTracksIndexComplete &&
        _myTracksIndexUpdatedAt != null &&
        DateTime.now().difference(_myTracksIndexUpdatedAt!) <
            const Duration(minutes: 30)) {
      return;
    }

    final requestId = ++_myTracksSearchRequestId;
    _myTracksIndexSyncing = true;
    notifyListeners();

    try {
      final allTracks = <Track>[];
      String? cursor;

      do {
        final page = await _api.getLibrary(
          cursor: cursor,
          limit: kLibraryIndexBatchSize,
        );
        allTracks.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null && requestId == _myTracksSearchRequestId);

      if (requestId != _myTracksSearchRequestId) return;

      final indexed = _dedupeTracks(allTracks);
      _myTracksIndex = indexed;
      _myTracksIndexComplete = true;
      _myTracksIndexUpdatedAt = DateTime.now();
      _savedTrackIds
        ..clear()
        ..addAll(indexed.map((track) => track.id));
      _noteTracks(indexed);
      await _persistMyTracksIndex();
    } catch (e) {
      debugPrint('MusicProvider.syncMyTracksIndex: $e');
    } finally {
      if (requestId == _myTracksSearchRequestId) {
        _myTracksIndexSyncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> searchAudio(String query) async {
    final normalizedQuery = query.trim();
    final requestId = ++_searchRequestId;

    if (normalizedQuery.isEmpty) {
      _searchResults = [];
      _searchQuery = '';
      _searchCursor = null;
      _searchLoading = false;
      _searchError = null;
      notifyListeners();
      return;
    }

    _searchQuery = normalizedQuery;
    _searchLoading = true;
    _searchError = null;
    notifyListeners();

    try {
      final found = await _api.search(normalizedQuery);
      if (requestId != _searchRequestId) return;
      _searchResults = _dedupeTracks(found.items);
      _noteTracks(found.items);
      _searchCursor = found.nextCursor;
    } catch (e) {
      debugPrint('MusicProvider.searchAudio: $e');
      if (requestId != _searchRequestId) return;
      _searchResults = [];
      _searchCursor = null;
      _searchError = e.toString();
    }

    if (requestId != _searchRequestId) return;
    _searchLoading = false;
    notifyListeners();
  }

  Future<void> searchArtistTracks(String artist) async {
    final query = artist.trim();
    final requestId = ++_searchRequestId;
    _searchCursor = null;
    if (query.isEmpty) {
      _searchResults = [];
      _searchQuery = '';
      _searchLoading = false;
      notifyListeners();
      return;
    }

    _searchQuery = query;
    _searchLoading = true;
    notifyListeners();

    try {
      final found = await _api.search(query, limit: 150);
      if (requestId != _searchRequestId) return;
      _searchResults = _dedupeTracks(_byArtist(found.items, query));
      _noteTracks(found.items);
      _searchError = null;
    } catch (e) {
      debugPrint('MusicProvider.searchArtistTracks: $e');
      if (requestId != _searchRequestId) return;
      _searchResults = [];
      _searchError = e.toString();
    }

    if (requestId != _searchRequestId) return;
    _searchLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreSearch() async {
    if (_searchLoading || _searchQuery.isEmpty || _searchCursor == null) return;
    if (_searchResults.length >= _kMaxSearchResults) return;
    final requestId = _searchRequestId;
    _searchLoading = true;
    notifyListeners();

    try {
      final more = await _api.search(_searchQuery, cursor: _searchCursor);
      if (requestId != _searchRequestId) return;
      _searchCursor = more.nextCursor;
      _noteTracks(more.items);
      final merged = _dedupeTracks([..._searchResults, ...more.items]);
      _searchResults = merged.length > _kMaxSearchResults
          ? merged.take(_kMaxSearchResults).toList(growable: false)
          : merged;
    } catch (e) {
      debugPrint('MusicProvider.loadMoreSearch: $e');
    }

    if (requestId != _searchRequestId) return;
    _searchLoading = false;
    notifyListeners();
  }

  Future<void> loadRecommendations({bool refresh = false}) async {
    if (_recommendationsLoading) return;
    _recommendationsLoading = true;
    notifyListeners();

    await _ensureMyTracks();
    _recommendations = _stableShuffle(_libraryTracks(), _daySeed());

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
      await loadRecommendations(refresh: refresh);
      await loadNewReleases(refresh: refresh);

      final library = _libraryTracks();
      final byPlays = List<Track>.from(library)
        ..sort((a, b) => b.plays.compareTo(a.plays));
      _popularAlbums = _albumsFromTracks(byPlays).take(24).toList();

      // Search is what brings in public tracks the user does not have yet.
      final topArtists = _topArtists(library, limit: 6);
      final artistPicks = <Track>[];
      for (final artist in topArtists.take(3)) {
        try {
          final found = await _api.search(artist, limit: 20);
          artistPicks.addAll(_byArtist(found.items, artist));
        } catch (e) {
          debugPrint('MusicProvider.loadDiscovery (artist=$artist): $e');
        }
      }

      final mixPool = _dedupeTracks([
        ..._recommendations.take(50),
        ...artistPicks.take(40),
      ]);

      final seed = _daySeed();
      _dailyMix = _stableShuffle(
        mixPool,
        seed,
      ).take(30).toList(growable: false);

      _albumOfDay = _pickAlbumOfDay(
        tracks: [...library, ...artistPicks],
        seed: seed + 17,
      );

      if (topArtists.isNotEmpty) {
        await loadArtistAlbums(topArtists.first);
      }

      _discoveryDateKey = dateKey;
    } catch (e) {
      debugPrint('MusicProvider.loadDiscovery: $e');
      if (_dailyMix.isEmpty) {
        _dailyMix = _libraryTracks().take(30).toList(growable: false);
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
    } catch (e) {
      debugPrint('MusicProvider.loadPlaylists: $e');
    }

    _playlistsLoading = false;
    notifyListeners();
  }

  Future<void> createPlaylist(String title) async {
    final playlist = await _api.createPlaylist(title);
    _playlists = [playlist, ..._playlists];
    notifyListeners();
  }

  Future<void> renamePlaylist(Playlist playlist, String title) async {
    await _api.renamePlaylist(playlist.id, title);
    _playlistsLoading = false;
    await loadPlaylists();
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    await _api.deletePlaylist(playlist.id);
    _playlists = _playlists.where((p) => p.id != playlist.id).toList();
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(Playlist playlist, Track track) async {
    await _api.removeFromPlaylist(playlist.id, track.id);
  }

  Future<List<Track>> loadPlaylistTracks(Playlist playlist) async {
    switch (playlist.kind) {
      case PlaylistKind.own:
        return await _api.getPlaylistTracks(playlist.id);
      case PlaylistKind.liked:
        final liked = await _api.getLikes();
        _likedTrackIds
          ..clear()
          ..addAll(liked.map((t) => t.id));
        notifyListeners();
        return liked;
      case PlaylistKind.album:
        return await _loadAlbumTracks(playlist.id);
    }
  }

  // The server gives only the public tracks of an album, so the private ones of the user
  // come from their library.
  Future<List<Track>> _loadAlbumTracks(String albumId) async {
    final own = _libraryTracks().where((t) => t.albumId == albumId);
    try {
      return _dedupeTracks([...own, ...await _api.getAlbumTracks(albumId)]);
    } on ApiException {
      if (own.isEmpty) rethrow;
      return own.toList(growable: false);
    }
  }

  Future<bool> toggleLike(Track track) async {
    final liked = !isTrackLiked(track.id);
    if (liked) {
      await _api.like(track.id);
      _likedTrackIds.add(track.id);
    } else {
      await _api.unlike(track.id);
      _likedTrackIds.remove(track.id);
    }
    notifyListeners();
    return liked;
  }

  Future<void> updateTrack(
    Track track, {
    String? title,
    String? artist,
    String? album,
    String? visibility,
  }) async {
    await _api.updateTrack(
      track.id,
      title: title,
      artist: artist,
      album: album,
      visibility: visibility,
    );
    await _rereadLibrary();
  }

  Future<void> deleteOwnTrack(Track track) async {
    await _api.deleteTrack(track.id);
    _myTracks = _myTracks.where((t) => t.id != track.id).toList();
    _myTracksIndex = _myTracksIndex
        .where((t) => t.id != track.id)
        .toList(growable: false);
    _savedTrackIds.remove(track.id);
    _likedTrackIds.remove(track.id);
    await _persistMyTracksIndex();
    notifyListeners();
  }

  Future<void> _rereadLibrary() async {
    await loadMyTracks(refresh: true);
    await syncMyTracksIndex(force: true);
  }

  // Tracks say by themselves whether they are liked and in the library.
  void _noteTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      if (track.liked) _likedTrackIds.add(track.id);
      if (track.inLibrary) _savedTrackIds.add(track.id);
    }
  }

  Future<void> addTrack(Track track) async {
    await _api.addToLibrary(track.id);
    _myTracks = List<Track>.from(_myTracks, growable: true);
    if (_myTracks.indexWhere((t) => t.id == track.id) == -1) {
      _myTracks.insert(0, track);
    }
    _savedTrackIds.add(track.id);
    _mergeTracksIntoMyTracksIndex([track]);
    await _persistMyTracksIndex();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(Track track, Playlist playlist) async {
    await _api.addTrackToPlaylist(playlist.id, track.id);
  }

  Future<void> deleteTrack(Track track) async {
    await _api.removeFromLibrary(track.id);
    _myTracks = _myTracks.where((t) => t.id != track.id).toList();
    _myTracksIndex = _myTracksIndex
        .where((t) => t.id != track.id)
        .toList(growable: false);
    if (_myTracksIndex.isEmpty) {
      _myTracksIndexComplete = false;
    }
    _savedTrackIds.remove(track.id);
    await _persistMyTracksIndex();
    notifyListeners();
  }

  Future<bool> toggleSavedTrack(Track track) async {
    if (isTrackSaved(track.id)) {
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

    await _ensureMyTracks();
    // The library comes newest first.
    _newTracks = _libraryTracks().take(40).toList(growable: false);
    _newAlbums = _albumsFromTracks(_newTracks).take(25).toList(growable: false);

    _newReleasesLoading = false;
    notifyListeners();
  }

  Future<void> loadArtistAlbums(String artist, {bool refresh = false}) async {
    final key = artist.trim();
    if (key.isEmpty) return;
    if (!refresh && _hasFreshArtistAlbumsCache(key)) return;
    if (_artistAlbumsLoading.contains(key)) return;

    _artistAlbumsLoading.add(key);
    notifyListeners();

    try {
      final found = await _api.search(key, limit: 100);
      final tracks = _byArtist([..._libraryTracks(), ...found.items], key);
      _artistAlbumsCache[key] = _ArtistAlbumsCacheEntry(
        _albumsFromTracks(tracks).take(24).toList(growable: false),
        DateTime.now(),
      );
    } catch (e) {
      debugPrint('MusicProvider.loadArtistAlbums ($key): $e');
      _artistAlbumsCache.putIfAbsent(
        key,
        () => _ArtistAlbumsCacheEntry(const <Playlist>[], DateTime.now()),
      );
    }

    _artistAlbumsLoading.remove(key);
    notifyListeners();
  }

  Future<int> saveTracksToMyLibrary(
    Iterable<Track> tracks, {
    int? maxCount,
  }) async {
    _myTracks = List<Track>.from(_myTracks, growable: true);
    var added = 0;
    var processed = 0;
    for (final track in tracks) {
      if (maxCount != null && processed >= maxCount) break;
      processed++;
      if (_savedTrackIds.contains(track.id)) {
        continue;
      }
      try {
        await _api.addToLibrary(track.id);
        _savedTrackIds.add(track.id);
        if (_myTracks.indexWhere((t) => t.id == track.id) == -1) {
          _myTracks.insert(0, track);
        }
        added++;
      } catch (e) {
        debugPrint('MusicProvider.saveTracksToMyLibrary (${track.id}): $e');
      }
    }
    notifyListeners();
    return added;
  }

  /// Uploads files one by one and adds them to the library. Returns how many got through.
  Future<int> uploadFiles(List<File> files, String visibility) async {
    if (_uploading) return 0;
    _uploading = true;
    _uploadProgress = 0;
    _lastUploadError = null;
    notifyListeners();

    var done = 0;
    for (var i = 0; i < files.length; i++) {
      try {
        final track = await _api.uploadFile(
          files[i],
          visibility: visibility,
          onProgress: (progress) {
            _uploadProgress = (i + progress) / files.length;
            notifyListeners();
          },
        );
        await _api.addToLibrary(track.id);
        unawaited(_refreshWhenProcessed(track.id));
        done++;
      } catch (e) {
        debugPrint('MusicProvider.uploadFiles (${files[i].path}): $e');
        _lastUploadError = e.toString();
      }
    }

    _uploading = false;
    notifyListeners();
    await _rereadLibrary();
    return done;
  }

  // A new track needs a while to get its streams, and until then it cannot be played.
  Future<void> _refreshWhenProcessed(String trackId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline) && isAuthorized) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final track = await _api.getTrack(trackId);
        if (track.isProcessing) continue;
        await _rereadLibrary();
        return;
      } catch (e) {
        debugPrint('MusicProvider._refreshWhenProcessed: $e');
        return;
      }
    }
  }

  /// Gets new links for the tracks about to be played, if theirs have run out. Without
  /// an answer from the server the tracks stay as they are, and the cached ones still play.
  Future<List<Track>> freshenTracks(List<Track> tracks, int startIndex) async {
    final result = List<Track>.from(tracks);
    final end = min(startIndex + _kFreshenAhead, tracks.length);
    final stale = [
      for (var i = startIndex; i < end; i++)
        if (tracks[i].isLinkStale) i,
    ];
    for (var i = 0; i < stale.length; i += _kFreshenAtOnce) {
      final batch = stale.skip(i).take(_kFreshenAtOnce);
      try {
        await Future.wait(
          batch.map((index) async {
            result[index] = await _api.getTrack(tracks[index].id);
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('MusicProvider.freshenTracks: $e');
        break;
      }
    }
    return result;
  }

  Future<void> reportPlay(String trackId) async {
    try {
      await _api.reportPlay(trackId);
    } catch (e) {
      debugPrint('MusicProvider.reportPlay: $e');
    }
  }

  Future<void> _ensureMyTracks() async {
    if (_myTracks.isEmpty && _myTracksIndex.isEmpty) {
      await loadMyTracks();
    }
  }

  List<Track> _libraryTracks() {
    return _dedupeTracks(
      _myTracksIndex.isNotEmpty ? _myTracksIndex : _myTracks,
    );
  }

  int _daySeed() {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  Iterable<Track> _byArtist(Iterable<Track> tracks, String artist) {
    final needle = artist.toLowerCase().trim();
    return tracks.where((track) {
      final name = track.artist.toLowerCase().trim();
      return name.contains(needle) || needle.contains(name);
    });
  }

  List<Playlist> _albumsFromTracks(Iterable<Track> tracks) {
    final byId = <String, Playlist>{};
    for (final track in tracks) {
      final albumId = track.albumId;
      if (albumId == null) continue;
      byId.putIfAbsent(
        albumId,
        () => Playlist(
          id: albumId,
          title: track.albumTitle ?? track.title,
          count: 0,
          photo: track.albumThumb,
          kind: PlaylistKind.album,
        ),
      );
    }
    return byId.values.toList(growable: false);
  }

  void _mergeTracksIntoMyTracksIndex(Iterable<Track> tracks) {
    if (tracks.isEmpty) return;
    _myTracksIndex = _dedupeTracks([...tracks, ..._myTracksIndex]);
  }

  void _restoreMyTracksIndexFromDisk() {
    final userId = _api.userId;
    if (userId == null) return;

    _myTracksIndex = _libraryIndex.readMyTracks(userId);
    _myTracksIndexComplete = _libraryIndex.readMyTracksIsComplete(userId);
    _myTracksIndexUpdatedAt = _libraryIndex.readMyTracksUpdatedAt(userId);
    if (_myTracksIndex.isNotEmpty) {
      _savedTrackIds
        ..clear()
        ..addAll(_myTracksIndex.map((track) => track.id));
    }
  }

  void _startMyTracksIndexSync() {
    Future<void>(() async {
      await syncMyTracksIndex();
      await _loadLikes();
    });
  }

  Future<void> _loadLikes() async {
    try {
      _noteTracks(await _api.getLikes());
      notifyListeners();
    } catch (e) {
      debugPrint('MusicProvider._loadLikes: $e');
    }
  }

  Future<void> _persistMyTracksIndex() async {
    final userId = _api.userId;
    if (userId == null) return;

    if (_myTracksIndex.isEmpty) {
      await _libraryIndex.clearMyTracks(userId);
      return;
    }

    await _libraryIndex.writeMyTracks(
      userId,
      _myTracksIndex,
      isComplete: _myTracksIndexComplete,
    );
  }

  bool _hasFreshArtistAlbumsCache(String artist) {
    final entry = _artistAlbumsCache[artist];
    if (entry == null) return false;
    return DateTime.now().difference(entry.cachedAt) < kArtistAlbumsCacheTtl;
  }

  List<Track> _dedupeTracks(Iterable<Track> tracks) {
    final byId = <String, Track>{};
    for (final track in tracks) {
      byId[track.id] = track;
    }
    return byId.values.toList();
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
    final albums = _albumsFromTracks(tracks);
    if (albums.isEmpty) return null;
    return albums[Random(seed).nextInt(albums.length)];
  }
}

class _ArtistAlbumsCacheEntry {
  final List<Playlist> albums;
  final DateTime cachedAt;

  const _ArtistAlbumsCacheEntry(this.albums, this.cachedAt);
}

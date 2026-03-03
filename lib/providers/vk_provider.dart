import 'package:flutter/foundation.dart';
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
  String? _myTracksError;

  List<Track> get myTracks => _myTracks;
  bool get myTracksLoading => _myTracksLoading;
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
    _playlists = [];
    notifyListeners();
  }

  Future<void> loadMyTracks({bool refresh = false}) async {
    if (_myTracksLoading) return;
    _myTracksLoading = true;
    _myTracksError = null;
    if (refresh) _myTracks = [];
    notifyListeners();

    try {
      final tracks = await _api.getMyAudio(
        offset: refresh ? 0 : _myTracks.length,
      );
      if (refresh) {
        _myTracks = tracks;
        _savedTrackKeys
          ..clear()
          ..addAll(tracks.map((t) => _trackKey(t.id, t.ownerId)));
      } else {
        _myTracks.addAll(tracks);
        _savedTrackKeys.addAll(tracks.map((t) => _trackKey(t.id, t.ownerId)));
      }
    } catch (e) {
      _myTracksError = e.toString();
    }

    _myTracksLoading = false;
    notifyListeners();
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

      if (refresh) {
        _newTracks = tracks;
        _newAlbums = const [];
      } else {
        _newTracks.addAll(tracks);
      }
    } catch (_) {}

    _newReleasesLoading = false;
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
}

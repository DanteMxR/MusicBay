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
  bool _myTracksLoading = false;
  String? _myTracksError;

  List<Track> get myTracks => _myTracks;
  bool get myTracksLoading => _myTracksLoading;
  String? get myTracksError => _myTracksError;

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

  Future<bool> login(String username, String password, {
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
    _searchResults = [];
    _recommendations = [];
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
      } else {
        _myTracks.addAll(tracks);
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
  }

  Future<void> deleteTrack(Track track) async {
    await _api.deleteTrack(track.id, track.ownerId);
    _myTracks.removeWhere((t) => t.id == track.id);
    notifyListeners();
  }
}

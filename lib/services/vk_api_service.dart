import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/track.dart';
import '../models/playlist.dart';

class VkApiService {
  static const String _authUrl = 'https://oauth.vk.com/token';
  static const String _apiUrl = 'https://api.vk.com/method';
  static const String _apiVersion = '5.131';

  // Kate Mobile credentials
  static const int _appId = 2685278;
  static const String _appSecret = 'lxhD8OD7dMsqtXIm5IUY';

  static const String _userAgent =
      'KateMobileAndroid/91.1 lite-523 (Android 12; SDK 31; arm64-v8a; en)';

  final Dio _dio = Dio(BaseOptions(headers: {'User-Agent': _userAgent}));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  int? _userId;

  String? get token => _token;
  int? get userId => _userId;

  Future<void> init() async {
    _token = await _storage.read(key: 'vk_token');
    final uid = await _storage.read(key: 'vk_user_id');
    if (uid != null) _userId = int.tryParse(uid);
  }

  bool get isAuthorized => _token != null && _userId != null;

  Future<Map<String, dynamic>> login(
    String username,
    String password, {
    String? captchaSid,
    String? captchaKey,
  }) async {
    try {
      final params = <String, dynamic>{
        'grant_type': 'password',
        'client_id': _appId,
        'client_secret': _appSecret,
        'username': username,
        'password': password,
        'v': _apiVersion,
        '2fa_supported': 1,
      };
      if (captchaSid != null && captchaKey != null) {
        params['captcha_sid'] = captchaSid;
        params['captcha_key'] = captchaKey;
      }

      final response = await _dio.post(
        _authUrl,
        queryParameters: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (_) => true,
        ),
      );

      final data = response.data;
      developer.log('VK auth response: $data', name: 'VkApi');

      if (data['access_token'] != null) {
        _token = data['access_token'];
        _userId = data['user_id'];
        await _storage.write(key: 'vk_token', value: _token);
        await _storage.write(key: 'vk_user_id', value: _userId.toString());
        return {'success': true};
      }

      // 2FA required
      if (data['redirect_uri'] != null &&
          data['redirect_uri'].toString().contains('act=authcheck')) {
        return {'success': false, 'need_2fa': true};
      }

      // Captcha required
      if (data['error'] == 'need_captcha') {
        return {
          'success': false,
          'need_captcha': true,
          'captcha_sid': data['captcha_sid']?.toString() ?? '',
          'captcha_img': data['captcha_img']?.toString() ?? '',
        };
      }

      return {
        'success': false,
        'error': data['error_description'] ?? data['error'] ?? 'Unknown error',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> login2FA(
    String username,
    String password,
    String code,
  ) async {
    try {
      final response = await _dio.post(
        _authUrl,
        queryParameters: {
          'grant_type': 'password',
          'client_id': _appId,
          'client_secret': _appSecret,
          'username': username,
          'password': password,
          'v': _apiVersion,
          '2fa_supported': 1,
          'code': code,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (_) => true,
        ),
      );

      final data = response.data;

      if (data['access_token'] != null) {
        _token = data['access_token'];
        _userId = data['user_id'];
        await _storage.write(key: 'vk_token', value: _token);
        await _storage.write(key: 'vk_user_id', value: _userId.toString());
        return {'success': true};
      }

      return {
        'success': false,
        'error': data['error_description'] ?? 'Invalid code',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> loginWithToken(String token, int userId) async {
    _token = token;
    _userId = userId;
    await _storage.write(key: 'vk_token', value: _token);
    await _storage.write(key: 'vk_user_id', value: _userId.toString());
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    await _storage.delete(key: 'vk_token');
    await _storage.delete(key: 'vk_user_id');
  }

  Future<dynamic> _apiCall(String method, Map<String, dynamic> params) async {
    if (_token == null) throw Exception('Not authorized');

    final response = await _dio.get(
      '$_apiUrl/$method',
      queryParameters: {...params, 'access_token': _token, 'v': _apiVersion},
    );

    if (response.data['error'] != null) {
      throw Exception(response.data['error']['error_msg'] ?? 'API Error');
    }

    return response.data['response'];
  }

  // ---- Audio methods ----

  Future<List<Track>> getMyAudio({int offset = 0, int count = 50}) async {
    final data = await _apiCall('audio.get', {
      'owner_id': _userId,
      'offset': offset,
      'count': count,
    });

    final items = data['items'] as List;
    return items.map((e) => Track.fromJson(e)).toList();
  }

  Future<List<Track>> searchAudio(
    String query, {
    int offset = 0,
    int count = 50,
  }) async {
    final data = await _apiCall('audio.search', {
      'q': query,
      'auto_complete': 1,
      'sort': 2,
      'offset': offset,
      'count': count,
    });

    final items = data['items'] as List;
    return items.map((e) => Track.fromJson(e)).toList();
  }

  Future<List<Track>> getRecommendations({
    int offset = 0,
    int count = 50,
  }) async {
    final data = await _apiCall('audio.getRecommendations', {
      'offset': offset,
      'count': count,
    });

    final items = data['items'] as List;
    return items.map((e) => Track.fromJson(e)).toList();
  }

  Future<List<Playlist>> getPlaylists({int offset = 0, int count = 50}) async {
    final data = await _apiCall('audio.getPlaylists', {
      'owner_id': _userId,
      'offset': offset,
      'count': count,
    });

    final items = data['items'] as List;
    return items.map((e) => Playlist.fromJson(e)).toList();
  }

  Future<List<Track>> getPlaylistTracks(
    int ownerId,
    int playlistId, {
    int offset = 0,
    int count = 100,
  }) async {
    final data = await _apiCall('audio.get', {
      'owner_id': ownerId,
      'album_id': playlistId,
      'offset': offset,
      'count': count,
    });

    final items = data['items'] as List;
    return items.map((e) => Track.fromJson(e)).toList();
  }

  Future<void> addTrack(int audioId, int ownerId) async {
    await _apiCall('audio.add', {'audio_id': audioId, 'owner_id': ownerId});
  }

  Future<void> addTrackToPlaylist({
    required int playlistOwnerId,
    required int playlistId,
    required int audioId,
    required int audioOwnerId,
  }) async {
    await _apiCall('audio.addToPlaylist', {
      'owner_id': playlistOwnerId,
      'playlist_id': playlistId,
      'audio_ids': '${audioOwnerId}_$audioId',
    });
  }

  Future<void> deleteTrack(int audioId, int ownerId) async {
    await _apiCall('audio.delete', {'audio_id': audioId, 'owner_id': ownerId});
  }

  Future<List<Track>> getPopular({int offset = 0, int count = 50}) async {
    final data = await _apiCall('audio.getPopular', {
      'offset': offset,
      'count': count,
    });

    // audio.getPopular may return a plain list or {count, items}
    final List items = data is List ? data : data['items'] as List;
    return items.map((e) => Track.fromJson(e)).toList();
  }

  Future<List<Track>> getNewTracks({int offset = 0, int count = 50}) async {
    try {
      return await getPopular(offset: offset, count: count);
    } catch (_) {
      return await getRecommendations(offset: offset, count: count);
    }
  }

  Future<List<Playlist>> getNewAlbums({int offset = 0, int count = 30}) async {
    try {
      final data = await _apiCall('audio.getPlaylists', {
        'offset': offset,
        'count': count,
      });
      final items = data['items'] as List;
      return items.map((e) => Playlist.fromJson(e)).toList();
    } catch (_) {
      return await getPlaylists(offset: offset, count: count);
    }
  }
}

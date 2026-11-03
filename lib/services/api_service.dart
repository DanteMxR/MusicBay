import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// An answer of the server that is an error, or no answer at all, when [status] is null.
class ApiException implements Exception {
  final int? status;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  const ApiException(
    this.status,
    this.code,
    this.message, [
    this.details = const {},
  ]);

  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

class Quota {
  final int usedBytes;
  final int quotaBytes;
  final int uploadsToday;
  final int uploadsPerDay;

  const Quota(
    this.usedBytes,
    this.quotaBytes,
    this.uploadsToday,
    this.uploadsPerDay,
  );
}

class Device {
  final String id;
  final String name;
  final String platform;
  final bool current;

  const Device(this.id, this.name, this.platform, this.current);
}

class TrackPage {
  final List<Track> items;
  final String? nextCursor;

  const TrackPage(this.items, this.nextCursor);
}

/// Where the session is kept. Tests keep it in memory.
abstract class SessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class ApiService {
  static const String defaultServerUrl = String.fromEnvironment('SERVER_URL');

  static const String _keyServer = 'server_url';
  static const String _keyAccess = 'access_token';
  static const String _keyRefresh = 'refresh_token';
  static const String _keyUser = 'user_id';
  static const int _chunkAttempts = 3;

  static const Map<String, String> _messages = {
    'invalid_credentials': 'Неверное имя или пароль',
    'username_taken': 'Это имя уже занято',
    'invalid_username': 'Имя: от 3 до 32 латинских букв, цифр и знаков _ . -',
    'invalid_password': 'Пароль: от 8 символов',
    'quota_exceeded': 'На сервере закончилось ваше место',
    'upload_limit_reached': 'На сегодня лимит загрузок исчерпан',
    'upload_too_large': 'Файл больше, чем разрешает сервер',
    'unsupported_format':
        'Формат не поддерживается. Подойдут mp3, flac, wav, aiff, ogg, opus, m4a, aac, alac',
    'empty_file': 'Файл пуст',
    'track_duplicate': 'Этот файл уже загружен',
    'track_not_found': 'Трек не найден, или он не ваш',
    'playlist_not_found': 'Плейлист не найден, или он не ваш',
    'duplicate_track': 'Этот трек уже есть в плейлисте',
    'too_many_tracks': 'В плейлисте может быть до 5000 треков',
    'album_needs_artist': 'У альбома должен быть артист',
    'invalid_metadata': 'Название, артист и альбом: до 500 символов',
    'invalid_title': 'Название слишком длинное или пустое',
    'invalid_query': 'Запрос: до 200 символов',
    'client_outdated': 'Обновите приложение',
    'rate_limited': 'Слишком много запросов, подождите немного',
  };

  final SessionStore _store;

  /// Called when the server has ended the session, so that the app can ask to log in again.
  void Function()? onSessionExpired;

  /// Called when the server refuses this version of the app.
  void Function()? onClientOutdated;

  ApiService(this._store) {
    for (final dio in [_dio, _authDio]) {
      dio.options.headers['X-Client'] =
          '${Platform.operatingSystem}/$kAppVersion';
    }
    _authDio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          _noticeOutdated(error);
          handler.next(error);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
        onError: _retryWithNewToken,
      ),
    );
  }

  final Dio _dio = Dio(_options());

  // Refreshing goes around the interceptors of _dio, which would wait for it.
  final Dio _authDio = Dio(_options());

  static BaseOptions _options() => BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  );

  String _serverUrl = defaultServerUrl;
  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  Future<bool>? _refreshing;

  String get serverUrl => _serverUrl;
  String? get userId => _userId;
  bool get isAuthorized => _refreshToken != null && _userId != null;

  void close() {
    _dio.close(force: true);
    _authDio.close(force: true);
  }

  Future<void> init() async {
    final server = await _store.read(_keyServer);
    _setServer(server ?? defaultServerUrl);
    _accessToken = await _store.read(_keyAccess);
    _refreshToken = await _store.read(_keyRefresh);
    _userId = await _store.read(_keyUser);

    // With no server chosen, whatever is in the store came from an older version of the app.
    if (server == null) await _store.deleteAll();
  }

  void _setServer(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isNotEmpty && !normalized.contains('://')) {
      normalized = 'https://$normalized';
    }
    _serverUrl = normalized;
    _dio.options.baseUrl = normalized;
    _authDio.options.baseUrl = normalized;
  }

  // ---- Accounts ----

  Future<void> login(String server, String username, String password) =>
      _enter('/api/v1/auth/login', server, username, password);

  Future<void> register(String server, String username, String password) =>
      _enter('/api/v1/auth/register', server, username, password);

  Future<void> _enter(
    String path,
    String server,
    String username,
    String password,
  ) async {
    _setServer(server);
    if (_serverUrl.isEmpty) {
      throw const ApiException(null, 'no_server', 'Укажите адрес сервера');
    }
    final data = await _call(
      () => _authDio.post(
        path,
        data: {
          'username': username.trim(),
          'password': password,
          'device': _deviceInfo(),
        },
      ),
    );
    await _keepTokens(data as Map<String, dynamic>);
    final me = await _call(() => _dio.get('/api/v1/me'));
    _userId = me['id'] as String;
    await _store.write(_keyUser, _userId!);
    await _store.write(_keyServer, _serverUrl);
  }

  Map<String, String> _deviceInfo() {
    final os = Platform.operatingSystem;
    return {'name': 'MusicBay ($os)', 'platform': os};
  }

  Future<void> _keepTokens(Map<String, dynamic> session) async {
    _accessToken = session['access_token'] as String;
    _refreshToken = session['refresh_token'] as String;
    await _store.write(_keyAccess, _accessToken!);
    await _store.write(_keyRefresh, _refreshToken!);
  }

  Future<void> logout() async {
    final refreshToken = _refreshToken;
    await _forgetSession();
    if (refreshToken == null) return;
    try {
      await _authDio.post(
        '/api/v1/auth/logout',
        data: {'refresh_token': refreshToken},
      );
    } on DioException {
      // The device is logged out here anyway, and its session runs out on the server.
    }
  }

  Future<void> _forgetSession() async {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    await _store.delete(_keyAccess);
    await _store.delete(_keyRefresh);
    await _store.delete(_keyUser);
  }

  void _noticeOutdated(DioException error) {
    if (error.response?.statusCode == 426) onClientOutdated?.call();
  }

  Future<void> _retryWithNewToken(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    _noticeOutdated(error);
    final options = error.requestOptions;
    if (error.response?.statusCode != 401 || options.extra['retried'] == true) {
      handler.next(error);
      return;
    }
    if (!await _refreshOnce()) {
      handler.next(error);
      return;
    }
    options.extra['retried'] = true;
    options.headers['Authorization'] = 'Bearer $_accessToken';
    try {
      handler.resolve(await _dio.fetch(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  // A refresh token works once, so requests that fail together must share one refresh.
  Future<bool> _refreshOnce() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _authDio.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      await _keepTokens(response.data as Map<String, dynamic>);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _forgetSession();
        onSessionExpired?.call();
      }
      return false;
    }
  }

  /// Returns the name of the user.
  Future<String> getMe() async {
    final me = await _call(() => _dio.get('/api/v1/me'));
    return me['username'] as String;
  }

  Future<Quota> getQuota() async {
    final data = await _call(() => _dio.get('/api/v1/me/quota'));
    return Quota(
      (data['used_bytes'] as num).toInt(),
      (data['quota_bytes'] as num).toInt(),
      (data['uploads_today'] as num).toInt(),
      (data['uploads_per_day'] as num).toInt(),
    );
  }

  Future<List<Device>> getDevices() async {
    final data = await _call(() => _dio.get('/api/v1/me/devices'));
    final items = (data['items'] as List?) ?? const [];
    return items
        .map(
          (e) => Device(
            e['id'] as String,
            e['name'] as String,
            e['platform'] as String,
            e['current'] == true,
          ),
        )
        .toList(growable: false);
  }

  Future<void> logoutDevice(String id) async {
    await _call(() => _dio.delete('/api/v1/me/devices/$id'));
  }

  // ---- Tracks ----

  Future<dynamic> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final response = e.response;
    if (response == null) {
      return const ApiException(null, 'network', 'Сервер недоступен');
    }
    final error = response.data is Map ? response.data['error'] : null;
    if (error is! Map) {
      return ApiException(
        response.statusCode,
        'unknown',
        'Ошибка сервера: ${response.statusCode}',
      );
    }
    final code = error['code'] as String? ?? 'unknown';
    return ApiException(
      response.statusCode,
      code,
      _messages[code] ?? error['message'] as String? ?? 'Ошибка сервера',
      Map<String, dynamic>.from(error['details'] as Map? ?? const {}),
    );
  }

  TrackPage _trackPage(dynamic data, [String field = 'items']) {
    final items = (data[field] as List?) ?? const [];
    return TrackPage(
      items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
      data['next_cursor'] as String?,
    );
  }

  Map<String, dynamic> _page(String? cursor, int limit) => {
    'limit': limit,
    'cursor': ?cursor,
  };

  Future<TrackPage> getLibrary({String? cursor, int limit = 50}) async {
    final data = await _call(
      () => _dio.get('/api/v1/library', queryParameters: _page(cursor, limit)),
    );
    return _trackPage(data);
  }

  Future<TrackPage> search(
    String query, {
    String? cursor,
    int limit = 50,
  }) async {
    final data = await _call(
      () => _dio.get(
        '/api/v1/search',
        queryParameters: {'q': query, ..._page(cursor, limit)},
      ),
    );
    return _trackPage(data);
  }

  Future<Track> getTrack(String id) async {
    final data = await _call(() => _dio.get('/api/v1/tracks/$id'));
    return Track.fromJson(data as Map<String, dynamic>);
  }

  Future<void> addToLibrary(String trackId) async {
    await _call(() => _dio.put('/api/v1/library/$trackId'));
  }

  Future<void> removeFromLibrary(String trackId) async {
    await _call(() => _dio.delete('/api/v1/library/$trackId'));
  }

  /// Fields left null stay as they are. An empty artist or album removes it.
  Future<Track> updateTrack(
    String id, {
    String? title,
    String? artist,
    String? album,
    String? visibility,
  }) async {
    final data = await _call(
      () => _dio.patch(
        '/api/v1/tracks/$id',
        data: {
          'title': ?title,
          'artist': ?artist,
          'album': ?album,
          'visibility': ?visibility,
        },
      ),
    );
    return Track.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteTrack(String id) async {
    await _call(() => _dio.delete('/api/v1/tracks/$id'));
  }

  Future<List<Track>> getLikes() => _allPages('/api/v1/me/likes', 'items');

  Future<void> like(String trackId) async {
    await _call(() => _dio.put('/api/v1/tracks/$trackId/like'));
  }

  Future<void> unlike(String trackId) async {
    await _call(() => _dio.delete('/api/v1/tracks/$trackId/like'));
  }

  Future<void> reportPlay(String trackId) async {
    await _call(() => _dio.post('/api/v1/tracks/$trackId/play'));
  }

  // ---- Playlists and albums ----

  Future<List<Playlist>> getPlaylists() async {
    final playlists = <Playlist>[];
    String? cursor;
    do {
      final data = await _call(
        () =>
            _dio.get('/api/v1/playlists', queryParameters: _page(cursor, 200)),
      );
      final items = (data['items'] as List?) ?? const [];
      playlists.addAll(
        items.map((e) => Playlist.fromJson(e as Map<String, dynamic>)),
      );
      cursor = data['next_cursor'] as String?;
    } while (cursor != null);
    return playlists;
  }

  Future<Playlist> createPlaylist(String title) async {
    final data = await _call(
      () => _dio.post('/api/v1/playlists', data: {'title': title}),
    );
    return Playlist.fromJson(data as Map<String, dynamic>);
  }

  Future<void> renamePlaylist(String id, String title) async {
    await _call(
      () => _dio.patch('/api/v1/playlists/$id', data: {'title': title}),
    );
  }

  Future<void> deletePlaylist(String id) async {
    await _call(() => _dio.delete('/api/v1/playlists/$id'));
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    await _call(
      () => _dio.delete('/api/v1/playlists/$playlistId/tracks/$trackId'),
    );
  }

  Future<List<Track>> getPlaylistTracks(String playlistId) =>
      _allPages('/api/v1/playlists/$playlistId', 'tracks');

  Future<List<Track>> getAlbumTracks(String albumId) =>
      _allPages('/api/v1/albums/$albumId', 'items');

  Future<List<Track>> _allPages(String path, String field) async {
    final tracks = <Track>[];
    String? cursor;
    do {
      final data = await _call(
        () => _dio.get(path, queryParameters: _page(cursor, 200)),
      );
      final page = _trackPage(data, field);
      tracks.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return tracks;
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    await _call(
      () => _dio.post(
        '/api/v1/playlists/$playlistId/tracks',
        data: {'track_id': trackId},
      ),
    );
  }

  // ---- Uploads ----

  /// Sends a file in chunks, so that a broken connection costs one chunk and not the whole file.
  Future<Track> uploadFile(
    File file, {
    String visibility = 'private',
    void Function(double progress)? onProgress,
  }) async {
    final size = await file.length();
    final hash = await sha256.bind(file.openRead()).first;
    final session = await _call(
      () => _dio.post(
        '/api/v1/uploads',
        data: {
          'filename': file.uri.pathSegments.last,
          'size': size,
          'sha256': hash.toString(),
          'visibility': visibility,
        },
      ),
    );
    final uploadId = session['upload_id'] as String;
    final chunkSize = (session['chunk_size'] as num).toInt();

    final reader = await file.open();
    try {
      var offset = 0;
      while (offset < size) {
        await reader.setPosition(offset);
        final chunk = await reader.read(chunkSize);
        offset = await _sendChunk(uploadId, offset, chunk);
        onProgress?.call(offset / size);
      }
    } finally {
      await reader.close();
    }

    final track = await _call(
      () => _dio.post('/api/v1/uploads/$uploadId/complete'),
    );
    return Track.fromJson(track as Map<String, dynamic>);
  }

  /// Returns the offset to go on from, which the server decides.
  Future<int> _sendChunk(String uploadId, int offset, Uint8List chunk) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final response = await _dio.patch(
          '/api/v1/uploads/$uploadId',
          data: chunk,
          options: Options(
            sendTimeout: const Duration(minutes: 5),
            contentType: 'application/offset+octet-stream',
            headers: {
              'Upload-Offset': offset,
              Headers.contentLengthHeader: chunk.length,
            },
          ),
        );
        return int.parse(response.headers.value('upload-offset')!);
      } on DioException catch (e) {
        final error = _toApiException(e);
        if (error.code == 'offset_mismatch') {
          return int.parse(error.details['upload_offset'].toString());
        }
        if (!error.isNetwork || attempt >= _chunkAttempts) throw error;
      }
    }
  }
}

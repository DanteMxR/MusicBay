import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

class CacheService {
  static const String _boxName = 'cached_tracks';
  late Box<Map> _box;
  final Dio _dio = Dio();
  final Map<String, Future<String?>> _activeDownloads = {};

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  bool isTrackCached(int trackId, {int? ownerId}) {
    return getCachedPath(trackId, ownerId: ownerId) != null;
  }

  String? getCachedPath(int trackId, {int? ownerId}) {
    final data = _getEntry(trackId, ownerId: ownerId);
    if (data == null) return null;

    final path = data['path'] as String?;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        final expectedSize = (data['size_bytes'] as num?)?.toInt();
        if (expectedSize == null || expectedSize <= 0) {
          return path;
        }
        if (file.lengthSync() == expectedSize) {
          return path;
        }
      }
    }

    final key = _entryKey(trackId, ownerId: ownerId);
    if (_box.containsKey(key)) {
      _box.delete(key);
    }
    return null;
  }

  Future<String?> cacheTrack(
    Track track, {
    Function(double)? onProgress,
  }) async {
    if (track.url.isEmpty) return null;

    final key = _entryKey(track.id, ownerId: track.ownerId);
    final existingPath = getCachedPath(track.id, ownerId: track.ownerId);
    if (existingPath != null) return existingPath;

    final running = _activeDownloads[key];
    if (running != null) {
      return await running;
    }

    final task = _cacheTrackInternal(track, onProgress: onProgress);
    _activeDownloads[key] = task;
    try {
      return await task;
    } finally {
      _activeDownloads.remove(key);
    }
  }

  Future<String?> _cacheTrackInternal(
    Track track, {
    Function(double)? onProgress,
  }) async {
    if (track.url.isEmpty) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/music_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final ext = _inferAudioExtension(track.url);
      final filePath = '${cacheDir.path}/${track.ownerId}_${track.id}$ext';

      await _dio.download(
        track.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      await _box.put(_entryKey(track.id, ownerId: track.ownerId), {
        ...track.toJson(),
        'path': filePath,
        'size_bytes': File(filePath).lengthSync(),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });

      return filePath;
    } catch (e) {
      debugPrint('CacheService: download failed for ${track.id}: $e');
      return null;
    }
  }

  String _inferAudioExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final segment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      final dotIndex = segment.lastIndexOf('.');
      if (dotIndex == -1) return '.audio';
      final ext = segment.substring(dotIndex).toLowerCase();
      const allowed = {
        '.mp3',
        '.m4a',
        '.aac',
        '.ogg',
        '.wav',
        '.flac',
        '.opus',
        '.webm',
      };
      return allowed.contains(ext) ? ext : '.audio';
    } catch (_) {
      return '.audio';
    }
  }

  Future<int> cacheTracksIfNeeded(
    Iterable<Track> tracks, {
    int maxToDownload = 200,
  }) async {
    var cachedNow = 0;
    final unique = <String, Track>{};
    for (final track in tracks) {
      unique[_entryKey(track.id, ownerId: track.ownerId)] = track;
    }

    for (final track in unique.values) {
      if (maxToDownload <= 0) break;
      if (isTrackCached(track.id, ownerId: track.ownerId)) continue;
      final path = await cacheTrack(track);
      if (path != null) {
        cachedNow++;
        maxToDownload--;
      }
    }
    return cachedNow;
  }

  Future<void> removeFromCache(int trackId, {int? ownerId}) async {
    final key = _entryKey(trackId, ownerId: ownerId);
    final data = _box.get(key) ?? _getLegacyEntry(trackId, ownerId: ownerId);
    if (data != null) {
      final path = data['path'] as String?;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      await _box.delete(key);
      await _box.delete(trackId.toString());
    }
  }

  List<Track> getCachedTracks() {
    return _box.values.map((data) {
      final map = Map<String, dynamic>.from(data);
      return Track.fromCache(map);
    }).toList();
  }

  Future<int> getCacheSize() async {
    int totalSize = 0;
    for (final data in _box.values) {
      final path = data['path'] as String?;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          totalSize += file.lengthSync();
        }
      }
    }
    return totalSize;
  }

  Future<void> clearCache() async {
    for (final key in _box.keys.toList()) {
      final data = _box.get(key);
      if (data != null) {
        final path = data['path'] as String?;
        if (path != null) {
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
        }
      }
    }
    await _box.clear();
  }

  String _entryKey(int trackId, {int? ownerId}) {
    if (ownerId == null) return trackId.toString();
    return '${ownerId}_$trackId';
  }

  Map? _getEntry(int trackId, {int? ownerId}) {
    final key = _entryKey(trackId, ownerId: ownerId);
    final direct = _box.get(key);
    if (direct != null) return direct;
    return _getLegacyEntry(trackId, ownerId: ownerId);
  }

  Map? _getLegacyEntry(int trackId, {int? ownerId}) {
    final legacy = _box.get(trackId.toString());
    if (legacy == null) return null;
    if (ownerId == null) return legacy;
    final legacyOwnerId = (legacy['owner_id'] as num?)?.toInt();
    if (legacyOwnerId == ownerId) return legacy;
    return null;
  }
}

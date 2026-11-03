import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../constants.dart';
import '../models/track.dart';

class CacheService {
  static const String _boxName = 'server_tracks';
  late Box<Map> _box;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      // No receiveTimeout — file downloads may legitimately take a while.
    ),
  );
  final Map<String, Future<String?>> _activeDownloads = {};

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  bool isTrackCached(String trackId) {
    return getCachedPath(trackId) != null;
  }

  String? getCachedPath(String trackId) {
    final data = _box.get(trackId);
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

    if (_box.containsKey(trackId)) {
      _box.delete(trackId);
    }
    return null;
  }

  Future<String?> cacheTrack(
    Track track, {
    Function(double)? onProgress,
  }) async {
    if (track.url.isEmpty) return null;

    final key = track.id;
    final existingPath = getCachedPath(track.id);
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
      final filePath = '${cacheDir.path}/${track.id}$ext';

      await _dio.download(
        track.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      await _box.put(track.id, {
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
    int maxToDownload = kDefaultCacheBatchSize,
  }) async {
    var cachedNow = 0;
    final unique = <String, Track>{};
    for (final track in tracks) {
      unique[track.id] = track;
    }

    for (final track in unique.values) {
      if (maxToDownload <= 0) break;
      if (isTrackCached(track.id)) continue;
      final path = await cacheTrack(track);
      if (path != null) {
        cachedNow++;
        maxToDownload--;
      }
    }
    return cachedNow;
  }

  Future<void> removeFromCache(String trackId) async {
    final data = _box.get(trackId);
    if (data != null) {
      final path = data['path'] as String?;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      await _box.delete(trackId);
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
}

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

class CacheService {
  static const String _boxName = 'cached_tracks';
  late Box<Map> _box;
  final Dio _dio = Dio();

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  bool isTrackCached(int trackId) {
    return _box.containsKey(trackId.toString());
  }

  String? getCachedPath(int trackId) {
    final data = _box.get(trackId.toString());
    if (data == null) return null;
    final path = data['path'] as String?;
    if (path != null && File(path).existsSync()) return path;
    // File was deleted, clean up entry
    _box.delete(trackId.toString());
    return null;
  }

  Future<String?> cacheTrack(Track track,
      {Function(double)? onProgress}) async {
    if (track.url.isEmpty) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/music_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final filePath = '${cacheDir.path}/${track.ownerId}_${track.id}.mp3';

      await _dio.download(
        track.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      await _box.put(track.id.toString(), {
        ...track.toJson(),
        'path': filePath,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });

      return filePath;
    } catch (e) {
      return null;
    }
  }

  Future<void> removeFromCache(int trackId) async {
    final data = _box.get(trackId.toString());
    if (data != null) {
      final path = data['path'] as String?;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
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
}

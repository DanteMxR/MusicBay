import 'package:hive/hive.dart';
import '../models/track.dart';

class LibraryIndexService {
  static const String _boxName = 'library_index';
  static const String _tracksSuffix = 'my_tracks';
  static const String _updatedAtSuffix = 'updated_at';

  late Box<Map> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  List<Track> readMyTracks(int userId) {
    final raw = _box.get(_tracksKey(userId));
    if (raw == null) return const <Track>[];

    final items = (raw['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((item) => Track.fromCache(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  DateTime? readMyTracksUpdatedAt(int userId) {
    final raw = _box.get(_updatedAtKey(userId));
    final millis = (raw?['value'] as num?)?.toInt();
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  bool readMyTracksIsComplete(int userId) {
    final raw = _box.get(_updatedAtKey(userId));
    return raw?['is_complete'] == true;
  }

  Future<void> writeMyTracks(
    int userId,
    List<Track> tracks, {
    required bool isComplete,
  }) async {
    await _box.put(_tracksKey(userId), {
      'items': tracks.map((track) => track.toJson()).toList(growable: false),
    });
    await _box.put(_updatedAtKey(userId), {
      'value': DateTime.now().millisecondsSinceEpoch,
      'is_complete': isComplete,
    });
  }

  Future<void> clearMyTracks(int userId) async {
    await _box.delete(_tracksKey(userId));
    await _box.delete(_updatedAtKey(userId));
  }

  String _tracksKey(int userId) => '${userId}_$_tracksSuffix';
  String _updatedAtKey(int userId) => '${userId}_$_updatedAtSuffix';
}

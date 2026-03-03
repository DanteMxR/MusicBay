import 'dart:developer' as developer;

class Track {
  final int id;
  final int ownerId;
  final String artist;
  final String title;
  final int duration;
  final String url;
  final String? albumThumb;
  final int? albumId;
  final int? albumOwnerId;
  final String? albumTitle;
  final bool isExplicit;

  Track({
    required this.id,
    required this.ownerId,
    required this.artist,
    required this.title,
    required this.duration,
    required this.url,
    this.albumThumb,
    this.albumId,
    this.albumOwnerId,
    this.albumTitle,
    this.isExplicit = false,
  });

  String get accessKey => '${ownerId}_$id';

  String get durationFormatted {
    final min = duration ~/ 60;
    final sec = duration % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    final thumb = _extractThumb(json);

    // Extract album info - VK API can return it in different formats
    int? albumId;
    int? albumOwnerId;
    String? albumTitle;
    
    // Try standard album object
    if (json['album'] != null) {
      albumId = json['album']['id'];
      albumOwnerId = json['album']['owner_id'];
      albumTitle = json['album']['title'];
    }
    
    // Also check for direct fields (some API endpoints return them this way)
    albumId ??= json['album_id'];
    albumOwnerId ??= json['album_owner_id'];
    albumTitle ??= json['album_title'];

    // Debug logging for album info
    if (albumId != null) {
      developer.log(
        'Track "${json['title']}" has album: id=$albumId, owner=$albumOwnerId, title=$albumTitle',
        name: 'Track',
      );
    } else {
      developer.log(
        'Track "${json['title']}" has NO album info',
        name: 'Track',
      );
    }

    return Track(
      id: json['id'] ?? 0,
      ownerId: json['owner_id'] ?? 0,
      artist: json['artist'] ?? 'Unknown',
      title: json['title'] ?? 'Unknown',
      duration: json['duration'] ?? 0,
      url: json['url'] ?? '',
      albumThumb: thumb,
      albumId: albumId,
      albumOwnerId: albumOwnerId,
      albumTitle: albumTitle,
      isExplicit: json['is_explicit'] == true,
    );
  }

  static String? _extractThumb(Map<String, dynamic> json) {
    final candidates = <dynamic>[
      json['album'],
      json['album']?['thumb'],
      json['album']?['photo'],
      json['track_covers'],
      json['thumb'],
      json['photo'],
      json['cover_url'],
      json['artwork_url'],
      json['main_artists'],
    ];

    for (final candidate in candidates) {
      final extracted = _extractImageFromDynamic(candidate);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }

    final deep = _extractImageFromDynamic(json);
    if (deep != null && deep.isNotEmpty) return deep;
    return null;
  }

  static String? _extractImageFromDynamic(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final normalized = _normalizeImageUrl(value);
      if (normalized != null) {
        return normalized;
      }
      return null;
    }

    if (value is List) {
      for (final item in value) {
        final extracted = _extractImageFromDynamic(item);
        if (extracted != null) return extracted;
      }
      return null;
    }

    if (value is Map) {
      const preferredKeys = [
        'photo_1200',
        'photo_800',
        'photo_600',
        'photo_500',
        'photo_300',
        'photo_270',
        'photo_200',
        'photo_135',
        'photo_68',
        'url',
        'cover_url',
        'artwork_url',
      ];

      for (final key in preferredKeys) {
        final extracted = _extractImageFromDynamic(value[key]);
        if (extracted != null) return extracted;
      }

      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key.contains('photo') ||
            key.contains('thumb') ||
            key.contains('cover') ||
            key.contains('image') ||
            key.contains('artwork')) {
          final extracted = _extractImageFromDynamic(entry.value);
          if (extracted != null) return extracted;
        }
      }

      for (final nested in value.values) {
        final extracted = _extractImageFromDynamic(nested);
        if (extracted != null) return extracted;
      }
    }

    return null;
  }

  static String? _normalizeImageUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;

    value = value.replaceAll(r'\/', '/');
    if (value.startsWith('//')) {
      value = 'https:$value';
    }
    if (value.startsWith('http://')) {
      value = 'https://${value.substring(7)}';
    }

    final lower = value.toLowerCase();
    if (!lower.startsWith('https://')) return null;
    if (_looksLikeNonImage(lower)) return null;
    return value;
  }

  static bool _looksLikeNonImage(String lowerUrl) {
    const nonImageExt = [
      '.mp3',
      '.m4a',
      '.aac',
      '.ogg',
      '.wav',
      '.flac',
      '.opus',
      '.webm',
      '.mp4',
      '.mkv',
      '.m3u8',
      '.ts',
    ];
    for (final ext in nonImageExt) {
      if (lowerUrl.contains(ext)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'artist': artist,
    'title': title,
    'duration': duration,
    'url': url,
    'album_thumb': albumThumb,
    'album_id': albumId,
    'album_owner_id': albumOwnerId,
    'album_title': albumTitle,
    'is_explicit': isExplicit,
  };

  factory Track.fromCache(Map<String, dynamic> json) => Track(
    id: json['id'],
    ownerId: json['owner_id'],
    artist: json['artist'],
    title: json['title'],
    duration: json['duration'],
    url: json['url'] ?? '',
    albumThumb: json['album_thumb'],
    albumId: json['album_id'],
    albumOwnerId: json['album_owner_id'],
    albumTitle: json['album_title'],
    isExplicit: json['is_explicit'] ?? false,
  );
}

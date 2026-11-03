class Track {
  /// The quality to play, from the settings. A track without it gets the closest one it has.
  static String preferredQuality = 'normal';

  static const List<String> qualities = ['low', 'normal', 'lossless'];

  final String id;
  final String artist;
  final String? artistId;
  final String title;
  final int duration;
  final Map<String, String> streams;
  final String _localPath;
  final String? albumThumb;
  final String? albumId;
  final String? albumTitle;
  final String status;
  final String? error;
  final String visibility;
  final int plays;
  final bool liked;
  final bool inLibrary;

  Track({
    required this.id,
    required this.artist,
    this.artistId,
    required this.title,
    required this.duration,
    this.streams = const {},
    String localPath = '',
    this.albumThumb,
    this.albumId,
    this.albumTitle,
    this.status = 'ready',
    this.error,
    this.visibility = 'private',
    this.plays = 0,
    this.liked = false,
    this.inLibrary = false,
  }) : _localPath = localPath;

  String get accessKey => id;

  /// A file on the device if it has one, otherwise a stream of the preferred quality.
  String get url {
    if (_localPath.isNotEmpty) return _localPath;
    final order = [
      preferredQuality,
      ...qualities.where((q) => q != preferredQuality),
    ];
    for (final quality in order) {
      final link = streams[quality];
      if (link != null && link.isNotEmpty) return link;
    }
    return '';
  }

  bool get isProcessing => status == 'pending' || status == 'processing';
  bool get isFailed => status == 'failed';

  String get durationFormatted {
    final min = duration ~/ 60;
    final sec = duration % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  /// A link to a stream is signed and expires, and tracks kept on disk outlive it.
  bool get isLinkStale {
    final link = url;
    if (!link.startsWith('http')) return false;
    final expires = int.tryParse(
      Uri.tryParse(link)?.queryParameters['exp'] ?? '',
    );
    if (expires == null) return false;
    final margin = DateTime.now().add(const Duration(minutes: 10));
    return DateTime.fromMillisecondsSinceEpoch(expires * 1000).isBefore(margin);
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    final artist = json['artist'] as Map?;
    final album = json['album'] as Map?;
    final streams = <String, String>{};
    (json['streams'] as Map?)?.forEach((quality, stream) {
      final link = (stream as Map?)?['url'] as String?;
      if (link != null) streams[quality as String] = link;
    });
    return Track(
      id: json['id'] as String,
      artist: artist?['name'] as String? ?? 'Неизвестный артист',
      artistId: artist?['id'] as String?,
      title: json['title'] as String? ?? 'Без названия',
      duration: ((json['duration_ms'] as num?)?.toInt() ?? 0) ~/ 1000,
      streams: streams,
      albumThumb: _pickCover(json['covers'] as Map?),
      albumId: album?['id'] as String?,
      albumTitle: album?['name'] as String?,
      status: json['status'] as String? ?? 'pending',
      error: json['error'] as String?,
      visibility: json['visibility'] as String? ?? 'private',
      plays: (json['plays'] as num?)?.toInt() ?? 0,
      liked: json['liked'] == true,
      inLibrary: json['in_library'] == true,
    );
  }

  static String? _pickCover(Map? covers) {
    if (covers == null) return null;
    for (final size in const ['600', '300', '128']) {
      final url = covers[size] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  Track copyWithUrl(String localPath) => Track(
    id: id,
    artist: artist,
    artistId: artistId,
    title: title,
    duration: duration,
    streams: streams,
    localPath: localPath,
    albumThumb: albumThumb,
    albumId: albumId,
    albumTitle: albumTitle,
    status: status,
    error: error,
    visibility: visibility,
    plays: plays,
    liked: liked,
    inLibrary: inLibrary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'artist': artist,
    'artist_id': artistId,
    'title': title,
    'duration': duration,
    'streams': streams,
    'album_thumb': albumThumb,
    'album_id': albumId,
    'album_title': albumTitle,
    'status': status,
    'error': error,
    'visibility': visibility,
    'plays': plays,
    'liked': liked,
    'in_library': inLibrary,
  };

  factory Track.fromCache(Map<String, dynamic> json) => Track(
    id: json['id'],
    artist: json['artist'],
    artistId: json['artist_id'],
    title: json['title'],
    duration: json['duration'],
    streams: Map<String, String>.from((json['streams'] as Map?) ?? const {}),
    albumThumb: json['album_thumb'],
    albumId: json['album_id'],
    albumTitle: json['album_title'],
    status: json['status'] ?? 'ready',
    error: json['error'],
    visibility: json['visibility'] ?? 'private',
    plays: json['plays'] ?? 0,
    liked: json['liked'] ?? false,
    inLibrary: json['in_library'] ?? false,
  );
}

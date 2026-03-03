class Track {
  final int id;
  final int ownerId;
  final String artist;
  final String title;
  final int duration;
  final String url;
  final String? albumThumb;
  final int? albumId;
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
    this.isExplicit = false,
  });

  String get accessKey => '${ownerId}_$id';

  String get durationFormatted {
    final min = duration ~/ 60;
    final sec = duration % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    String? thumb;
    if (json['album'] != null && json['album']['thumb'] != null) {
      thumb = json['album']['thumb']['photo_300'] ??
          json['album']['thumb']['photo_270'] ??
          json['album']['thumb']['photo_135'] ??
          json['album']['thumb']['photo_68'];
    }

    return Track(
      id: json['id'] ?? 0,
      ownerId: json['owner_id'] ?? 0,
      artist: json['artist'] ?? 'Unknown',
      title: json['title'] ?? 'Unknown',
      duration: json['duration'] ?? 0,
      url: json['url'] ?? '',
      albumThumb: thumb,
      albumId: json['album']?['id'],
      isExplicit: json['is_explicit'] == true,
    );
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
        isExplicit: json['is_explicit'] ?? false,
      );
}

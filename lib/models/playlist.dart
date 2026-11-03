enum PlaylistKind {
  /// A list made by the user, which they can change.
  own,

  /// An album of the catalog, made from the tags of tracks.
  album,

  /// The tracks the user likes.
  liked,
}

class Playlist {
  final String id;
  final String title;
  final String? description;
  final String? photo;
  final int count;
  final String visibility;
  final PlaylistKind kind;

  Playlist({
    required this.id,
    required this.title,
    this.description,
    this.photo,
    required this.count,
    this.visibility = 'private',
    this.kind = PlaylistKind.own,
  });

  bool get isOwn => kind == PlaylistKind.own;

  factory Playlist.liked() => Playlist(
    id: 'liked',
    title: 'Любимые',
    count: 0,
    kind: PlaylistKind.liked,
  );

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Без названия',
      count: (json['track_count'] as num?)?.toInt() ?? 0,
      visibility: json['visibility'] as String? ?? 'private',
    );
  }
}

class Playlist {
  final int id;
  final int ownerId;
  final String title;
  final String? description;
  final String? photo;
  final int count;
  final int createTime;
  final int updateTime;

  Playlist({
    required this.id,
    required this.ownerId,
    required this.title,
    this.description,
    this.photo,
    required this.count,
    required this.createTime,
    required this.updateTime,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    String? photo;
    if (json['photo'] != null) {
      photo = json['photo']['photo_300'] ??
          json['photo']['photo_270'] ??
          json['photo']['photo_135'];
    } else if (json['thumbs'] != null && (json['thumbs'] as List).isNotEmpty) {
      final thumbs = json['thumbs'] as List;
      photo = thumbs[0]['photo_300'] ??
          thumbs[0]['photo_270'] ??
          thumbs[0]['photo_135'];
    }

    return Playlist(
      id: json['id'] ?? 0,
      ownerId: json['owner_id'] ?? 0,
      title: json['title'] ?? 'Unknown',
      description: json['description'],
      photo: photo,
      count: json['count'] ?? 0,
      createTime: json['create_time'] ?? 0,
      updateTime: json['update_time'] ?? 0,
    );
  }
}

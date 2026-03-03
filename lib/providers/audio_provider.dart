import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';

class AudioProvider extends ChangeNotifier {
  final AudioPlayerService _audioService;
  final CacheService _cacheService;

  AudioProvider(this._audioService, this._cacheService) {
    _audioService.currentIndexStream.listen((_) => notifyListeners());
    _audioService.playerStateStream.listen((_) => notifyListeners());
  }

  AudioPlayerService get audioService => _audioService;
  Track? get currentTrack => _audioService.currentTrack;
  List<Track> get queue => _audioService.tracks;
  int get currentIndex => _audioService.currentIndex;
  bool get isPlaying => _audioService.isPlaying;
  RepeatMode get repeatMode => _audioService.repeatMode;
  bool get shuffle => _audioService.shuffle;

  Stream<Duration> get positionStream => _audioService.positionStream;
  Stream<Duration?> get durationStream => _audioService.durationStream;
  Stream<PlayerState> get playerStateStream =>
      _audioService.playerStateStream;

  Future<void> playPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    // Replace URLs with cached paths where available
    final resolvedTracks = tracks.map((track) {
      final cachedPath = _cacheService.getCachedPath(track.id);
      if (cachedPath != null) {
        return Track(
          id: track.id,
          ownerId: track.ownerId,
          artist: track.artist,
          title: track.title,
          duration: track.duration,
          url: cachedPath,
          albumThumb: track.albumThumb,
          albumId: track.albumId,
          isExplicit: track.isExplicit,
        );
      }
      return track;
    }).toList();

    await _audioService.setPlaylist(resolvedTracks, startIndex: startIndex);
    await _audioService.play();
    notifyListeners();
  }

  Future<void> playPause() async {
    await _audioService.playPause();
    notifyListeners();
  }

  Future<void> next() async {
    await _audioService.next();
    notifyListeners();
  }

  Future<void> previous() async {
    await _audioService.previous();
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    await _audioService.seekTo(position);
  }

  Future<void> playTrackAt(int index) async {
    await _audioService.playTrackAt(index);
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    await _audioService.toggleRepeat();
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    await _audioService.toggleShuffle();
    notifyListeners();
  }
}

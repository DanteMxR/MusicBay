import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import 'vk_provider.dart';

class AudioProvider extends ChangeNotifier {
  final AudioPlayerService _audioService;
  final CacheService _cacheService;
  final VkProvider _vkProvider;
  bool _switchingPlaylist = false;
  bool _autoCachingTrack = false;
  int? _lastAutoCacheTrackId;
  Duration? _lastObservedPosition;
  DateTime? _lastObservedAt;
  DateTime? _lastRecoveryAt;
  int? _lastRecoveredTrackId;

  AudioProvider(this._audioService, this._cacheService, this._vkProvider) {
    _audioService.currentIndexStream.listen((_) {
      notifyListeners();
      _resetPlaybackWatchdog();
      unawaited(_cacheCurrentTrackIfNeeded());
    });
    _audioService.playerStateStream.listen((_) {
      notifyListeners();
      unawaited(_cacheCurrentTrackIfNeeded());
    });
    positionStream.listen((position) {
      unawaited(_detectAndRecoverPlaybackGlitch(position));
    });
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
  Stream<PlayerState> get playerStateStream => _audioService.playerStateStream;

  Future<void> playPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    if (_switchingPlaylist) return;
    _switchingPlaylist = true;
    // Replace URLs with cached paths where available
    try {
      final resolvedTracks = tracks.map((track) {
        final cachedPath = _cacheService.getCachedPath(
          track.id,
          ownerId: track.ownerId,
        );
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
      await _cacheCurrentTrackIfNeeded();
      notifyListeners();
    } catch (e) {
      debugPrint('playPlaylist error: $e');
    } finally {
      _switchingPlaylist = false;
    }
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

  Future<void> _cacheCurrentTrackIfNeeded() async {
    final track = currentTrack;
    if (track == null) return;
    if (!isPlaying) return;
    if (!_vkProvider.isTrackSaved(track.id, ownerId: track.ownerId)) return;
    if (_cacheService.isTrackCached(track.id, ownerId: track.ownerId)) return;
    if (_lastAutoCacheTrackId == track.id) return;
    if (_autoCachingTrack) return;

    _autoCachingTrack = true;
    try {
      final path = await _cacheService.cacheTrack(track);
      if (path != null) {
        _lastAutoCacheTrackId = track.id;
      }
    } finally {
      _autoCachingTrack = false;
    }
  }

  void _resetPlaybackWatchdog() {
    _lastObservedPosition = null;
    _lastObservedAt = null;
  }

  Future<void> _detectAndRecoverPlaybackGlitch(Duration position) async {
    if (!isPlaying) {
      _lastObservedPosition = position;
      _lastObservedAt = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final prevPos = _lastObservedPosition;
    final prevAt = _lastObservedAt;
    _lastObservedPosition = position;
    _lastObservedAt = now;

    if (prevPos == null || prevAt == null) return;

    final elapsedMs = now.difference(prevAt).inMilliseconds;
    final advancedMs = position.inMilliseconds - prevPos.inMilliseconds;
    if (elapsedMs < 500 || advancedMs <= 0) return;

    // Ignore seeks and large jumps initiated by user/system.
    if (advancedMs > 8000) return;

    final ratio = advancedMs / elapsedMs;
    if (ratio < 1.35) return;

    final track = currentTrack;
    if (track == null) return;

    if (_lastRecoveredTrackId == track.id && _lastRecoveryAt != null) {
      final cooldown = now.difference(_lastRecoveryAt!).inSeconds;
      if (cooldown < 20) return;
    }

    _lastRecoveredTrackId = track.id;
    _lastRecoveryAt = now;
    await _audioService.recoverDecoderGlitch();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../constants.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';

typedef IsTrackSavedCallback = bool Function(int trackId, {int? ownerId});

class AudioProvider extends ChangeNotifier {
  final AudioPlayerService _audioService;
  final CacheService _cacheService;
  final IsTrackSavedCallback _isTrackSaved;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _autoCachingTrack = false;
  String? _lastAutoCacheTrackKey;
  Duration? _lastObservedPosition;
  DateTime? _lastObservedAt;
  DateTime? _lastRecoveryAt;
  int? _lastRecoveredTrackId;
  bool _disposed = false;

  AudioProvider(this._audioService, this._cacheService, this._isTrackSaved) {
    _subscriptions.add(
      _audioService.currentIndexStream.listen((_) {
        _safeNotifyListeners();
        _resetPlaybackWatchdog();
        unawaited(_cacheCurrentTrackIfNeeded());
      }),
    );
    _subscriptions.add(
      _audioService.playerStateStream.listen((_) {
        _safeNotifyListeners();
        unawaited(_cacheCurrentTrackIfNeeded());
      }),
    );
    _subscriptions.add(
      positionStream.listen((position) {
        unawaited(_detectAndRecoverPlaybackGlitch(position));
      }),
    );
  }

  AudioPlayerService get audioService => _audioService;
  Track? get currentTrack => _audioService.currentTrack;
  List<Track> get queue => _audioService.tracks;
  int get currentIndex => _audioService.currentIndex;
  bool get isPlaying => _audioService.isPlaying;
  RepeatMode get repeatMode => _audioService.repeatMode;
  bool get shuffle => _audioService.shuffle;

  bool isPlayingTrack(Track track) {
    final current = _audioService.currentTrack;
    return current != null && _isSameTrack(current, track);
  }

  Track _resolveTrackWithCache(Track track) {
    final cachedPath = _cacheService.getCachedPath(track.id, ownerId: track.ownerId);
    if (cachedPath != null) return track.copyWithUrl(cachedPath);
    return track;
  }

  List<Track> _resolveTracksWithCache(List<Track> tracks) {
    return tracks.map(_resolveTrackWithCache).toList(growable: false);
  }

  Future<void> playPauseTrack(
    Track track,
    List<Track> playlist, {
    int startIndex = 0,
  }) async {
    final resolvedTrack = _resolveTrackWithCache(track);
    if (resolvedTrack.url.trim().isEmpty) return;

    final isCurrentTrack = isPlayingTrack(resolvedTrack);

    if (isCurrentTrack) {
      await playPause();
    } else {
      final resolvedPlaylist = _resolveTracksWithCache(playlist);
      final playable = resolvedPlaylist
          .where((t) => t.url.trim().isNotEmpty)
          .toList(growable: false);
      if (playable.isEmpty) return;

      var resolvedIndex = _resolvePlayableIndex(
        track: resolvedTrack,
        playlist: resolvedPlaylist,
        playable: playable,
        startIndex: startIndex,
      );

      if (resolvedIndex < 0) {
        debugPrint(
          'playPauseTrack: unable to resolve index for ${track.ownerId}_${track.id}',
        );
        return;
      }
      await playPlaylist(playable, startIndex: resolvedIndex);
    }
  }

  Stream<Duration> get positionStream => _audioService.positionStream;
  Stream<Duration?> get durationStream => _audioService.durationStream;
  Stream<PlayerState> get playerStateStream => _audioService.playerStateStream;

  Future<void> playPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    final resolved = _resolveTracksWithCache(tracks);
    final playableTracks = resolved
        .where((t) => t.url.trim().isNotEmpty)
        .toList(growable: false);
    if (playableTracks.isEmpty) return;

    final safeStartIndex = startIndex.clamp(0, playableTracks.length - 1);
    try {
      if (_isSamePlaylist(playableTracks)) {
        if (safeStartIndex == _audioService.currentIndex) {
          if (!_audioService.isPlaying) {
            await _audioService.play();
          }
        } else {
          await _audioService.playTrackAt(safeStartIndex);
        }
        notifyListeners();
        return;
      }

      await _audioService.setPlaylist(
        playableTracks,
        startIndex: safeStartIndex,
      );
      await _audioService.play();
      await _cacheCurrentTrackIfNeeded();
      notifyListeners();
    } catch (e) {
      debugPrint('playPlaylist error: $e');
    }
  }

  int _mapOriginalIndexToPlayableIndex({
    required List<Track> playlist,
    required int originalIndex,
  }) {
    if (playlist.isEmpty) return -1;
    final safeOriginalIndex = originalIndex.clamp(0, playlist.length - 1);
    if (playlist[safeOriginalIndex].url.trim().isEmpty) return -1;

    var playableIndex = 0;
    for (var i = 0; i < playlist.length; i++) {
      final hasUrl = playlist[i].url.trim().isNotEmpty;
      if (!hasUrl) continue;
      if (i == safeOriginalIndex) return playableIndex;
      playableIndex++;
    }
    return -1;
  }

  int _resolvePlayableIndex({
    required Track track,
    required List<Track> playlist,
    required List<Track> playable,
    required int startIndex,
  }) {
    // Prefer tapped index first, then fallback to track matching.
    final byOriginalIndex = _mapOriginalIndexToPlayableIndex(
      playlist: playlist,
      originalIndex: startIndex,
    );
    if (byOriginalIndex >= 0 &&
        byOriginalIndex < playable.length &&
        _isSameTrack(playable[byOriginalIndex], track)) {
      return byOriginalIndex;
    }

    var byExactTrack = playable.indexWhere((t) => _isSameTrack(t, track));
    if (byExactTrack >= 0) return byExactTrack;

    byExactTrack = playable.indexWhere(
      (t) =>
          t.id == track.id &&
          t.ownerId == track.ownerId &&
          t.url == track.url,
    );
    if (byExactTrack >= 0) return byExactTrack;

    byExactTrack = playable.indexWhere(
      (t) => t.id == track.id && t.ownerId == track.ownerId,
    );
    if (byExactTrack >= 0) return byExactTrack;

    byExactTrack = playable.indexWhere(
      (t) =>
          t.url.trim().isNotEmpty &&
          t.url == track.url &&
          t.duration == track.duration,
    );
    return byExactTrack;
  }

  bool _isSameTrack(Track a, Track b) {
    final aHasIdentity = a.id > 0 && a.ownerId != 0;
    final bHasIdentity = b.id > 0 && b.ownerId != 0;
    if (aHasIdentity && bHasIdentity) {
      if (a.id != b.id || a.ownerId != b.ownerId) return false;

      final aUrl = a.url.trim();
      final bUrl = b.url.trim();
      if (aUrl.isNotEmpty && bUrl.isNotEmpty && aUrl != bUrl) {
        return false;
      }
      return true;
    }

    final aUrl = a.url.trim();
    final bUrl = b.url.trim();
    if (aUrl.isNotEmpty && bUrl.isNotEmpty) {
      return aUrl == bUrl;
    }

    return a.artist == b.artist &&
        a.title == b.title &&
        a.duration == b.duration;
  }

  bool _isSamePlaylist(List<Track> tracks) {
    final current = _audioService.tracks;
    if (current.isEmpty) return false;
    if (current.any((t) => _isLocalPath(t.url))) return false;
    if (current.length != tracks.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id != tracks[i].id ||
          current[i].ownerId != tracks[i].ownerId ||
          current[i].url != tracks[i].url) {
        return false;
      }
    }
    return true;
  }

  bool _isLocalPath(String path) {
    if (path.startsWith('/')) return true;
    if (path.length >= 2 && path[1] == ':') {
      final drive = path[0].toUpperCase().codeUnitAt(0);
      return drive >= 65 && drive <= 90; // A-Z
    }
    return false;
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
    final trackKey = _trackKey(track);
    if (!isPlaying) return;
    if (!_isTrackSaved(track.id, ownerId: track.ownerId)) return;
    if (_cacheService.isTrackCached(track.id, ownerId: track.ownerId)) return;
    if (_lastAutoCacheTrackKey == trackKey) return;
    if (_autoCachingTrack) return;

    _autoCachingTrack = true;
    try {
      final path = await _cacheService.cacheTrack(track);
      if (path != null) {
        _lastAutoCacheTrackKey = trackKey;
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
    if (advancedMs > kPlaybackGlitchLargeJumpMs) return;

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

  String _trackKey(Track track) => '${track.ownerId}_${track.id}';

  void _safeNotifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    super.dispose();
  }
}

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
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _switchingPlaylist = false;
  bool _autoCachingTrack = false;
  String? _lastAutoCacheTrackKey;
  Duration? _lastObservedPosition;
  DateTime? _lastObservedAt;
  DateTime? _lastRecoveryAt;
  int? _lastRecoveredTrackId;
  bool _disposed = false;

  AudioProvider(this._audioService, this._cacheService, this._vkProvider) {
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
    return current != null &&
        current.id == track.id &&
        current.ownerId == track.ownerId;
  }

  Future<void> playPauseTrack(
    Track track,
    List<Track> playlist, {
    int startIndex = 0,
  }) async {
    if (track.url.trim().isEmpty) return;

    final isCurrentTrack = isPlayingTrack(track);

    if (isCurrentTrack) {
      await playPause();
    } else {
      final playable = playlist
          .where((t) => t.url.trim().isNotEmpty)
          .toList(growable: false);
      if (playable.isEmpty) return;

      var resolvedIndex = playable.indexWhere(
        (t) => t.id == track.id && t.ownerId == track.ownerId,
      );

      if (resolvedIndex < 0 && playlist.isNotEmpty) {
        final clamped = startIndex.clamp(0, playlist.length - 1);
        final candidate = playlist[clamped];
        resolvedIndex = playable.indexWhere(
          (t) => t.id == candidate.id && t.ownerId == candidate.ownerId,
        );
      }

      if (resolvedIndex < 0) resolvedIndex = 0;
      await playPlaylist(playable, startIndex: resolvedIndex);
    }
  }

  Stream<Duration> get positionStream => _audioService.positionStream;
  Stream<Duration?> get durationStream => _audioService.durationStream;
  Stream<PlayerState> get playerStateStream => _audioService.playerStateStream;

  Future<void> playPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    final playableTracks = tracks
        .where((t) => t.url.trim().isNotEmpty)
        .toList(growable: false);
    if (playableTracks.isEmpty) return;

    final safeStartIndex = startIndex.clamp(0, playableTracks.length - 1);

    // If the same playlist is already loaded, just switch track
    if (_isSamePlaylist(playableTracks) && !_switchingPlaylist) {
      var resolvedIndex = safeStartIndex;

      // Avoid restarting the same track when it is already selected.
      if (resolvedIndex == _audioService.currentIndex) {
        if (!_audioService.isPlaying) {
          await _audioService.play();
        }
      } else {
        await _audioService.playTrackAt(resolvedIndex);
      }
      notifyListeners();
      return;
    }

    if (_switchingPlaylist) return;
    _switchingPlaylist = true;
    try {
      await _audioService.setPlaylist(
        playableTracks,
        startIndex: safeStartIndex,
      );
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
    final trackKey = _trackKey(track);
    if (!isPlaying) return;
    if (!_vkProvider.isTrackSaved(track.id, ownerId: track.ownerId)) return;
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

  bool _isSamePlaylist(List<Track> tracks) {
    final current = _audioService.tracks;
    if (current.isEmpty) return false;
    if (current.any((t) => _isLocalPath(t.url))) return false;
    final filtered = tracks.where((t) => t.url.isNotEmpty).toList();
    if (current.length != filtered.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id != filtered[i].id ||
          current[i].ownerId != filtered[i].ownerId ||
          current[i].url != filtered[i].url) {
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  MusicAudioHandler? _handler;

  MusicAudioHandler get _safeHandler {
    final handler = _handler;
    if (handler == null) {
      throw StateError('AudioPlayerService is not initialized');
    }
    return handler;
  }

  Future<void> init() async {
    _handler = await AudioService.init(
      builder: () => MusicAudioHandler(_player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.musicbay.musicbay.audio',
        androidNotificationChannelName: 'MusicBay Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  AudioPlayer get player => _player;
  List<Track> get tracks => _safeHandler.tracks;
  int get currentIndex => _safeHandler.currentIndex;
  Track? get currentTrack => _safeHandler.currentTrack;

  RepeatMode get repeatMode => _safeHandler.repeatMode;
  bool get shuffle => _safeHandler.shuffle;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  AudioPlayerService();

  Future<void> setPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    await _safeHandler.setPlaylist(tracks, startIndex: startIndex);
  }

  Future<void> play() async => _safeHandler.play();
  Future<void> pause() async => _safeHandler.pause();

  Future<void> playPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async => _safeHandler.skipToNext();

  Future<void> previous() async => _safeHandler.skipToPrevious();

  Future<void> seekTo(Duration position) async => _safeHandler.seek(position);

  Future<void> playTrackAt(int index) async {
    await _safeHandler.playTrackAt(index);
  }

  Future<void> toggleRepeat() async => _safeHandler.toggleRepeat();

  Future<void> toggleShuffle() async => _safeHandler.toggleShuffle();

  Future<void> recoverDecoderGlitch() async =>
      _safeHandler.recoverDecoderGlitch();

  Future<void> dispose() async {
    await _safeHandler.stop();
    await _player.dispose();
  }
}

enum RepeatMode { off, all, one }

class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player;
  List<AudioSource> _playlistSources = [];

  List<Track> _tracks = [];
  int _currentIndex = -1;
  RepeatMode _repeatMode = RepeatMode.off;
  bool _shuffle = false;

  MusicAudioHandler(this._player) {
    unawaited(_player.setSpeed(1.0));

    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _tracks.length) {
        _currentIndex = index;
        mediaItem.add(_trackToMediaItem(_tracks[index]));
      }
      _broadcastState();
    });

    _player.processingStateStream.listen((_) => _broadcastState());

    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) {
        debugPrint('Playback error: $e');
      },
    );
  }

  List<Track> get tracks => _tracks;
  int get currentIndex => _currentIndex;
  Track? get currentTrack =>
      _currentIndex >= 0 && _currentIndex < _tracks.length
      ? _tracks[_currentIndex]
      : null;

  RepeatMode get repeatMode => _repeatMode;
  bool get shuffle => _shuffle;

  Future<void> setPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final safeOriginalIndex = startIndex.clamp(0, tracks.length - 1);
    _tracks = tracks.where((t) => t.url.isNotEmpty).toList(growable: false);
    if (_tracks.isEmpty) return;

    var targetIndex = _mapOriginalIndexToPlayableIndex(
      tracks,
      safeOriginalIndex,
    );
    if (targetIndex < 0 || targetIndex >= _tracks.length) {
      targetIndex = 0;
    }
    _currentIndex = targetIndex;

    final mediaItems = _tracks.map(_trackToMediaItem).toList();
    queue.add(mediaItems);

    _playlistSources = _tracks.asMap().entries.map((entry) {
      final index = entry.key;
      final track = entry.value;
      return AudioSource.uri(
        _isLocalPath(track.url) ? Uri.file(track.url) : Uri.parse(track.url),
        tag: mediaItems[index],
      );
    }).toList();

    if (_player.playing) {
      await _player.pause();
    }
    if (_player.speed != 1.0) {
      await _player.setSpeed(1.0);
    }
    // Use targetIndex (local variable) instead of _currentIndex here,
    // because _player.pause() above can trigger currentIndexStream listener
    // which overwrites _currentIndex with the OLD playlist's index.
    _currentIndex = targetIndex;
    await _player.setAudioSources(
      _playlistSources,
      initialIndex: targetIndex,
    );
    await _player.setLoopMode(_mapLoopMode(_repeatMode));
    await _player.setShuffleModeEnabled(_shuffle);
    if (_shuffle) {
      await _player.shuffle();
    }
    _currentIndex = targetIndex;
    mediaItem.add(mediaItems[targetIndex]);
    _broadcastState();
  }

  int _mapOriginalIndexToPlayableIndex(List<Track> tracks, int originalIndex) {
    if (tracks.isEmpty) return -1;
    final safeOriginalIndex = originalIndex.clamp(0, tracks.length - 1);
    if (tracks[safeOriginalIndex].url.isEmpty) return -1;

    var playableIndex = 0;
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i].url.isEmpty) continue;
      if (i == safeOriginalIndex) return playableIndex;
      playableIndex++;
    }
    return -1;
  }

  Future<void> playTrackAt(int index) async {
    if (index >= 0 && index < _tracks.length) {
      _currentIndex = index;
      if (_player.playing) {
        await _player.pause();
      }
      try {
        await _player.seek(Duration.zero, index: index);
      } catch (_) {
        await _player.setAudioSources(_playlistSources, initialIndex: index);
      }
      await _player.play();
      mediaItem.add(_trackToMediaItem(_tracks[index]));
      _broadcastState();
    }
  }

  Future<void> toggleRepeat() async {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        await _player.setLoopMode(_mapLoopMode(_repeatMode));
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        await _player.setLoopMode(_mapLoopMode(_repeatMode));
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        await _player.setLoopMode(_mapLoopMode(_repeatMode));
        break;
    }
    _broadcastState();
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await _player.setShuffleModeEnabled(_shuffle);
    if (_shuffle) {
      await _player.shuffle();
    }
    _broadcastState();
  }

  Future<void> recoverDecoderGlitch() async {
    if (_tracks.isEmpty) return;
    final idx = _player.currentIndex ?? _currentIndex;
    if (idx < 0 || idx >= _tracks.length) return;

    final wasPlaying = _player.playing;
    final pos = _player.position;

    try {
      await _player.stop();
      await _player.setAudioSources(
        _playlistSources,
        initialIndex: idx,
        initialPosition: pos,
      );
      await _player.setLoopMode(_mapLoopMode(_repeatMode));
      await _player.setShuffleModeEnabled(_shuffle);
      if (_shuffle) {
        await _player.shuffle();
      }
      if (wasPlaying) {
        await _player.play();
      }
    } catch (e) {
      debugPrint('Decoder recovery failed: $e');
    }
    _broadcastState();
  }

  @override
  Future<void> play() async {
    if (_player.speed != 1.0) {
      await _player.setSpeed(1.0);
    }
    await _player.play();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) async {
    // Force normal playback speed to avoid accidental external speed changes.
    await _player.setSpeed(1.0);
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (_currentIndex < _tracks.length - 1) {
      await _player.seekToNext();
      _broadcastState();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastState();
    return super.stop();
  }

  void _broadcastState() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekBackward,
          MediaAction.seekForward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapProcessingState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        speed: _player.speed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
        repeatMode: _mapRepeatMode(_repeatMode),
        shuffleMode: _shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _mapRepeatMode(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return AudioServiceRepeatMode.none;
      case RepeatMode.all:
        return AudioServiceRepeatMode.all;
      case RepeatMode.one:
        return AudioServiceRepeatMode.one;
    }
  }

  LoopMode _mapLoopMode(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return LoopMode.off;
      case RepeatMode.all:
        return LoopMode.all;
      case RepeatMode.one:
        return LoopMode.one;
    }
  }

  MediaItem _trackToMediaItem(Track track) {
    return MediaItem(
      id: track.accessKey,
      title: track.title,
      artist: track.artist,
      duration: Duration(seconds: track.duration),
      artUri: track.albumThumb != null ? Uri.tryParse(track.albumThumb!) : null,
      extras: {'url': track.url},
    );
  }

  bool _isLocalPath(String path) {
    if (path.startsWith('/')) return true;
    if (path.length >= 2 && path[1] == ':') {
      final drive = path[0].toUpperCase().codeUnitAt(0);
      return drive >= 65 && drive <= 90; // A-Z
    }
    return false;
  }
}

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist =
      ConcatenatingAudioSource(children: []);

  List<Track> _tracks = [];
  int _currentIndex = -1;
  RepeatMode _repeatMode = RepeatMode.off;
  bool _shuffle = false;

  AudioPlayer get player => _player;
  List<Track> get tracks => _tracks;
  int get currentIndex => _currentIndex;
  Track? get currentTrack =>
      _currentIndex >= 0 && _currentIndex < _tracks.length
          ? _tracks[_currentIndex]
          : null;

  RepeatMode get repeatMode => _repeatMode;
  bool get shuffle => _shuffle;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  AudioPlayerService() {
    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _tracks.length) {
        _currentIndex = index;
      }
    });

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        if (_repeatMode == RepeatMode.one) {
          _player.seek(Duration.zero);
          _player.play();
        }
      }
    });

    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('Playback error: $e');
      },
    );
  }

  Future<void> setPlaylist(List<Track> tracks, {int startIndex = 0}) async {
    final selectedTrack = (startIndex >= 0 && startIndex < tracks.length)
        ? tracks[startIndex]
        : null;

    _tracks = tracks.where((t) => t.url.isNotEmpty).toList();

    _currentIndex = 0;
    if (selectedTrack != null && selectedTrack.url.isNotEmpty) {
      final idx = _tracks.indexWhere((t) => t.id == selectedTrack.id);
      if (idx >= 0) _currentIndex = idx;
    }

    await _playlist.clear();
    final sources = _tracks
        .map((t) => AudioSource.uri(
              _isLocalPath(t.url) ? Uri.file(t.url) : Uri.parse(t.url),
            ))
        .toList();

    await _playlist.addAll(sources);
    await _player.setAudioSource(_playlist, initialIndex: _currentIndex);
  }

  Future<void> play() async => _player.play();
  Future<void> pause() async => _player.pause();

  Future<void> playPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_currentIndex < _tracks.length - 1) {
      await _player.seekToNext();
    }
  }

  Future<void> previous() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seekTo(Duration position) async => _player.seek(position);

  Future<void> playTrackAt(int index) async {
    if (index >= 0 && index < _tracks.length) {
      _currentIndex = index;
      await _player.seek(Duration.zero, index: index);
      await _player.play();
    }
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        _player.setLoopMode(LoopMode.all);
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        _player.setLoopMode(LoopMode.one);
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        _player.setLoopMode(LoopMode.off);
        break;
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _player.setShuffleModeEnabled(_shuffle);
  }

  bool _isLocalPath(String path) {
    return path.startsWith('/') || path.startsWith('C:') || path.startsWith('D:');
  }

  Future<void> dispose() async => _player.dispose();
}

enum RepeatMode { off, all, one }

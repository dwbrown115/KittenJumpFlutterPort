import 'dart:async';
import 'dart:math';

import 'package:flame_audio/flame_audio.dart';

import '../game/game_model.dart';

class GameAudio {
  final _random = Random();
  final Map<String, Future<AudioPool>> _pools = {};
  Future<void> _pending = Future<void>.value();
  StreamSubscription<void>? _completion;
  bool enabled = false;
  bool musicEnabled = false;
  bool _initialized = false;
  Future<void>? _initialization;
  bool _inGame = false;
  bool _paused = false;
  bool _introPlayed = false;
  bool _disposed = false;
  String? _musicTrack;
  int levelNumber = 7;

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> _initialize() {
    if (_initialized || _disposed) return Future<void>.value();
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    await FlameAudio.bgm.initialize();
    _completion = FlameAudio.bgm.audioPlayer.onPlayerComplete.listen((_) {
      if (!_inGame && musicEnabled && !_disposed) {
        unawaited(_enqueue(() => _playTrack('MenuLoop.wav')));
      }
    });
    _initialized = true;
  }

  Future<void> setEnabled(bool value) {
    enabled = value;
    return _enqueue(() async {
      if (value) await _initialize();
    });
  }

  Future<void> setMusicEnabled(bool value) {
    musicEnabled = value;
    return _enqueue(() async {
      if (_disposed) return;
      if (!value) {
        if (_initialized) await FlameAudio.bgm.stop();
        _musicTrack = null;
      } else {
        await _initialize();
        await _updateMusic();
      }
    });
  }

  Future<void> setPlayingGame(bool value) {
    _inGame = value;
    _paused = false;
    return _enqueue(_updateMusic);
  }

  Future<void> _updateMusic() async {
    if (!musicEnabled || _disposed) return;
    await _initialize();
    final track = _inGame
        ? 'GameLoop.wav'
        : _introPlayed
        ? 'MenuLoop.wav'
        : 'MenuIntro.wav';
    if (_musicTrack != track) await _playTrack(track);
  }

  Future<void> _playTrack(String track) async {
    if (!musicEnabled || _disposed) return;
    _musicTrack = track;
    await FlameAudio.bgm.play(track, volume: 0.55);
    if (track == 'MenuIntro.wav') {
      _introPlayed = true;
      await FlameAudio.bgm.audioPlayer.setReleaseMode(ReleaseMode.stop);
    }
    if (_paused) await FlameAudio.bgm.pause();
  }

  Future<void> _effect(String file) async {
    if (!enabled || _disposed) return;
    await _initialize();
    final pool = await _pools.putIfAbsent(
      file,
      () => FlameAudio.createPool(file, maxPlayers: 4),
    );
    if (enabled && !_disposed) await pool.start(volume: 0.8);
  }

  Future<void> play(GameSound sound) => _effect(
    sound == GameSound.cloud
        ? 'jump$levelNumber${_random.nextInt(3)}.wav'
        : levelNumber >= 6
        ? 'butterfly0${_random.nextInt(3)}.wav'
        : 'butterfly${1 + _random.nextInt(2)}.wav',
  );

  Future<void> menu({bool back = false}) =>
      _effect(back ? 'menu01.wav' : 'menu00.wav');

  Future<void> pause(bool paused) {
    _paused = paused;
    return _enqueue(() async {
      if (!_initialized || !musicEnabled || _disposed) return;
      if (paused) {
        await FlameAudio.bgm.pause();
      } else {
        await FlameAudio.bgm.resume();
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _pending;
    await _completion?.cancel();
    for (final future in _pools.values) {
      await (await future).dispose();
    }
    if (_initialized) await FlameAudio.bgm.dispose();
  }
}

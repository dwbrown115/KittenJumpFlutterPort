import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../game/game_model.dart';
import '../game/kitten_jump_game.dart';
import '../services/game_audio.dart';
import '../services/game_store.dart';

enum _MenuPage { main, levels, settings, help }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.store});
  final GameStore store;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final model = GameModel(
    seed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
  );
  final _audio = GameAudio();
  final _focus = FocusNode(debugLabel: 'Game controls');
  final _nameFocus = FocusNode();
  final _name = TextEditingController();
  late KittenJumpGame game;
  StreamSubscription<AccelerometerEvent>? _sensor;
  bool _paused = false;
  bool _saving = false;
  bool _audioReady = false;
  int _session = 0;
  String? _notice;
  _MenuPage _page = _MenuPage.main;
  int _scoresLevel = 7;

  bool get _canTilt =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name.text = widget.store.playerName;
    model.skin = widget.store.kittenSkin;
    game = KittenJumpGame(
      model: model,
      onStateChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
      onSound: (sound) => _handleAudio(_audio.play(sound)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _configureTilt();
    });
  }

  void _handleAudio(Future<void> action) {
    unawaited(
      action.catchError((Object error) {
        debugPrint('Kitten Jump audio error: $error');
        if (mounted) {
          setState(
            () => _notice = 'Sound is unavailable. You can keep playing.',
          );
        }
      }),
    );
  }

  void _beginAudio() {
    if (_audioReady) return;
    _audioReady = true;
    _handleAudio(_audio.setEnabled(widget.store.soundOn));
    _handleAudio(_audio.setMusicEnabled(widget.store.musicOn));
  }

  Future<void> _configureTilt() async {
    await _sensor?.cancel();
    _sensor = null;
    game.useTiltInstructions = widget.store.tiltOn && _canTilt;
    if (!widget.store.tiltOn || !_canTilt) return;
    _sensor =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 10),
        ).listen(
          (event) {
            if (model.phase == GamePhase.playing && !_paused) {
              // Android's positive X points left; the original iPhone input points right.
              model.applyTilt(-event.x / 9.80665);
            }
          },
          onError: (Object error) {
            unawaited(widget.store.setTilt(false));
            if (mounted) {
              setState(
                () => _notice = 'Tilt is unavailable. Use finger control.',
              );
            }
            unawaited(_sensor?.cancel());
            _sensor = null;
          },
        );
  }

  void _start([int? levelNumber]) {
    if (!game.assetsReady) return;
    _session++;
    _beginAudio();
    _audio.levelNumber = levelNumber ?? model.selectedLevel;
    _handleAudio(_audio.setPlayingGame(true));
    _handleAudio(_audio.pause(false));
    model.selectLevel(_audio.levelNumber);
    model.skin = widget.store.kittenSkin;
    game.kittenSkin = widget.store.kittenSkin;
    _nameFocus.unfocus();
    _paused = false;
    game.pauseGame(false);
    game.startGame();
    _focus.requestFocus();
    setState(() => _notice = null);
  }

  void _pause([bool? value]) {
    if (model.phase != GamePhase.playing) return;
    setState(() => _paused = value ?? !_paused);
    game.pauseGame(_paused);
    _handleAudio(_audio.pause(_paused));
  }

  void _menu() {
    _session++;
    _nameFocus.unfocus();
    _paused = false;
    game.pauseGame(false);
    model.showMenu();
    _page = _MenuPage.main;
    _handleAudio(_audio.setPlayingGame(false));
    _handleAudio(_audio.pause(false));
    _focus.requestFocus();
    setState(() => _notice = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = _session;
    setState(() => _saving = true);
    try {
      await widget.store.saveScore(
        _name.text,
        model.score,
        levelNumber: model.selectedLevel,
        butterflies: model.butterflyCount,
        percentage: model.progress,
        won: model.won,
        stars: model.earnedStars,
      );
      if (!mounted ||
          session != _session ||
          model.phase != GamePhase.gameOver) {
        return;
      }
      _nameFocus.unfocus();
      _scoresLevel = model.selectedLevel;
      model.showScores();
      _focus.requestFocus();
      setState(() => _notice = null);
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Could not save your score. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_nameFocus.hasFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (event is KeyUpEvent &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.keyA ||
            key == LogicalKeyboardKey.keyD)) {
      model.setTarget(model.playerX);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent &&
        (key == LogicalKeyboardKey.escape ||
            key == LogicalKeyboardKey.keyP ||
            key == LogicalKeyboardKey.space)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      if (model.phase == GamePhase.playing) {
        _pause();
      } else {
        _menu();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (model.phase == GamePhase.menu ||
          model.phase == GamePhase.scores ||
          model.phase == GamePhase.gameOver) {
        _start();
      } else if (_paused) {
        _pause(false);
      } else {
        game.jump();
      }
      return KeyEventResult.handled;
    }
    if (model.phase == GamePhase.playing && !_paused) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.keyA) {
        model.setTarget(0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.keyD) {
        model.setTarget(320);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _pointer(Offset position, {bool start = false}) {
    if (model.phase != GamePhase.playing || _paused) return;
    _focus.requestFocus();
    if (!widget.store.tiltOn || !_canTilt) game.setPointer(position.dx);
    if (start) game.jump();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        model.phase == GamePhase.playing) {
      _pause(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sensor?.cancel());
    unawaited(_audio.dispose());
    _focus.dispose();
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _open(_MenuPage page) {
    _beginAudio();
    _handleAudio(_audio.menu());
    _nameFocus.unfocus();
    setState(() {
      _page = page;
      _notice = null;
    });
  }

  void _showScores() {
    _beginAudio();
    _handleAudio(_audio.menu());
    _scoresLevel = model.selectedLevel;
    model.showScores();
    setState(() => _notice = null);
  }

  void _setTilt(bool value) {
    if (value && !_canTilt) {
      setState(
        () =>
            _notice = 'Tilt is available on Android. Use finger control here.',
      );
      return;
    }
    unawaited(widget.store.setTilt(value));
    unawaited(_configureTilt());
    setState(() => _notice = null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / 320,
              constraints.maxHeight / 480,
            );
            return Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: 320 * scale,
                    height: 480 * scale,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 320,
                        height: 480,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned.fill(
                              child: Listener(
                                key: const Key('playfield'),
                                onPointerDown: (event) =>
                                    _pointer(event.localPosition, start: true),
                                onPointerMove: (event) =>
                                    _pointer(event.localPosition),
                                child: GameWidget<KittenJumpGame>(
                                  game: game,
                                  loadingBuilder: (_) => const ColoredBox(
                                    color: Color(0xfff8fbff),
                                    child: Center(
                                      child: Text('Loading original artwork…'),
                                    ),
                                  ),
                                  errorBuilder: (_, error) => ColoredBox(
                                    color: const Color(0xfff8fbff),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Could not load the game artwork.',
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton(
                                            onPressed: () => setState(() {
                                              game =
                                                  KittenJumpGame(
                                                      model: model,
                                                      onStateChanged: () {
                                                        if (mounted) {
                                                          setState(() {});
                                                        }
                                                      },
                                                      onSound: (sound) =>
                                                          _handleAudio(
                                                            _audio.play(sound),
                                                          ),
                                                    )
                                                    ..kittenSkin =
                                                        widget.store.kittenSkin;
                                            }),
                                            child: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (model.phase == GamePhase.menu &&
                                game.assetsReady &&
                                _page == _MenuPage.main)
                              _mainMenu(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (model.phase == GamePhase.playing &&
                    !_paused &&
                    game.assetsReady)
                  Positioned(
                    left: (constraints.maxWidth - 320 * scale) / 2,
                    top: (constraints.maxHeight - 480 * scale) / 2,
                    width: 320 * scale,
                    height: math.max(44, 80 * scale),
                    child: _MenuHitTarget(
                      key: const Key('pause'),
                      label: 'Pause',
                      onPressed: _pause,
                    ),
                  ),
                if (model.phase == GamePhase.menu && game.assetsReady)
                  switch (_page) {
                    _MenuPage.main => const SizedBox(),
                    _MenuPage.levels => _levelsView(),
                    _MenuPage.settings => _settingsView(),
                    _MenuPage.help => _helpView(),
                  },
                if (_paused) _pauseView(),
                if (model.phase == GamePhase.gameOver) _scoreEntry(),
                if (model.phase == GamePhase.scores) _scoresView(),
                if (_notice != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: const Color(0xfff8fbff),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _notice!,
                          style: const TextStyle(color: Color(0xff202c47)),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _mainMenu() => Stack(
    children: [
      Positioned(
        left: 8,
        top: 8,
        child: Semantics(
          label: 'Kitten Jump Christmas',
          child: const SizedBox(width: 1, height: 1),
        ),
      ),
      _menuZone(
        'start',
        'Play: choose a level',
        const Rect.fromLTWH(0, 256, 105, 75),
        () => _open(_MenuPage.levels),
      ),
      _menuZone(
        'classic',
        'Play Classic mode',
        const Rect.fromLTWH(180, 270, 90, 55),
        () => _start(6),
      ),
      _menuZone(
        'help',
        'How to play',
        const Rect.fromLTWH(196, 328, 122, 77),
        () => _open(_MenuPage.help),
      ),
      _menuZone(
        'scores',
        'Stats and local scores',
        const Rect.fromLTWH(88, 398, 123, 82),
        _showScores,
      ),
      _menuZone(
        'settings',
        'Settings',
        const Rect.fromLTWH(212, 404, 106, 76),
        () => _open(_MenuPage.settings),
      ),
      _menuZone(
        'christmas',
        'Play Christmas Surprise',
        const Rect.fromLTWH(0, 369, 61, 111),
        () => _start(7),
      ),
    ],
  );

  Widget _menuZone(String key, String label, Rect rect, VoidCallback action) =>
      Positioned.fromRect(
        rect: rect,
        child: _MenuHitTarget(key: Key(key), label: label, onPressed: action),
      );

  Widget _panel(Widget child) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0x990f1b30),
      child: Center(
        child: Container(
          width: 380,
          constraints: const BoxConstraints(maxHeight: 610),
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          child: Material(
            color: const Color(0xfff8fbff),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );

  Widget _levelsView() => _panel(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.asset(
          'assets/images/pick_a_level_title.png',
          height: 70,
          fit: BoxFit.contain,
          semanticLabel: 'Pick a level',
        ),
        for (final level in GameModel.levels.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OutlinedButton(
              key: Key('level_${level.id}'),
              onPressed: widget.store.isLevelUnlocked(level.id)
                  ? () => _start(level.id)
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(level.name)),
                  const SizedBox(width: 8),
                  if (!widget.store.isLevelUnlocked(level.id))
                    Text(
                      '${level.id * 2} stars',
                      style: const TextStyle(fontSize: 12),
                    )
                  else if (level.id < 5)
                    Text('${widget.store.starsForLevel(level.id)} / 3 ★'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          'Collect butterflies and finish a level to earn stars. Save your result to unlock more levels.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('levels_menu'),
          onPressed: _menu,
          child: const Text('Main menu'),
        ),
      ],
    ),
  );

  Widget _settingsView() => _panel(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Settings',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('settings_name'),
          controller: _name,
          focusNode: _nameFocus,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Player name',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => unawaited(widget.store.setPlayerName(value)),
        ),
        SwitchListTile(
          key: const Key('sound'),
          title: const Text('Sound effects'),
          value: widget.store.soundOn,
          onChanged: (value) {
            _beginAudio();
            unawaited(widget.store.setSound(value));
            _handleAudio(_audio.setEnabled(value));
            setState(() {});
          },
        ),
        SwitchListTile(
          key: const Key('music'),
          title: const Text('Music'),
          value: widget.store.musicOn,
          onChanged: (value) {
            _beginAudio();
            unawaited(widget.store.setMusic(value));
            _handleAudio(_audio.setMusicEnabled(value));
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        const Text('Choose your kitten', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (index, skin) in GameStore.kittenSkins.indexed)
              _Choice(
                key: Key('skin_$index'),
                label: const [
                  'Grey kitten',
                  'Orange kitten',
                  'Siamese kitten',
                ][index],
                selected: widget.store.kittenSkin == skin,
                onPressed: () {
                  unawaited(widget.store.setSkin(skin));
                  model.skin = skin;
                  game.kittenSkin = skin;
                  setState(() {});
                },
                child: _KittenPreview(asset: skin),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Christmas and Classic modes use their own original kitten artwork.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _Choice(
                key: const Key('finger'),
                label: 'Finger or mouse control',
                selected: !widget.store.tiltOn || !_canTilt,
                onPressed: () => _setTilt(false),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Finger / mouse'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Choice(
                key: const Key('tilt'),
                label: _canTilt
                    ? 'Tilt control'
                    : 'Tilt control requires an Android phone',
                selected: widget.store.tiltOn && _canTilt,
                onPressed: () => _setTilt(true),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Tilt'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextButton(
          key: const Key('settings_menu'),
          onPressed: _menu,
          child: const Text('Main menu'),
        ),
      ],
    ),
  );

  Widget _helpView() => _panel(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: const Key('help_back'),
          onPressed: _menu,
          child: const Text('Main menu'),
        ),
        const SizedBox(height: 8),
        Image.asset(
          'assets/images/${widget.store.tiltOn && _canTilt ? 'how_to_play_tilt.png' : 'how_to_play_finger.png'}',
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 12),
        const Text(
          'Tap or press Space for the first jump. Drag, tilt on Android, or use Left/Right and A/D to steer. Bounce on platforms and collect butterflies; avoid falling after your first platform. Esc or P pauses.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
      ],
    ),
  );

  Widget _pauseView() => _panel(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Paused',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(model.currentLevel.name),
        const SizedBox(height: 12),
        const Text(
          'Drag to steer. Tap or press Space to jump.\nArrow keys steer; Esc or P pauses.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('resume'),
          onPressed: () => _pause(false),
          child: const Text('Resume'),
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('pause_menu'),
          onPressed: _menu,
          child: const Text('Main menu'),
        ),
      ],
    ),
  );

  Widget _scoreEntry() => _panel(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          model.won ? 'Level complete!' : 'Game over',
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(model.currentLevel.name),
        const SizedBox(height: 8),
        Text('Score: ${model.score}', style: const TextStyle(fontSize: 20)),
        Text(
          '${model.butterflyCount} ${model.selectedLevel == 7 ? 'gifts' : 'butterflies'}',
        ),
        if (model.selectedLevel < 5)
          Text('${(model.progress * 100).floor()}% climbed'),
        if (model.won) Text('${model.earnedStars} / 3 ★'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('player_name'),
          controller: _name,
          focusNode: _nameFocus,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Player name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => unawaited(_save()),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('save'),
          onPressed: _saving ? null : () => unawaited(_save()),
          child: Text(_saving ? 'Saving…' : 'Save result'),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('replay'),
              onPressed: () => _start(),
              child: const Text('Replay'),
            ),
            TextButton(
              key: const Key('gameover_menu'),
              onPressed: _menu,
              child: const Text('Main menu'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _scoresView() {
    final scores = widget.store.topTenForLevel(_scoresLevel);
    return _panel(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Local scores',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          DropdownButton<int>(
            key: const Key('scores_level'),
            value: _scoresLevel,
            isExpanded: true,
            items: [
              for (final level in GameModel.levels)
                DropdownMenuItem(
                  value: level.id,
                  child: Text(level.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _scoresLevel = value);
            },
          ),
          if (_scoresLevel < 5)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Best result: ${widget.store.starsForLevel(_scoresLevel)} / 3 ★',
                textAlign: TextAlign.center,
              ),
            ),
          if (scores.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No scores yet. Finish a run and save your result.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final (index, score) in scores.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 30, child: Text('${index + 1}.')),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(score.name, overflow: TextOverflow.ellipsis),
                        Text(
                          '${score.butterflies} ${_scoresLevel == 7 ? 'gifts' : 'butterflies'}${_scoresLevel < 5 ? ' · ${(score.percentage * 100).floor()}%' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${score.score}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('scores_replay'),
                onPressed: widget.store.isLevelUnlocked(_scoresLevel)
                    ? () => _start(_scoresLevel)
                    : null,
                child: const Text('Play again'),
              ),
              TextButton(
                key: const Key('scores_menu'),
                onPressed: _menu,
                child: const Text('Main menu'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuHitTarget extends StatelessWidget {
  const _MenuHitTarget({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    onTap: onPressed,
    excludeSemantics: true,
    child: TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? const BorderSide(color: Color(0xffffdf85), width: 3)
              : BorderSide.none,
        ),
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.child,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    selected: selected,
    onTap: onPressed,
    excludeSemantics: true,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        foregroundColor: const Color(0xff202c47),
        side: BorderSide(
          color: const Color(0xff283b62),
          width: selected ? 3 : 1,
        ),
        backgroundColor: selected ? const Color(0xffdee8f8) : null,
      ),
      child: child,
    ),
  );
}

class _KittenPreview extends StatelessWidget {
  const _KittenPreview({required this.asset});
  final String asset;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 74,
    height: 70,
    child: FittedBox(
      child: SizedBox(
        width: 85,
        height: 80,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: 1024,
            maxHeight: 1024,
            child: Image.asset(
              'assets/images/$asset',
              width: 1024,
              height: 1024,
              excludeFromSemantics: true,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import 'game_model.dart';

ui.Rect atlasCellRect(
  int frame, {
  required double width,
  required double height,
  required int columns,
  double offsetX = 0,
  double offsetY = 0,
}) => ui.Rect.fromLTWH(
  offsetX + frame % columns * width,
  offsetY + frame ~/ columns * height,
  width,
  height,
);

class KittenJumpGame extends FlameGame {
  KittenJumpGame({
    required this.model,
    required this.onStateChanged,
    this.onSound,
  }) {
    // GameScreen owns lifecycle pause and leaves Resume under the player's control.
    pauseWhenBackgrounded = false;
  }

  final GameModel model;
  final void Function() onStateChanged;
  final void Function(GameSound)? onSound;
  final Map<String, ui.Image> _sprites = {};
  final ui.Paint _spritePaint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low;
  final Map<String, _BitmapFont> _fonts = {};
  final List<_Decoration> _decorations = [];
  final List<int> _wallFrames = [];
  math.Random _visualRandom = math.Random(211);
  bool _ready = false;
  Object? _loadError;
  double _accumulator = 0;
  double _lastKittenY = 0;
  double _sunPulse = 0;
  double _sunRotation = 0;
  double _planeX = 481;
  double _planeY = 481;
  int _planeDirection = 1;
  double _cometTarget = 33000;
  double _cometCenterY = 0;
  double _cometOffsetY = -500;
  double _cometRotation = 0;
  bool _cometActive = false;
  int _lastJump = -1;
  int _animationStart = 0;
  String _lastAnimation = '';
  String kittenSkin = 'red_kitten.png';
  bool useTiltInstructions = false;

  bool get assetsReady => _ready;
  Object? get loadError => _loadError;
  Map<String, dynamic> get _config => model.currentLevel.data;
  int get _level => (_config['LevelNumber'] as num).toInt();
  double _number(String key, [double fallback = 0]) =>
      (_config[key] as num?)?.toDouble() ?? fallback;
  List<double> _point(String key) =>
      (_config[key] as List).map((v) => (v as num).toDouble()).toList();

  @override
  ui.Color backgroundColor() => const ui.Color(0xff222a50);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final names = manifest
          .listAssets()
          .where(
            (name) =>
                name.startsWith('assets/images/') && name.endsWith('.png'),
          )
          .map((name) => name.substring('assets/images/'.length))
          .toList();
      await images.loadAll(names);
      for (final name in names) {
        _sprites[name] = images.fromCache(name);
      }
      for (final font in ['small_font', 'white_font', 'giant_scores']) {
        _fonts[font] = _BitmapFont.parse(
          await rootBundle.loadString('assets/fonts/$font.fnt'),
        );
      }
      _resetDecorations();
      _syncAnimation();
      _ready = true;
      onStateChanged();
    } catch (error) {
      _loadError = error;
      onStateChanged();
      rethrow;
    }
  }

  void startGame() {
    _accumulator = 0;
    resumeEngine();
    model.start();
    _lastAnimation = '';
    _lastJump = -1;
    _resetDecorations();
    _syncAnimation();
    _dispatchSounds();
    onStateChanged();
  }

  void pauseGame(bool value) {
    if (paused == value) return;
    _accumulator = 0;
    if (value) {
      pauseEngine();
    } else {
      resumeEngine();
    }
    onStateChanged();
  }

  void jump() {
    if (!paused) {
      model.jump();
      _syncAnimation();
    }
  }

  void setPointer(double logicalX) {
    if (!paused) model.setTarget(logicalX);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_ready || paused || model.phase != GamePhase.playing) {
      _accumulator = 0;
      return;
    }
    if (!dt.isFinite || dt <= 0) return;
    final previousPhase = model.phase;
    final previousScore = model.score;
    _accumulator += math.min(dt, 0.25);
    var steps = 0;
    while (_accumulator + 1e-12 >= GameModel.tickSeconds && steps < 8) {
      model.tick();
      _updateDecorations();
      _syncAnimation();
      _accumulator = math.max(0, _accumulator - GameModel.tickSeconds);
      steps++;
      _dispatchSounds();
      if (model.phase != GamePhase.playing) {
        _accumulator = 0;
        break;
      }
    }
    if (steps == 8 && _accumulator >= GameModel.tickSeconds) {
      _accumulator %= GameModel.tickSeconds;
    }
    if (model.phase != previousPhase || model.score != previousScore) {
      onStateChanged();
    }
  }

  void _dispatchSounds() {
    for (final sound in model.drainSounds()) {
      onSound?.call(sound);
    }
  }

  void _resetDecorations() {
    _visualRandom = math.Random(211 + _level);
    _lastKittenY = model.playerY;
    _sunPulse = 0;
    _sunRotation = 0;
    _planeX = 481;
    _planeY = 481;
    _planeDirection = 1;
    _cometTarget = 33000;
    _cometCenterY = 0;
    _cometOffsetY = -500;
    _cometRotation = 0;
    _cometActive = false;
    _decorations.clear();
    _wallFrames.clear();
    for (var i = 0; i < 3; i++) {
      _wallFrames.add(_visualRandom.nextInt(3));
    }
    if ([1, 2, 5].contains(_level)) {
      for (var i = 0; i < 4; i++) {
        _decorations.add(
          _Decoration(
            x: _visualRandom.nextDouble() * 320,
            y: i * 120,
            frame: _visualRandom.nextInt(4),
          ),
        );
      }
    } else if ([3, 4, 6, 7].contains(_level)) {
      for (var i = 0; i < 30; i++) {
        _decorations.add(
          _Decoration(
            x: _visualRandom.nextDouble() * 320,
            y: i * 16,
            frame: _visualRandom.nextInt(5),
            scale: 1 - _visualRandom.nextDouble() * 0.8,
          ),
        );
      }
    }
  }

  void _updateDecorations() {
    final displacement = model.playerY - _lastKittenY;
    _lastKittenY = model.playerY;
    for (final item in _decorations) {
      item.y -= displacement / 50;
      if ([1, 2, 5].contains(_level)) {
        item.x += _visualRandom.nextDouble() * 0.3;
        if (item.x > 495) {
          item.x = -175;
          item.frame = _visualRandom.nextInt(4);
        }
        if (item.y < -50) item.y += 580;
        if (item.y > 580) item.y = -50;
      } else {
        if (_visualRandom.nextDouble() < 0.2) {
          item.frame = _visualRandom.nextInt(5);
        }
        if (item.y < 0 || item.y > 480) {
          item.y = item.y < 0 ? item.y + 480 : 0;
          item.x = _visualRandom.nextDouble() * 320;
          item.scale = 1 - _visualRandom.nextDouble() * 0.8;
        }
      }
    }
    if (_level == 6) {
      _planeX -= _planeDirection * 0.2;
      _planeY -= displacement / 30;
      if (_planeY < -15 && model.playerY < 29000) {
        _planeY = 500;
        _planeDirection = -1;
      }
      if (_planeX < -161 && _planeDirection > 0) _planeX = 481;
      if (_planeY > 481 && _planeDirection < 0) _planeX = -161;
      if (!_cometActive &&
          model.playerY > _cometTarget &&
          model.playerY < _cometTarget + 25) {
        _cometActive = true;
        _cometRotation = _visualRandom.nextDouble() * 360;
        _cometCenterY = _visualRandom.nextDouble() * 460;
      }
      if (_cometActive) {
        _cometOffsetY += 8;
        if (_cometOffsetY >= 500) {
          _cometOffsetY = -500;
          _cometActive = false;
          _cometTarget += 2500;
        }
      }
    }
    _sunRotation += 0.2;
    _sunPulse += 0.002;
    if (_sunPulse > 0.1) _sunPulse = -0.1;
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    if (!_ready || !hasLayout) return;
    final scale = math.min(
      canvasSize.x / GameModel.width,
      canvasSize.y / GameModel.height,
    );
    if (scale <= 0) return;
    canvas.save();
    canvas.translate(
      (canvasSize.x - GameModel.width * scale) / 2,
      (canvasSize.y - GameModel.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 320, 480));
    if (model.phase == GamePhase.menu) {
      _drawRect(
        canvas,
        'menu_bg.png',
        const ui.Rect.fromLTWH(0, 0, 320, 480),
        source: const ui.Rect.fromLTWH(0, 480, 1, 480),
      );
      _drawRect(
        canvas,
        'main_menu.png',
        const ui.Rect.fromLTWH(0, 0, 320, 480),
      );
    } else {
      _renderScene(canvas);
    }
    canvas.restore();
  }

  void _renderScene(ui.Canvas canvas) {
    final start = _config['BackgroundColor'] as List;
    final end = _config['BackgroundEndColor'] as List;
    final fraction = (model.playerY / (_number('BackgroundChangeEnd', 1) + 480))
        .clamp(0.0, 1.0);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 320, 480),
      ui.Paint()
        ..color = ui.Color.fromARGB(
          255,
          _mix(start[0], end[0], fraction),
          _mix(start[1], end[1], fraction),
          _mix(start[2], end[2], fraction),
        ),
    );
    _renderFarBackground(canvas);
    if (_level == 0 || _level == 1) _renderWall(canvas);
    final back = _point('GroundBackPos');
    _drawCentered(
      canvas,
      _config['GroundBackImg'] as String,
      back[0],
      back[1] - model.cameraY,
    );
    final ending = _point('EndLayerImagePos');
    _drawCentered(
      canvas,
      _config['EndLayerImage'] as String,
      ending[0],
      ending[1] - model.cameraY,
    );
    for (final cloud in model.clouds) {
      if (!cloud.visible) continue;
      final width = _number('CloudWidth');
      final height = _number('CloudHeight');
      final offset = _point('CloudAtlasStartOffset');
      final columns = (_number('CloudsAtlasWidth') / width).floor();
      _drawCentered(
        canvas,
        _config['CloudsAtlas'] as String,
        cloud.x,
        cloud.y - model.cameraY,
        source: atlasCellRect(
          cloud.frame,
          width: width,
          height: height,
          columns: columns,
          offsetX: offset[0],
          offsetY: offset[1],
        ),
        scale: cloud.size,
        rotation: cloud.rotation,
      );
    }
    _renderKitten(canvas);
    if ([0, 5, 6, 7].contains(_level)) {
      final front = _point('GroundFrontPos');
      _drawCentered(
        canvas,
        _config['GroundFrontImg'] as String,
        front[0],
        front[1] - model.cameraY,
      );
    }
    _renderButterflies(canvas);
    _renderHud(canvas);
    if ((_level == 0 || _level == 5) && !model.jumping && model.score == 0) {
      _drawCentered(
        canvas,
        useTiltInstructions
            ? 'how_to_play_overlay_tilt.png'
            : 'how_to_play_overlay_finger.png',
        160,
        240,
      );
    }
  }

  int _mix(dynamic a, dynamic b, double fraction) =>
      ((a as num).toDouble() * (1 - fraction) +
              (b as num).toDouble() * fraction)
          .round()
          .clamp(0, 255);

  void _renderWall(ui.Canvas canvas) {
    final height = _number('BackgroundImgHeight', 480);
    final overlap = _number('BackgroundOverlap');
    final spacing = height - overlap;
    final origin = spacing - height / 2 - overlap;
    final first = ((model.cameraY - origin - height / 2) / spacing).floor();
    for (var i = first; i < first + 4; i++) {
      if (i < 0) continue;
      _drawCentered(
        canvas,
        _config['BackgroundLoopImg'] as String,
        160,
        origin + i * spacing - model.cameraY,
        source: atlasCellRect(
          _wallFrames[i % 3],
          width: 320,
          height: 480,
          columns: 3,
        ),
      );
    }
  }

  void _renderFarBackground(ui.Canvas canvas) {
    final altitude = model.playerY;
    if (_level == 6 && _cometActive) {
      final radians = _cometRotation * math.pi / 180;
      _drawCentered(
        canvas,
        'Comet.png',
        160 + 160 * math.cos(radians) + _cometOffsetY * math.sin(radians),
        _cometCenterY -
            160 * math.sin(radians) +
            _cometOffsetY * math.cos(radians),
        rotation: _cometRotation,
      );
    }
    final transition = _number('BackgroundChangeEnd', 1);
    if (_level == 3) {
      final progress = (altitude / transition).clamp(0.0, 1.0);
      _drawCentered(
        canvas,
        'earth.png',
        160,
        progress * 398 - 250,
        scale: 1.2 - progress,
        opacity: (255 - progress * 128) / 255,
      );
    } else if (_level == 4) {
      final progress = (altitude / transition).clamp(0.0, 1.0);
      _drawCentered(
        canvas,
        'galaxy.png',
        160,
        progress * 167 + 18,
        scale: progress * 0.9 + 0.1,
        opacity: progress,
      );
    }
    for (final item in _decorations) {
      if ([1, 2, 5].contains(_level)) {
        _drawCentered(
          canvas,
          'BackCloudsAtlas.png',
          item.x,
          item.y,
          source: ui.Rect.fromLTWH(0, item.frame * 100, 350, 100),
        );
      } else {
        final source = switch (_level) {
          6 => ui.Rect.fromLTWH(item.frame * 14, 628, 14, 14),
          7 => ui.Rect.fromLTWH(748 + item.frame * 14, 857, 14, 14),
          _ => ui.Rect.fromLTWH(item.frame * 14, 0, 14, 14),
        };
        final name = switch (_level) {
          6 => 'classic_atlas.png',
          7 => 'winter_level_atlas.png',
          _ => 'bgstars.png',
        };
        final opacity = _level == 6
            ? ((altitude - transition * 0.5) / transition).clamp(0.0, 1.0)
            : 1.0;
        _drawCentered(
          canvas,
          name,
          item.x,
          item.y,
          source: source,
          scale: item.scale,
          opacity: opacity,
        );
      }
    }
    if (_level == 6) {
      _drawCentered(
        canvas,
        'classic_atlas.png',
        80,
        altitude / 30000 * -470 + 400,
        source: const ui.Rect.fromLTWH(283, 633, 123, 119),
        scale: 0.7 + _sunPulse.abs(),
        rotation: _sunRotation,
      );
      _drawCentered(
        canvas,
        'classic_atlas.png',
        179,
        altitude / 15000 * -346 + 173,
        source: const ui.Rect.fromLTWH(0, 643, 282, 346),
      );
      _drawCentered(
        canvas,
        'classic_atlas.png',
        _planeX,
        _planeY,
        source: const ui.Rect.fromLTWH(321, 602, 323, 30),
        flipX: _planeDirection < 0,
      );
    } else if (_level == 7) {
      _drawCentered(
        canvas,
        'winter_level_atlas.png',
        80,
        altitude / 30000 * -470 + 400,
        source: const ui.Rect.fromLTWH(321, 881, 130, 130),
      );
    }
  }

  void _syncAnimation() {
    final animation = model.animation.name;
    if (_lastAnimation != animation || _lastJump != model.jumpGeneration) {
      _lastAnimation = animation;
      _lastJump = model.jumpGeneration;
      _animationStart = model.ticks;
    }
  }

  void _renderKitten(ui.Canvas canvas) {
    final animation = model.animation.name;
    final seconds = (model.ticks - _animationStart) * GameModel.tickSeconds;
    final classic = _level == 6;
    final name = classic
        ? 'classic_atlas.png'
        : _level == 7
        ? 'winter_level_atlas.png'
        : kittenSkin;
    int frame;
    if (animation == 'jump') {
      final jumpFrames = classic ? 35 : 45;
      final jumpIndex = (seconds / 0.03).floor();
      frame = jumpIndex < jumpFrames
          ? jumpIndex
          : classic
          ? 35
          : 39 + ((seconds - jumpFrames * 0.03) / 0.04).floor() % 6;
    } else if (animation == 'run') {
      frame = classic
          ? 36 + (seconds / 0.03).floor() % 19
          : 45 + (seconds / 0.03).floor() % 22;
    } else {
      final sitSeconds = classic ? 0.04 : 0.08;
      final sitIndex = (seconds / sitSeconds).floor();
      frame = sitIndex < 6
          ? (classic ? 55 : 67) + sitIndex
          : classic
          ? 61
          : 72;
      final lickStart = 6 * sitSeconds + 1;
      if (!classic && seconds >= lickStart) {
        final lickIndex = ((seconds - lickStart) / 0.05).floor();
        final sequence = [
          for (var i = 72; i < 97; i++) i,
          for (var i = 77; i < 97; i++) i,
          for (var i = 77; i < 119; i++) i,
          for (var i = 101; i < 125; i++) i,
          for (var i = 77; i < 97; i++) i,
          77,
        ];
        frame = sequence[math.min(lickIndex, sequence.length - 1)];
      }
    }
    _drawCentered(
      canvas,
      name,
      model.playerX,
      model.playerY + 20 - model.cameraY,
      source: atlasCellRect(frame, width: 85, height: 80, columns: 12),
      flipX: model.facingLeft,
    );
  }

  void _renderButterflies(ui.Canvas canvas) {
    for (final butterfly in model.butterflies) {
      if (!butterfly.visible) continue;
      final index = (model.ticks * GameModel.tickSeconds / 0.05).floor();
      late String name;
      late ui.Rect source;
      if (_level == 6) {
        name = 'classic_atlas.png';
        source = ui.Rect.fromLTWH((index % 8) * 50, 551, 50, 50);
      } else if (_level == 7) {
        name = 'winter_level_atlas.png';
        source = ui.Rect.fromLTWH(868 + butterfly.color * 40, 801, 40, 53);
      } else {
        name = 'Butterflies.png';
        final start = butterfly.color == 1
            ? 12
            : butterfly.color == 2
            ? 6
            : 0;
        source = atlasCellRect(
          start + index % 6,
          width: 50,
          height: 50,
          columns: 5,
        );
      }
      _drawCentered(
        canvas,
        name,
        butterfly.x,
        butterfly.y - model.cameraY,
        source: source,
        scale: butterfly.size,
        rotation: (_level == 6 || _level == 7)
            ? butterfly.rotation
            : butterfly.rotation + 80,
      );
    }
  }

  void _renderHud(ui.Canvas canvas) {
    _drawAtlasNumber(canvas, model.score.toString(), 10, 450);
    final icon = _level == 7 ? 'scores_giftbox.png' : 'scores_butterfly.png';
    _drawCentered(canvas, icon, 145, 460);
    _drawAtlasNumber(canvas, model.butterflyCount.toString(), 160, 450);
    _drawCentered(canvas, 'pause_btn.png', 300, 460);
    if (_level < 5) {
      final progress = model.progress.clamp(0.0, 1.0);
      _drawCentered(canvas, 'jump_progress_frame.png', 160, 440);
      if (progress > 0) {
        final image = _sprites['jump_progress_fill.png']!;
        _drawRect(
          canvas,
          'jump_progress_fill.png',
          ui.Rect.fromLTWH(
            10,
            480 - 440 - image.height / 2,
            300 * progress,
            image.height.toDouble(),
          ),
        );
      }
    }
  }

  void _drawAtlasNumber(ui.Canvas canvas, String text, double x, double y) {
    for (final rune in text.runes) {
      final frame = rune - 44;
      if (frame >= 0 && frame <= 13) {
        _drawRect(
          canvas,
          'fps_font1.png',
          ui.Rect.fromLTWH(x, 480 - y - 24, 10, 24),
          source: ui.Rect.fromLTWH(frame * 10, 0, 10, 24),
        );
      }
      x += 10;
    }
  }

  void drawOriginalText(
    ui.Canvas canvas,
    String text,
    ui.Offset position, {
    String font = 'white_font',
    double scale = 1,
  }) {
    final metadata = _fonts[font];
    if (metadata == null) return;
    var x = position.dx;
    var y = position.dy;
    for (final rune in text.runes) {
      if (rune == 10) {
        x = position.dx;
        y += metadata.lineHeight * scale;
        continue;
      }
      final glyph = metadata.glyphs[rune];
      if (glyph == null) continue;
      _drawRect(
        canvas,
        metadata.image,
        ui.Rect.fromLTWH(
          x + glyph.xOffset * scale,
          y + glyph.yOffset * scale,
          glyph.source.width * scale,
          glyph.source.height * scale,
        ),
        source: glyph.source,
      );
      x += glyph.advance * scale;
    }
  }

  void _drawRect(
    ui.Canvas canvas,
    String name,
    ui.Rect destination, {
    ui.Rect? source,
    double opacity = 1,
  }) {
    final image = _sprites[name];
    if (image == null ||
        !destination.overlaps(const ui.Rect.fromLTWH(0, 0, 320, 480))) {
      return;
    }
    _spritePaint.color = ui.Color.fromRGBO(
      255,
      255,
      255,
      opacity.clamp(0.0, 1.0),
    );
    canvas.drawImageRect(
      image,
      source ??
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
      destination,
      _spritePaint,
    );
  }

  void _drawCentered(
    ui.Canvas canvas,
    String name,
    double x,
    double y, {
    ui.Rect? source,
    double scale = 1,
    double rotation = 0,
    bool flipX = false,
    double opacity = 1,
  }) {
    final image = _sprites[name];
    if (image == null ||
        !x.isFinite ||
        !y.isFinite ||
        scale <= 0 ||
        opacity <= 0) {
      return;
    }
    final rect =
        source ??
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final width = rect.width * scale;
    final height = rect.height * scale;
    final radius = math.sqrt(width * width + height * height) / 2;
    if (x + radius < 0 ||
        x - radius > 320 ||
        y + radius < 0 ||
        y - radius > 480) {
      return;
    }
    canvas.save();
    canvas.translate(x, 480 - y);
    // Cocos2d's positive sprite rotation is clockwise in the displayed view.
    canvas.rotate(rotation * math.pi / 180);
    if (flipX) canvas.scale(-1, 1);
    _spritePaint.color = ui.Color.fromRGBO(
      255,
      255,
      255,
      opacity.clamp(0.0, 1.0),
    );
    canvas.drawImageRect(
      image,
      rect,
      ui.Rect.fromCenter(center: ui.Offset.zero, width: width, height: height),
      _spritePaint,
    );
    canvas.restore();
  }
}

class _Decoration {
  _Decoration({
    required this.x,
    required this.y,
    required this.frame,
    this.scale = 1,
  });
  double x;
  double y;
  int frame;
  double scale;
}

class _BitmapFont {
  _BitmapFont(this.image, this.lineHeight, this.glyphs);
  final String image;
  final double lineHeight;
  final Map<int, _Glyph> glyphs;
  factory _BitmapFont.parse(String source) {
    final image = RegExp(r'page id=0 file="([^"]+)"')
        .firstMatch(source)!
        .group(1)!;
    final lineHeight = double.parse(
      RegExp(r'lineHeight=(\d+)').firstMatch(source)!.group(1)!,
    );
    final glyphs = <int, _Glyph>{};
    for (final line in source.split('\n')) {
      if (!line.startsWith('char id=')) continue;
      final values = <String, int>{
        for (final match in RegExp(r'(\w+)=(-?\d+)').allMatches(line))
          match.group(1)!: int.parse(match.group(2)!),
      };
      glyphs[values['id']!] = _Glyph(
        ui.Rect.fromLTWH(
          values['x']!.toDouble(),
          values['y']!.toDouble(),
          values['width']!.toDouble(),
          values['height']!.toDouble(),
        ),
        values['xoffset']!.toDouble(),
        values['yoffset']!.toDouble(),
        values['xadvance']!.toDouble(),
      );
    }
    return _BitmapFont(image, lineHeight, glyphs);
  }
}

class _Glyph {
  _Glyph(this.source, this.xOffset, this.yOffset, this.advance);
  final ui.Rect source;
  final double xOffset;
  final double yOffset;
  final double advance;
}

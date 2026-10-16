import 'dart:math' as math;
import 'dart:typed_data';

enum GamePhase { menu, playing, gameOver, scores }

enum KittenAnimation { sit, run, jump }

enum GameSound { cloud, butterfly }

final _floatScratch = Float32List(1);
double _f32(double value) {
  _floatScratch[0] = value;
  return _floatScratch[0];
}

class LevelConfig {
  const LevelConfig(this.data);
  final Map<String, Object> data;
  int get id => data['LevelNumber'] as int;
  int get levelNumber => id;
  String get name => data['LevelName'] as String;
  String get levelName => name;
  double number(String key) => (data[key] as num? ?? 0).toDouble();
  int integer(String key) => number(key).toInt();
  bool flag(String key) => integer(key) != 0;
  List<double> point(String key) =>
      (data[key] as List).map((v) => (v as num).toDouble()).toList();
  String image(String key) => data[key] as String;
  bool get endless => id >= 5;
  double get gravity => number('Gravity');
  double get jumpSpeed => number('JumpSpeed');
  double get cloudWidth => number('CloudWidth');
  double get cloudHeight => number('CloudHeight');
  double get cloudAreaWidth => number('CloudAreaWidth');
  double get cloudAreaHeight => number('CloudAreaHeight');
  double get cloudXOffset => number('CloudXOffset');
  double get cloudYOffset => number('CloudYOffset');
  double get finalHeight => number('FinalHeight');
  double get finalCameraPos => number('FinalCameraPos');
  double get cloudsAbsTop => number('CloudsAbsTop');
  double get cloudsAbsBottom => number('CloudsAbsBottom');
  double get cloudsMoveDownSpeed => number('CloudsMoveDownSpeed');
  bool get hasToFallOnCloud => flag('HasToFallOnCloud');
  bool get cloudsPop => flag('CloudsPop');
  bool get cloudsBounce => flag('CloudsBounce');
  bool get cloudsInvert => flag('CloudsInvert');
  int get scorePerCloud => integer('ScorePerCloud');
  int get popFrames => integer('PopFrames');
  int get randomFrames => integer('RandomFrames');
  int get numClouds => integer('NumClouds');
  int get numButterflies => integer('NumButterflies');
  String get cloudsAtlas => image('CloudsAtlas');
  int get cloudsAtlasWidth => integer('CloudsAtlasWidth');
  List<double> get cloudAtlasStartOffset => point('CloudAtlasStartOffset');
  String get groundBackImg => image('GroundBackImg');
  String get groundFrontImg => image('GroundFrontImg');
  List<double> get groundBackPos => point('GroundBackPos');
  List<double> get groundFrontPos => point('GroundFrontPos');
  String get endLayerImage => image('EndLayerImage');
  List<double> get endLayerImagePos => point('EndLayerImagePos');
  List<double> get endLayerArea => point('EndLayerArea');
  String get backgroundLoopImg => image('BackgroundLoopImg');
  int get backgroundImgHeight => integer('BackgroundImgHeight');
  int get backgroundOverlap => integer('BackgroundOverlap');
  List<int> get backgroundColor =>
      (data['BackgroundColor'] as List).cast<int>();
  List<int> get backgroundEndColor =>
      (data['BackgroundEndColor'] as List).cast<int>();
  List<int> get requiredForStar =>
      (data['RequiredForStar'] as List).cast<int>();
  List<double> get kittenStartPosition => point('KittenStartPosition');
}

class Cloud {
  Cloud({
    required this.x,
    required this.y,
    this.size = 1,
    this.popped = 0,
    this.frame = 0,
    bool movingRight = false,
    this.xSpeed = 0,
    bool? inverted,
  }) : inverted = inverted ?? movingRight;
  double x;
  double y;
  double size;
  int popped;
  int popCount = 0;
  int frame;
  bool get movingRight => inverted;
  set movingRight(bool value) => inverted = value;
  double xSpeed;
  bool inverted;
  bool gotOnce = false;
  bool visible = true;
  bool overTop = false;
  double rotation = 0;
  double rotationSpeed = 0;
  double acceleration = 0;
  double offset = 0;
  double angle = 0;
  double amplitude = 0;
  int get spriteFrame => frame;
  bool get flipX => false;
}

class Butterfly {
  Butterfly({
    required this.x,
    required this.y,
    this.size = 1,
    this.color = 0,
    this.speed = 1,
    this.flies = true,
  });
  double x;
  double y;
  double size;
  int color;
  double speed;
  bool flies;
  int frame = 0;
  int popped = 0;
  double rotation = 0;
  double rotationVar = 1;
  bool movingRight = false;
  bool visible = true;
}

/// Kitten Jump Paid 2.1.1 dynamics in its original 320×480 world coordinates.
/// Constants come from Levels.init; update order follows DynamicsLayer.updateTimer.
class GameModel {
  GameModel({int seed = 1, this.selectedLevel = 7})
    : _random = math.Random(seed) {
    reset();
    showMenu();
  }
  static const width = 320.0;
  static const height = 480.0;
  static const tickSeconds = 1 / 50;
  static const List<LevelConfig> levels = _recoveredLevels;
  final math.Random _random;
  final List<GameSound> _sounds = [];
  GamePhase phase = GamePhase.menu;
  int selectedLevel;
  String skin = 'red_kitten.png';
  int score = 0;
  int butterflyCount = 0;
  int butterflyCombo = 0;
  int ticks = 0;
  int jumpGeneration = 0;
  double playerX = 160;
  double playerY = 1;
  double targetX = 160;
  double velocityY = 0;
  double cameraY = 0;
  double cameraDelta = 0;
  bool jumping = false;
  bool sitting = true;
  bool facingLeft = false;
  bool freeFall = false;
  bool gotFirstOne = false;
  bool reached = false;
  bool won = false;
  KittenAnimation animation = KittenAnimation.sit;
  double _maximumY = 0;
  double _filteredTiltX = 0;
  final List<Cloud> clouds = [];
  final List<Butterfly> butterflies = [];
  LevelConfig get currentLevel => levels[selectedLevel];
  int get totalHeight => playerY.toInt();
  set totalHeight(int value) => playerY = value.toDouble();
  int get kittenFrame => 0;
  bool get floorVisible => cameraY < 160;
  double get floorY => -cameraY;
  int get heightFeet => math.max(0, playerY.toInt()) ~/ 20;
  double get progress => (_maximumY / currentLevel.finalHeight).clamp(0, 1);
  int get earnedStars => won
      ? currentLevel.requiredForStar.where((v) => butterflyCount >= v).length
      : 0;
  double get skyRed => _skyChannel(0);
  double get skyGreen => _skyChannel(1);
  double get skyBlue => _skyChannel(2);
  double _skyChannel(int index) {
    final c = currentLevel;
    final t = (playerY / (c.number('BackgroundChangeEnd') + 480)).clamp(0, 1);
    return (c.backgroundColor[index] +
            (c.backgroundEndColor[index] - c.backgroundColor[index]) * t) /
        255;
  }

  double _unit() =>
      _f32(_f32(_random.nextInt(1 << 31).toDouble()) * 4.656612873077393e-10);
  void selectLevel(int levelNumber) {
    if (levelNumber < 0 || levelNumber >= levels.length) {
      throw RangeError.range(levelNumber, 0, levels.length - 1, 'levelNumber');
    }
    selectedLevel = levelNumber;
    reset();
    showMenu();
  }

  void start({int? levelNumber}) => reset(levelNumber: levelNumber);
  void reset({int? levelNumber}) {
    if (levelNumber != null) {
      if (levelNumber < 0 || levelNumber >= levels.length) {
        throw RangeError.range(
          levelNumber,
          0,
          levels.length - 1,
          'levelNumber',
        );
      }
      selectedLevel = levelNumber;
    }
    final c = currentLevel;
    phase = GamePhase.playing;
    score = 0;
    butterflyCount = 0;
    butterflyCombo = 0;
    ticks = 0;
    cameraY = 0;
    cameraDelta = 0;
    playerX = c.kittenStartPosition[0];
    playerY = c.kittenStartPosition[1];
    _maximumY = playerY;
    targetX = 160;
    velocityY = 0;
    jumping = false;
    sitting = true;
    facingLeft = false;
    freeFall = false;
    gotFirstOne = false;
    reached = false;
    won = false;
    animation = KittenAnimation.sit;
    _sounds.clear();
    clouds.clear();
    butterflies.clear();
    final span = c.cloudsAbsTop - c.cloudsAbsBottom;
    final spacing = span / c.numClouds;
    final initialSpacing = c.cloudsMoveDownSpeed == 0 ? 0 : spacing;
    for (var i = 0; i < c.numClouds; i++) {
      final size = c.number('CloudSizeMax');
      final x =
          size * c.cloudWidth / 2 + _unit() * (width - size * c.cloudWidth);
      final cloud = Cloud(
        x: _f32(x),
        y: _f32(
          c.cloudsAbsBottom +
              c.number('CloudsStartOffset') +
              initialSpacing +
              spacing * i,
        ),
        size: size,
        frame: _random.nextInt(c.randomFrames),
        xSpeed: _initialCloudSpeed(c),
        inverted: c.cloudsInvert && _unit() > .5,
      );
      if (selectedLevel == 1 || selectedLevel == 7) {
        cloud.amplitude = _unit();
        cloud.rotationSpeed = _unit();
        cloud.rotation = _f32(cloud.amplitude * -45);
      }
      if (selectedLevel == 3 && !cloud.inverted) {
        cloud.frame += c.randomFrames;
      }
      clouds.add(cloud);
    }
    for (var i = 0; i < c.numButterflies; i++) {
      butterflies.add(
        Butterfly(
          x: 160,
          y:
              240 +
              c.number('ButterflyEvery') * (i + (selectedLevel >= 6 ? 1 : 0)),
          size: c.number('ButterflySizeMax'),
          color: selectedLevel == 7 ? 0 : i,
          speed: c.number('ButterflySpeedMin'),
          flies: true,
        ),
      );
    }
  }

  double _initialCloudSpeed(LevelConfig c) {
    if (c.number('CloudSpeedXChangeStart') != 0 &&
        c.number('CloudSpeedXChangeEnd') != 0) {
      return c.number('CloudXSpeedMin');
    }
    return _f32(
      c.number('CloudXSpeedMin') +
          _unit() * (c.number('CloudXSpeedMax') - c.number('CloudXSpeedMin')),
    );
  }

  void showMenu() {
    phase = GamePhase.menu;
    cameraDelta = 0;
    _sounds.clear();
  }

  void showScores() {
    phase = GamePhase.scores;
    cameraDelta = 0;
    _sounds.clear();
  }

  void jump() {
    if (phase != GamePhase.playing || jumping) return;
    _bounce();
  }

  void _bounce() {
    jumping = true;
    sitting = false;
    velocityY = currentLevel.jumpSpeed;
    animation = KittenAnimation.jump;
    jumpGeneration++;
  }

  void setTarget(double x) {
    if (phase != GamePhase.playing || !x.isFinite) return;
    targetX = _f32(x.clamp(0, width));
  }

  void applyTilt(double gX) {
    if (phase != GamePhase.playing || !jumping || !gX.isFinite) return;
    _filteredTiltX = _f32(gX * .3 + _filteredTiltX * .7);
    setTarget(_f32(_f32(_filteredTiltX * width) + width / 2));
  }

  List<GameSound> drainSounds() {
    final result = List<GameSound>.of(_sounds);
    _sounds.clear();
    return result;
  }

  void tick() {
    if (phase != GamePhase.playing) return;
    final c = currentLevel;
    ticks++;
    final oldCamera = cameraY;
    var center = cameraY + 240;
    if (reached) {
      center = c.finalCameraPos + (c.finalCameraPos - center) / -1.5;
    } else {
      center = _f32(center + (40 + playerY - center) / 10);
    }
    if (freeFall) center = playerY;
    cameraY = _f32(math.max(240, center) - 240);
    cameraDelta = _f32(cameraY - oldCamera);
    final oldY = playerY;
    playerX = _f32(playerX + (targetX - playerX) / 10);
    facingLeft = targetX - playerX <= 0;
    if (jumping) {
      velocityY = _f32(velocityY - c.gravity);
      final nextY = _f32(playerY + velocityY);
      if (reached && nextY <= c.finalHeight) {
        playerY = c.finalHeight;
        jumping = false;
        velocityY = 0;
        animation = KittenAnimation.sit;
        won = true;
        phase = GamePhase.gameOver;
        return;
      }
      if (nextY < c.kittenStartPosition[1]) {
        playerY = c.kittenStartPosition[1];
        jumping = false;
        velocityY = 0;
        animation = KittenAnimation.sit;
        sitting = true;
        if (gotFirstOne) {
          phase = GamePhase.gameOver;
          return;
        }
      } else {
        playerY = nextY;
      }
    } else {
      sitting = (targetX - playerX).abs() < 1;
      animation = sitting ? KittenAnimation.sit : KittenAnimation.run;
    }
    freeFall = true;
    final kittenWidth = selectedLevel >= 6 ? 45.0 : 50.0;
    final kittenHalf = (kittenWidth.toInt() >> 1).toDouble();
    for (final cloud in clouds) {
      _moveCloud(cloud);
      if (cloud.visible &&
          cloud.popped == 0 &&
          !cloud.overTop &&
          jumping &&
          (cloud.y - playerY).abs() < 100) {
        final rectX =
            cloud.x -
            c.cloudAreaWidth * cloud.size / 2 +
            c.cloudXOffset * cloud.size;
        final rectY =
            cloud.y +
            c.cloudAreaHeight * cloud.size / 2 +
            c.cloudYOffset * cloud.size;
        final overlaps = _overlap(
          rectX,
          rectY,
          c.cloudAreaWidth * cloud.size,
          c.cloudAreaHeight * cloud.size,
          playerX - kittenHalf,
          playerY,
          kittenWidth,
          22,
        );
        final falling = velocityY <= 0 && oldY > rectY && rectY >= playerY;
        if (overlaps && (!c.hasToFallOnCloud || falling)) {
          gotFirstOne = true;
          if (c.cloudsPop) {
            cloud.popped = 1;
            cloud.popCount = 0;
          }
          if (selectedLevel == 1) cloud.acceleration = 1;
          _bounce();
          score = _add64(score, c.scorePerCloud);
          _sounds.add(GameSound.cloud);
        }
      }
      if (playerY > cloud.y - 240 && cloud.popped == 0 && cloud.visible) {
        freeFall = false;
      }
    }
    for (final butterfly in butterflies) {
      _moveButterfly(butterfly);
      if (!butterfly.flies || !butterfly.visible) continue;
      final area = selectedLevel == 6
          ? 30.0
          : selectedLevel == 7
          ? 40.0
          : 50.0;
      if (_overlap(
        butterfly.x - area * butterfly.size / 2,
        butterfly.y - area * butterfly.size / 2,
        area * butterfly.size,
        area * butterfly.size,
        playerX - kittenHalf,
        playerY,
        kittenWidth,
        22,
      )) {
        gotFirstOne = true;
        butterflyCount++;
        if (selectedLevel >= 6) {
          score = _add64(score, score);
        } else {
          butterflyCombo++;
          score = _add64(score, butterflyCombo * 200);
        }
        _sounds.add(GameSound.butterfly);
        _bounce();
        _resetButterfly(butterfly);
      }
    }
    _maximumY = math.max(_maximumY, playerY);
    if (playerY > c.finalHeight) reached = true;
  }

  void _moveCloud(Cloud cloud) {
    final c = currentLevel;
    if (selectedLevel == 1) {
      if (cloud.acceleration > 0) {
        cloud.y = _f32(cloud.y - cloud.acceleration);
        cloud.offset = _f32(cloud.offset + cloud.acceleration);
        cloud.acceleration = _f32(cloud.acceleration - .1);
      }
      final a = cloud.rotation + cloud.rotationSpeed;
      if (a > cloud.amplitude * 45 || a < cloud.amplitude * -45) {
        cloud.rotationSpeed *= -1;
      }
      cloud.rotation = _f32(a);
    }
    if (c.cloudsPop && cloud.popped > 0) {
      if (cloud.popCount < c.popFrames && _unit() > .5) {
        cloud.frame =
            (selectedLevel == 3 ? c.randomFrames * 2 : c.randomFrames) +
            cloud.popCount;
        cloud.popCount++;
      } else if (cloud.popCount >= c.popFrames) {
        _recycleCloud(cloud);
      }
    }
    if (cameraY + 240 - cloud.y > 240 - c.cloudsAbsBottom &&
        cloud.popped == 0) {
      _recycleCloud(cloud);
    }
    if (cloud.y < c.cloudsAbsBottom &&
        cloud.popped == 0 &&
        c.cloudsMoveDownSpeed != 0) {
      if (c.cloudsPop) {
        cloud.popped = 1;
      } else {
        _recycleCloud(cloud);
      }
    }
    cloud.x = _f32(cloud.x + cloud.xSpeed * (cloud.movingRight ? 1 : -1));
    final half = c.cloudAreaWidth * cloud.size / 2;
    if (c.cloudsBounce) {
      if (cloud.movingRight && cloud.x >= width - half) {
        cloud.movingRight = false;
        if (selectedLevel == 3) cloud.frame += c.randomFrames;
      }
      if (!cloud.movingRight && cloud.x <= half) {
        cloud.movingRight = true;
        if (selectedLevel == 3) cloud.frame -= c.randomFrames;
      }
    } else {
      if (cloud.movingRight && cloud.x >= width + 2 * half) cloud.x = -2 * half;
      if (!cloud.movingRight && cloud.x <= -2 * half) {
        cloud.x = width + 2 * half;
      }
    }
    cloud.y = _f32(cloud.y - c.cloudsMoveDownSpeed);
    if (cloud.overTop &&
        cloud.y <= c.finalHeight - c.number('FinalCloudClearance')) {
      cloud.overTop = false;
      cloud.visible = true;
    }
  }

  void _recycleCloud(Cloud cloud) {
    final c = currentLevel;
    cloud.popped = 0;
    cloud.popCount = 0;
    cloud.y = _f32(cloud.y + c.cloudsAbsTop - c.cloudsAbsBottom + cloud.offset);
    final inset = selectedLevel >= 6 ? cloud.size * c.cloudWidth / 2 : 0.0;
    cloud.x = _f32(inset + _unit() * (width - inset * 2));
    cloud.offset = 0;
    cloud.acceleration = 0;
    cloud.overTop = cloud.y > c.finalHeight - c.number('FinalCloudClearance');
    cloud.visible = !cloud.overTop;
    cloud.size = _changing(
      c.number('CloudSizeMax'),
      c.number('CloudSizeMin'),
      c.number('CloudSizeChangeStart'),
      c.number('CloudSizeChangeEnd'),
      c.finalHeight,
    );
    if (c.number('CloudSpeedXChangeStart') != 0 &&
        c.number('CloudSpeedXChangeEnd') != 0) {
      cloud.xSpeed = _changing(
        c.number('CloudXSpeedMin'),
        c.number('CloudXSpeedMax'),
        c.number('CloudSpeedXChangeStart'),
        c.number('CloudSpeedXChangeEnd'),
        c.finalHeight,
      );
    } else {
      cloud.xSpeed = _initialCloudSpeed(c);
    }
    cloud.inverted = c.cloudsInvert && _unit() > .5;
    cloud.frame = _random.nextInt(c.randomFrames);
    if (selectedLevel == 3 && !cloud.inverted) cloud.frame += c.randomFrames;
    cloud.gotOnce = false;
  }

  double _changing(
    double from,
    double to,
    double start,
    double end,
    double fallback,
  ) {
    final t = start != 0 && end != 0
        ? ((playerY - start) / (end - start)).clamp(0, 1)
        : (playerY / fallback).clamp(0, 1);
    return _f32(from + (to - from) * t);
  }

  void _moveButterfly(Butterfly b) {
    b.frame = (ticks * tickSeconds / .04).floor() % 6;
    if (b.flies) {
      if (selectedLevel >= 6) {
        b.x = _f32(b.x + b.speed * b.size * (b.movingRight ? 1 : -1));
        if (b.x > width) {
          b.x = 319;
          b.movingRight = false;
        }
        if (b.x < 0) {
          b.x = 1;
          b.movingRight = true;
        }
      } else {
        if (_unit() > .95 || b.rotation < -90 || b.rotation > 90) {
          b.rotationVar *= -1;
        }
        b.rotation = _f32(b.rotation.clamp(-89, 89) + b.rotationVar);
        final radians = b.rotation * math.pi / 180;
        b.x = _f32(b.x + b.speed * math.sin(radians));
        b.y = _f32(b.y + b.speed * math.cos(radians));
        if (b.x > 320) {
          b.x = 319;
          b.rotation *= -1;
        }
        if (b.x < 0) {
          b.x = 1;
          b.rotation *= -1;
        }
      }
    }
    if (selectedLevel < 6 && b.y - playerY <= 280) b.flies = true;
    final c = currentLevel;
    if (playerY - b.y > 340 - c.cloudsAbsBottom ||
        (b.flies && b.y - playerY > c.cloudsAbsTop)) {
      _resetButterfly(b);
    }
  }

  void _resetButterfly(Butterfly b) {
    final c = currentLevel;
    b.speed = _f32(
      c.number('ButterflySpeedMin') +
          _unit() *
              (c.number('ButterflySpeedMax') - c.number('ButterflySpeedMin')),
    );
    if (c.number('ButterflySizeChangeStart') != 0 &&
        c.number('ButterflySizeChangeEnd') != 0) {
      b.size = _changing(
        c.number('ButterflySizeMax'),
        c.number('ButterflySizeMin'),
        c.number('ButterflySizeChangeStart'),
        c.number('ButterflySizeChangeEnd'),
        c.finalHeight,
      );
    } else {
      b.size = _f32(
        c.number('ButterflySizeMin') +
            _unit() *
                (c.number('ButterflySizeMax') - c.number('ButterflySizeMin')),
      );
    }
    b.x = _f32(_unit() * 318 + 1);
    b.y = _f32(playerY + c.number('ButterflyEvery') + _unit() * 100 - 50);
    b.flies = selectedLevel >= 6;
    if (selectedLevel == 7) b.color = _random.nextInt(3);
  }

  static bool _overlap(
    double ax,
    double ay,
    double aw,
    double ah,
    double bx,
    double by,
    double bw,
    double bh,
  ) => ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  static int _add64(int a, int b) => (a + b).toSigned(64);
}

const _recoveredLevels = <LevelConfig>[
  LevelConfig({
    'LevelNumber': 0,
    'LevelName': "First Jumps",
    'CloudWidth': 168.0,
    'CloudHeight': 63.0,
    'CloudAreaWidth': 58.0,
    'CloudAreaHeight': 20.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': 3.0,
    'CloudsMoveDownSpeed': 0.0,
    'CloudSizeMax': 1.0,
    'CloudSizeMin': 1.0,
    'NumClouds': 6,
    'CloudsAbsTop': 600.0,
    'CloudsAbsBottom': -216.0,
    'CloudsStartOffset': 370.0,
    'Gravity': 0.5799999833106995,
    'JumpSpeed': 14.520000457763672,
    'ScorePerCloud': 0,
    'HasToFallOnCloud': 1,
    'EndLayerImage': "roof_lvl1.png",
    'CloudsAtlas': "BricksSprite.png",
    'CloudsAtlasCapacity': 3,
    'CloudsAtlasWidth': 256,
    'CloudsPop': 0,
    'KittenStartPosition': [160.0, 10.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 7.0],
    'GroundBackImg': "fundament.png",
    'GroundBackPos': [160.0, 69.0],
    'BackgroundLoopImg': "WallSprites.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [206, 215, 241, 255],
    'BackgroundEndColor': [206, 215, 241, 255],
    'EndLayerImagePos': [160.0, 13892.0],
    'EndLayerArea': [160.0, 13742.0, 320.0, 40.0],
    'FinalHeight': 13742.0,
    'FinalCloudClearance': 65.0,
    'FinalCameraPos': 13892.0,
    'ButterflySizeMax': 1.0,
    'ButterflySizeMin': 0.6000000238418579,
    'ButterflySpeedMax': 3.0,
    'ButterflySpeedMin': 2.0,
    'ButterflyEvery': 1000.0,
    'NumButterflies': 1,
    'CloudXSpeedMax': 0.0,
    'CloudsInvert': 0,
    'RandomFrames': 3,
    'CloudsBounce': 0,
    'RequiredForStar': [6, 9, 11],
    'CloudSizeChangeStart': 0.0,
    'CloudSizeChangeEnd': 0.0,
    'CloudSpeedXChangeStart': 0.0,
    'CloudSpeedXChangeEnd': 0.0,
    'ButterflySpeedChangeStart': 13892.0,
    'ButterflySizeChangeStart': 0.0,
    'ButterflySizeChangeEnd': 13892.0,
    'BackgroundChangeEnd': 13892.0,
    'CloudAtlasStartOffset': [0.0, 0.0],
  }),
  LevelConfig({
    'LevelNumber': 1,
    'LevelName': "Falling Leaves",
    'CloudWidth': 90.0,
    'CloudHeight': 40.0,
    'CloudAreaWidth': 70.0,
    'CloudAreaHeight': 20.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': 0.0,
    'CloudsMoveDownSpeed': 0.30000001192092896,
    'CloudSizeMax': 0.6000000238418579,
    'CloudSizeMin': 0.6000000238418579,
    'NumClouds': 6,
    'CloudsAbsTop': 550.0,
    'CloudsAbsBottom': -180.0,
    'CloudsStartOffset': 120.0,
    'Gravity': 0.5400000214576721,
    'JumpSpeed': 16.950000762939453,
    'ScorePerCloud': 0,
    'HasToFallOnCloud': 1,
    'EndLayerImage': "tree_top.png",
    'CloudsAtlas': "LeafAtlas.png",
    'CloudsAtlasCapacity': 2,
    'CloudsAtlasWidth': 256,
    'CloudsPop': 0,
    'KittenStartPosition': [160.0, 60.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 10.0],
    'GroundBackImg': "roof_lvl2.png",
    'GroundBackPos': [160.0, 45.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [206, 215, 241, 255],
    'BackgroundEndColor': [139, 153, 193, 255],
    'EndLayerImagePos': [160.0, 27174.0],
    'EndLayerArea': [160.0, 27364.0, 320.0, 200.0],
    'FinalHeight': 27374.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 27574.0,
    'ButterflySizeMax': 0.800000011920929,
    'ButterflySizeMin': 0.6000000238418579,
    'ButterflySpeedMax': 4.0,
    'ButterflySpeedMin': 3.0,
    'ButterflyEvery': 1000.0,
    'NumButterflies': 2,
    'CloudXSpeedMax': 0.0,
    'CloudsInvert': 0,
    'RandomFrames': 2,
    'CloudsBounce': 0,
    'RequiredForStar': [21, 32, 42],
    'CloudSizeChangeStart': 0.0,
    'CloudSizeChangeEnd': 0.0,
    'CloudSpeedXChangeStart': 0.0,
    'CloudSpeedXChangeEnd': 0.0,
    'ButterflySpeedChangeStart': 27174.0,
    'ButterflySizeChangeStart': 0.0,
    'ButterflySizeChangeEnd': 27174.0,
    'BackgroundChangeEnd': 27174.0,
    'CloudAtlasStartOffset': [0.0, 0.0],
  }),
  LevelConfig({
    'LevelNumber': 2,
    'LevelName': "Up to the Skies",
    'CloudWidth': 90.0,
    'CloudHeight': 90.0,
    'CloudAreaWidth': 60.0,
    'CloudAreaHeight': 30.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': -30.0,
    'CloudsMoveDownSpeed': 0.44999998807907104,
    'CloudSizeMax': 0.8999999761581421,
    'CloudSizeMin': 0.30000001192092896,
    'NumClouds': 5,
    'CloudsAbsTop': 500.0,
    'CloudsAbsBottom': -100.0,
    'CloudsStartOffset': 140.0,
    'Gravity': 0.4399999976158142,
    'JumpSpeed': 13.699999809265137,
    'ScorePerCloud': 10,
    'HasToFallOnCloud': 0,
    'EndLayerImage': "big_cloud.png",
    'CloudsAtlas': "CloudAtlas.png",
    'CloudsAtlasCapacity': 7,
    'CloudsAtlasWidth': 512,
    'CloudsPop': 1,
    'KittenStartPosition': [160.0, 40.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 10.0],
    'GroundBackImg': "tree_top.png",
    'GroundBackPos': [160.0, -156.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [139, 153, 193, 255],
    'BackgroundEndColor': [20, 36, 80, 255],
    'EndLayerImagePos': [160.0, 40914.0],
    'EndLayerArea': [160.0, 41104.0, 320.0, 200.0],
    'FinalHeight': 40924.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 41114.0,
    'ButterflySizeMax': 0.6000000238418579,
    'ButterflySizeMin': 0.4000000059604645,
    'ButterflySpeedMax': 4.5,
    'ButterflySpeedMin': 4.0,
    'ButterflyEvery': 1000.0,
    'NumButterflies': 3,
    'CloudXSpeedMax': 0.0,
    'CloudsInvert': 0,
    'RandomFrames': 3,
    'PopFrames': 4,
    'CloudsBounce': 0,
    'RequiredForStar': [35, 53, 65],
    'CloudSizeChangeStart': 0.0,
    'CloudSizeChangeEnd': 0.0,
    'CloudSpeedXChangeStart': 0.0,
    'CloudSpeedXChangeEnd': 0.0,
    'ButterflySpeedChangeStart': 40914.0,
    'ButterflySizeChangeStart': 0.0,
    'ButterflySizeChangeEnd': 40914.0,
    'BackgroundChangeEnd': 40914.0,
    'CloudAtlasStartOffset': [0.0, 0.0],
  }),
  LevelConfig({
    'LevelNumber': 3,
    'LevelName': "Star Wars",
    'CloudWidth': 150.0,
    'CloudHeight': 46.0,
    'CloudAreaWidth': 28.0,
    'CloudAreaHeight': 28.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': -14.0,
    'CloudsMoveDownSpeed': 0.0,
    'CloudSizeMax': 0.8999999761581421,
    'CloudSizeMin': 0.4000000059604645,
    'NumClouds': 5,
    'CloudsAbsTop': 700.0,
    'CloudsAbsBottom': -50.0,
    'CloudsStartOffset': 200.0,
    'Gravity': 0.3799999952316284,
    'JumpSpeed': 12.699999809265137,
    'ScorePerCloud': 10,
    'HasToFallOnCloud': 0,
    'EndLayerImage': "mks.png",
    'CloudsAtlas': "sputniks.png",
    'CloudsAtlasCapacity': 13,
    'CloudsAtlasWidth': 512,
    'CloudsPop': 1,
    'KittenStartPosition': [160.0, 40.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 10.0],
    'GroundBackImg': "big_cloud.png",
    'GroundBackPos': [160.0, 30.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [20, 36, 80, 255],
    'BackgroundEndColor': [33, 24, 37, 255],
    'EndLayerImagePos': [160.0, 54654.0],
    'EndLayerArea': [160.0, 54844.0, 320.0, 200.0],
    'FinalHeight': 54669.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 54854.0,
    'ButterflySizeMax': 0.6000000238418579,
    'ButterflySizeMin': 0.4000000059604645,
    'ButterflySpeedMax': 5.0,
    'ButterflySpeedMin': 4.0,
    'ButterflyEvery': 1000.0,
    'NumButterflies': 3,
    'CloudXSpeedMin': 0.5,
    'CloudXSpeedMax': 1.2000000476837158,
    'CloudsInvert': 1,
    'RandomFrames': 3,
    'PopFrames': 7,
    'CloudsBounce': 1,
    'RequiredForStar': [48, 64, 85],
    'CloudSizeChangeStart': 0.0,
    'CloudSizeChangeEnd': 0.0,
    'CloudSpeedXChangeStart': 0.0,
    'CloudSpeedXChangeEnd': 0.0,
    'ButterflySpeedChangeStart': 54654.0,
    'ButterflySizeChangeStart': 0.0,
    'ButterflySizeChangeEnd': 54654.0,
    'BackgroundChangeEnd': 54654.0,
    'CloudAtlasStartOffset': [0.0, 0.0],
  }),
  LevelConfig({
    'LevelNumber': 4,
    'LevelName': "Speed of Light",
    'CloudWidth': 50.0,
    'CloudHeight': 50.0,
    'CloudAreaWidth': 25.0,
    'CloudAreaHeight': 25.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': -12.0,
    'CloudsMoveDownSpeed': 1.7999999523162842,
    'CloudSizeMax': 0.8999999761581421,
    'CloudSizeMin': 0.20000000298023224,
    'NumClouds': 4,
    'CloudsAbsTop': 500.0,
    'CloudsAbsBottom': 0.0,
    'CloudsStartOffset': 200.0,
    'Gravity': 0.36000001430511475,
    'JumpSpeed': 12.199999809265137,
    'ScorePerCloud': 10,
    'HasToFallOnCloud': 0,
    'EndLayerImage': "saturn.png",
    'CloudsAtlas': "asteroid.png",
    'CloudsAtlasCapacity': 29,
    'CloudsAtlasWidth': 512,
    'CloudsPop': 1,
    'KittenStartPosition': [160.0, 40.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 10.0],
    'GroundBackImg': "mks.png",
    'GroundBackPos': [160.0, 30.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [33, 24, 37, 255],
    'BackgroundEndColor': [33, 24, 37, 255],
    'EndLayerImagePos': [160.0, 68466.0],
    'EndLayerArea': [160.0, 68584.0, 320.0, 200.0],
    'FinalHeight': 68409.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 68594.0,
    'ButterflySizeMax': 0.6000000238418579,
    'ButterflySizeMin': 0.4000000059604645,
    'ButterflySpeedMax': 5.0,
    'ButterflySpeedMin': 4.0,
    'ButterflyEvery': 1000.0,
    'NumButterflies': 3,
    'CloudXSpeedMin': 1.0,
    'CloudXSpeedMax': 1.899999976158142,
    'CloudsInvert': 1,
    'RandomFrames': 23,
    'PopFrames': 6,
    'CloudsBounce': 1,
    'RequiredForStar': [45, 65, 86],
    'CloudSizeChangeStart': 0.0,
    'CloudSizeChangeEnd': 0.0,
    'CloudSpeedXChangeStart': 0.0,
    'CloudSpeedXChangeEnd': 0.0,
    'ButterflySpeedChangeStart': 68394.0,
    'ButterflySizeChangeStart': 0.0,
    'ButterflySizeChangeEnd': 68394.0,
    'BackgroundChangeEnd': 68394.0,
    'CloudAtlasStartOffset': [0.0, 0.0],
  }),
  LevelConfig({
    'LevelNumber': 5,
    'LevelName': "Endless mode",
    'CloudWidth': 90.0,
    'CloudHeight': 90.0,
    'CloudAreaWidth': 42.0,
    'CloudAreaHeight': 30.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': -30.0,
    'CloudsMoveDownSpeed': 0.44999998807907104,
    'CloudSizeMax': 0.8999999761581421,
    'CloudSizeMin': 0.20000000298023224,
    'NumClouds': 5,
    'CloudsAbsTop': 500.0,
    'CloudsAbsBottom': -100.0,
    'CloudsStartOffset': 140.0,
    'Gravity': 0.4399999976158142,
    'JumpSpeed': 13.699999809265137,
    'ScorePerCloud': 10,
    'HasToFallOnCloud': 0,
    'EndLayerImage': "big_cloud.png",
    'CloudsAtlas': "CloudAtlas.png",
    'CloudsAtlasCapacity': 7,
    'CloudsAtlasWidth': 512,
    'CloudsPop': 1,
    'KittenStartPosition': [160.0, 6.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 4.0],
    'GroundBackImg': "grass_front.png",
    'GroundBackPos': [160.0, 8.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [139, 153, 193, 255],
    'BackgroundEndColor': [33, 24, 37, 255],
    'EndLayerImagePos': [160.0, 4579694.0],
    'EndLayerArea': [160.0, 4579884.0, 320.0, 200.0],
    'FinalHeight': 4579704.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 4579894.0,
    'ButterflySizeMax': 0.8500000238418579,
    'ButterflySizeMin': 0.25,
    'ButterflySpeedMax': 5.0,
    'ButterflySpeedMin': 2.0,
    'ButterflyEvery': 1000.0,
    'NumButterflies': 3,
    'CloudXSpeedMin': 0.0,
    'CloudXSpeedMax': 2.0,
    'CloudsInvert': 0,
    'RandomFrames': 3,
    'PopFrames': 4,
    'CloudsBounce': 1,
    'RequiredForStar': [],
    'CloudSizeChangeStart': 14400.0,
    'CloudSizeChangeEnd': 86400.0,
    'CloudSpeedXChangeStart': 28800.0,
    'CloudSpeedXChangeEnd': 115200.0,
    'ButterflySpeedChangeStart': 115200.0,
    'ButterflySizeChangeStart': 480.0,
    'ButterflySizeChangeEnd': 115200.0,
    'BackgroundChangeEnd': 43200.0,
    'CloudAtlasStartOffset': [0.0, 0.0],
  }),
  LevelConfig({
    'LevelNumber': 6,
    'LevelName': "Classic mode",
    'CloudWidth': 90.0,
    'CloudHeight': 70.0,
    'CloudAreaWidth': 42.0,
    'CloudAreaHeight': 30.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': -30.0,
    'CloudsMoveDownSpeed': 0.5,
    'CloudSizeMax': 0.800000011920929,
    'CloudSizeMin': 0.10000000149011612,
    'NumClouds': 6,
    'CloudsAbsTop': 500.0,
    'CloudsAbsBottom': -50.0,
    'CloudsStartOffset': 140.0,
    'Gravity': 0.4399999976158142,
    'JumpSpeed': 12.0,
    'ScorePerCloud': 1,
    'HasToFallOnCloud': 0,
    'EndLayerImage': "big_cloud.png",
    'CloudsAtlas': "classic_atlas.png",
    'CloudsAtlasCapacity': 10,
    'CloudsAtlasWidth': 1024,
    'CloudsPop': 1,
    'KittenStartPosition': [160.0, 1.0],
    'GroundFrontImg': "grass_front.png",
    'GroundFrontPos': [160.0, 4.0],
    'GroundBackImg': "grass_back.png",
    'GroundBackPos': [160.0, 8.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [186, 204, 255, 255],
    'BackgroundEndColor': [0, 0, 0, 255],
    'EndLayerImagePos': [160.0, 4579694.0],
    'EndLayerArea': [160.0, 4579884.0, 320.0, 200.0],
    'FinalHeight': 4579704.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 4579894.0,
    'ButterflySizeMax': 1.0,
    'ButterflySizeMin': 1.0,
    'ButterflySpeedMax': 1.0,
    'ButterflySpeedMin': 1.0,
    'ButterflyEvery': 3000.0,
    'NumButterflies': 1,
    'CloudXSpeedMin': 0.0,
    'CloudXSpeedMax': 2.0,
    'CloudsInvert': 0,
    'RandomFrames': 1,
    'PopFrames': 10,
    'CloudAtlasStartOffset': [0.0, 481.0],
    'CloudsBounce': 1,
    'RequiredForStar': [],
    'CloudSizeChangeStart': 14400.0,
    'CloudSizeChangeEnd': 86400.0,
    'CloudSpeedXChangeStart': 14400.0,
    'CloudSpeedXChangeEnd': 86400.0,
    'ButterflySpeedChangeStart': 115200.0,
    'ButterflySizeChangeStart': 480.0,
    'ButterflySizeChangeEnd': 115200.0,
    'BackgroundChangeEnd': 43200.0,
  }),
  LevelConfig({
    'LevelNumber': 7,
    'LevelName': "Christmas Surprise",
    'CloudWidth': 55.0,
    'CloudHeight': 55.0,
    'CloudAreaWidth': 45.0,
    'CloudAreaHeight': 45.0,
    'CloudXOffset': 0.0,
    'CloudYOffset': -30.0,
    'CloudsMoveDownSpeed': 0.800000011920929,
    'CloudSizeMax': 0.800000011920929,
    'CloudSizeMin': 0.10000000149011612,
    'NumClouds': 6,
    'CloudsAbsTop': 500.0,
    'CloudsAbsBottom': -50.0,
    'CloudsStartOffset': 140.0,
    'Gravity': 0.4399999976158142,
    'JumpSpeed': 12.300000190734863,
    'ScorePerCloud': 1,
    'HasToFallOnCloud': 0,
    'EndLayerImage': "big_cloud.png",
    'CloudsAtlas': "winter_level_atlas.png",
    'CloudsAtlasCapacity': 8,
    'CloudsAtlasWidth': 1024,
    'CloudsPop': 1,
    'KittenStartPosition': [160.0, 1.0],
    'GroundFrontImg': "snow_front.png",
    'GroundFrontPos': [160.0, 8.0],
    'GroundBackImg': "snow_back.png",
    'GroundBackPos': [160.0, 68.0],
    'BackgroundLoopImg': "TreeAtlas.png",
    'BackgroundOverlap': 22,
    'BackgroundImgHeight': 480,
    'BackgroundColor': [34, 42, 80, 255],
    'BackgroundEndColor': [16, 17, 25, 255],
    'EndLayerImagePos': [160.0, 4579694.0],
    'EndLayerArea': [160.0, 4579884.0, 320.0, 200.0],
    'FinalHeight': 4579704.0,
    'FinalCloudClearance': 40.0,
    'FinalCameraPos': 4579894.0,
    'ButterflySizeMax': 1.0,
    'ButterflySizeMin': 1.0,
    'ButterflySpeedMax': 1.0,
    'ButterflySpeedMin': 1.0,
    'ButterflyEvery': 3000.0,
    'NumButterflies': 1,
    'CloudXSpeedMin': 0.009999999776482582,
    'CloudXSpeedMax': 2.0,
    'CloudsInvert': 0,
    'RandomFrames': 1,
    'PopFrames': 7,
    'CloudAtlasStartOffset': [427.0, 801.0],
    'CloudsBounce': 1,
    'RequiredForStar': [],
    'CloudSizeChangeStart': 14400.0,
    'CloudSizeChangeEnd': 86400.0,
    'CloudSpeedXChangeStart': 0.0,
    'CloudSpeedXChangeEnd': 115200.0,
    'ButterflySpeedChangeStart': 115200.0,
    'ButterflySizeChangeStart': 480.0,
    'ButterflySizeChangeEnd': 115200.0,
    'BackgroundChangeEnd': 43200.0,
  }),
];

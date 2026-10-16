import 'package:flutter_test/flutter_test.dart';
import 'package:kitten_jump/game/game_model.dart';

GameModel isolatedGame({int level = 7}) {
  final game = GameModel(seed: 7)..start(levelNumber: level);
  game.clouds.clear();
  game.butterflies.clear();
  return game;
}

void main() {
  test(
    'paid build recovers eight named levels and Christmas atlas offsets',
    () {
      expect(GameModel.levels.map((l) => l.name), [
        'First Jumps',
        'Falling Leaves',
        'Up to the Skies',
        'Star Wars',
        'Speed of Light',
        'Endless mode',
        'Classic mode',
        'Christmas Surprise',
      ]);
      final christmas = GameModel.levels[7];
      expect(christmas.cloudsAtlas, 'winter_level_atlas.png');
      expect(christmas.cloudAtlasStartOffset, [427, 801]);
      expect(christmas.cloudWidth, 55);
      expect(christmas.cloudAreaWidth, 45);
      expect(christmas.popFrames, 7);
      expect(christmas.endless, isTrue);
      expect(GameModel.tickSeconds, .02);
    },
  );

  test('quick reset places six gifts without a synchronous physics tick', () {
    final game = GameModel(seed: 42)..start();
    expect(game.phase, GamePhase.playing);
    expect(game.playerX, 160);
    expect(game.playerY, 1);
    expect(game.ticks, 0);
    expect(game.clouds.length, 6);
    expect(game.clouds.first.y, closeTo(181.6666717529297, 1e-6));
    expect(game.clouds.last.y, 640);
    expect(game.butterflies.single.y, 3240);
    expect(game.butterflies.single.flies, isTrue);
    game.playerX = 270;
    game.reset();
    expect(
      game.playerX,
      160,
      reason: 'new DynamicsLayer resets kitten position',
    );
    expect(game.score, 0);
    expect(game.butterflyCount, 0);
  });

  test('first level excludes the extra spacing used by drifting clouds', () {
    final game = GameModel()..start(levelNumber: 0);
    expect(game.clouds.map((c) => c.y), [154, 290, 426, 562, 698, 834]);
    expect(game.currentLevel.requiredForStar, [6, 9, 11]);
  });

  test('Christmas jump subtracts recovered gravity before advancing Y', () {
    final game = isolatedGame()..jump();
    game.tick();
    expect(game.velocityY, 11.860000610351562);
    expect(game.playerY, 12.860000610351562);
    expect(game.jumpGeneration, 1);
    expect(game.score, 0);
  });

  test('a missed first jump returns to the ground and permits another try', () {
    final game = isolatedGame()..jump();
    for (var i = 0; i < 70; i++) {
      game.tick();
    }
    expect(game.playerY, 1);
    expect(game.jumping, isFalse);
    expect(game.phase, GamePhase.playing);
    game.jump();
    expect(game.jumping, isTrue);
  });

  test('returning to the ground after first collection ends the run', () {
    final game = isolatedGame()..gotFirstOne = true;
    game.jump();
    game.playerY = -100;
    game.velocityY = -5;
    game.tick();
    expect(game.phase, GamePhase.gameOver);
    expect(game.won, isFalse);
  });

  test(
    'horizontal target eases by one tenth and airborne tilt is filtered',
    () {
      final game = isolatedGame();
      game.setTarget(320);
      game.tick();
      expect(game.playerX, 176);
      expect(game.animation, KittenAnimation.run);
      game.applyTilt(-1);
      expect(game.targetX, 320, reason: 'tilt is disabled while grounded');
      game.jump();
      game.applyTilt(-1);
      expect(game.targetX, 64);
      game.applyTilt(double.nan);
      expect(game.targetX, 64);
      game.applyTilt(-100);
      expect(game.targetX, 0);
    },
  );

  test('Christmas cloud can bounce a rising kitten and scores one point', () {
    final game = isolatedGame()
      ..playerY = 200
      ..velocityY = 5
      ..jumping = true;
    final cloud = Cloud(x: 160, y: 200, size: .8);
    game.clouds.add(cloud);
    game.tick();
    expect(game.score, 1);
    expect(game.velocityY, game.currentLevel.jumpSpeed);
    expect(game.gotFirstOne, isTrue);
    expect(cloud.popped, 1);
    expect(game.drainSounds(), [GameSound.cloud]);
    game.tick();
    expect(game.score, 1, reason: 'popped gift cannot score again');
  });

  test(
    'brick collision requires a descending crossing of the platform top',
    () {
      final game = isolatedGame(level: 0)
        ..playerY = 200
        ..velocityY = -5
        ..jumping = true;
      game.clouds.add(Cloud(x: 160, y: 185));
      game.tick();
      expect(game.velocityY, game.currentLevel.jumpSpeed);
      expect(
        game.score,
        0,
        reason: 'finite brick level has no per-cloud score',
      );
      final rising = isolatedGame(level: 0)
        ..playerY = 198
        ..velocityY = 5
        ..jumping = true;
      rising.clouds.add(Cloud(x: 160, y: 185));
      rising.tick();
      expect(rising.gotFirstOne, isFalse);
      expect(rising.drainSounds(), isEmpty);
    },
  );

  test('space platform direction does not exclude a bounce', () {
    final game = isolatedGame(level: 3)
      ..playerY = 200
      ..velocityY = 5
      ..jumping = true;
    game.clouds.add(Cloud(x: 160, y: 200, inverted: true));
    game.tick();
    expect(game.score, 10);
    expect(game.gotFirstOne, isTrue);
  });

  test('clouds score before Christmas collectible doubles the total', () {
    final game = isolatedGame()
      ..score = 3
      ..playerY = 200
      ..velocityY = 5
      ..jumping = true;
    game.clouds.add(Cloud(x: 160, y: 200, size: .8));
    game.butterflies.add(Butterfly(x: 160, y: 214));
    game.tick();
    expect(game.score, 8);
    expect(game.butterflyCount, 1);
    expect(game.butterflyCombo, 0);
    expect(game.drainSounds(), [GameSound.cloud, GameSound.butterfly]);
    expect(game.butterflies.single.y, greaterThan(3100));
  });

  test('nonclassic butterflies award successive two hundred point bonuses', () {
    final game = isolatedGame(level: 2)
      ..playerY = 200
      ..velocityY = 0
      ..jumping = true;
    game.butterflies.add(Butterfly(x: 160, y: 214, speed: 0));
    game.tick();
    expect(game.score, 200);
    game.butterflies.single
      ..x = game.playerX
      ..y = game.playerY + 10
      ..flies = true
      ..speed = 0;
    game.tick();
    expect(game.score, 600);
    expect(game.butterflyCount, 2);
  });

  test(
    'camera follows world height while entity coordinates stay in world',
    () {
      final game = isolatedGame()
        ..playerY = 500
        ..jumping = true
        ..velocityY = 0;
      game.tick();
      expect(game.cameraY, 30);
      expect(game.playerY, closeTo(499.56, .001));
      expect(game.cameraDelta, 30);
    },
  );

  test(
    'finite ending lands after passing the final height and awards stars',
    () {
      final game = isolatedGame(level: 0)
        ..butterflyCount = 9
        ..playerY = 13743
        ..velocityY = 1
        ..jumping = true;
      game.tick();
      expect(game.reached, isTrue);
      expect(game.won, isFalse);
      game.playerY = game.currentLevel.finalHeight + 1;
      game.velocityY = -2;
      game.tick();
      expect(game.won, isTrue);
      expect(game.phase, GamePhase.gameOver);
      expect(game.playerY, game.currentLevel.finalHeight);
      expect(game.earnedStars, 2);
    },
  );

  test('inactive phases freeze dynamics and ignore input', () {
    final game = isolatedGame()..showMenu();
    game.jump();
    game.setTarget(20);
    game.applyTilt(1);
    game.tick();
    expect(game.ticks, 0);
    expect(game.playerY, 1);
    expect(game.targetX, 160);
    expect(game.jumping, isFalse);
    game.showScores();
    game.tick();
    expect(game.ticks, 0);
  });

  test('level selection bounds are checked and reset clears progression', () {
    final game = GameModel()..selectLevel(2);
    expect(game.phase, GamePhase.menu);
    expect(game.currentLevel.name, 'Up to the Skies');
    expect(() => game.selectLevel(8), throwsRangeError);
    game.start();
    expect(game.phase, GamePhase.playing);
    game.butterflyCount = 8;
    game.reset(levelNumber: 7);
    expect(game.butterflyCount, 0);
    expect(game.progress, lessThan(.00001));
  });
}

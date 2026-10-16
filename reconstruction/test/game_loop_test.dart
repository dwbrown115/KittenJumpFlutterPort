import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitten_jump/game/game_model.dart';
import 'package:kitten_jump/game/kitten_jump_game.dart';

KittenJumpGame newGame({int seed = 77, void Function()? onStateChanged}) =>
    KittenJumpGame(
      model: GameModel(seed: seed),
      onStateChanged: onStateChanged ?? () {},
    );

Map<String, Object> snapshot(GameModel model) => {
  'phase': model.phase,
  'ticks': model.ticks,
  'score': model.score,
  'height': model.totalHeight,
  'camera': model.cameraY,
  'player': [
    model.playerX,
    model.playerY,
    model.velocityY,
    model.targetX,
    model.jumping,
    model.sitting,
    model.facingLeft,
    model.freeFall,
    model.animation,
    model.jumpGeneration,
  ],
  'clouds': [
    for (final c in model.clouds)
      [c.x, c.y, c.size, c.popped, c.movingRight, c.frame, c.visible],
  ],
  'butterflies': [
    for (final b in model.butterflies)
      [b.x, b.y, b.size, b.frame, b.color, b.visible],
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = newGame();
    await loader.onLoad();
    expect(loader.assetsReady, isTrue);
  });

  test('50 Hz trajectories agree at 30, 60 and 120 display updates', () async {
    final traces = <int, List<Map<String, Object>>>{};
    for (final fps in [30, 60, 120]) {
      final game = newGame();
      await game.onLoad();
      game.startGame();
      game.jump();
      final samples = <Map<String, Object>>[];
      for (var frame = 0; frame < fps * 3; frame++) {
        if (frame == 0) game.setPointer(250);
        if (frame == fps) game.setPointer(60);
        if (frame == fps * 2) game.setPointer(180);
        game.update(1 / fps);
        if ((frame + 1) % fps == 0) samples.add(snapshot(game.model));
      }
      traces[fps] = samples;
    }
    expect(traces[30], isNotEmpty);
    expect(traces[60], traces[30]);
    expect(traces[120], traces[30]);
  });

  test('a long resume interval advances at most eight ticks', () async {
    final game = newGame();
    await game.onLoad();
    game.startGame();
    final ticksBeforeResume = game.model.ticks;
    game.update(60);
    final resumedTicks = game.model.ticks - ticksBeforeResume;
    expect(resumedTicks, inInclusiveRange(1, 8));
    game.update(GameModel.tickSeconds);
    expect(game.model.ticks - ticksBeforeResume, resumedTicks + 1);
  });

  test('pause freezes physics and clears partial elapsed time', () async {
    final game = newGame();
    await game.onLoad();
    game.startGame();
    game.update(GameModel.tickSeconds / 2);
    game.pauseGame(true);
    final pausedSnapshot = snapshot(game.model);
    for (var frame = 0; frame < 120; frame++) {
      game.update(1 / 60);
    }
    game.jump();
    game.setPointer(0);
    expect(snapshot(game.model), pausedSnapshot);
    game.pauseGame(false);
    game.update(GameModel.tickSeconds / 2);
    expect(snapshot(game.model), pausedSnapshot);
    game.update(GameModel.tickSeconds / 2);
    expect(game.model.ticks, (pausedSnapshot['ticks']! as int) + 1);
  });

  test('unloaded and inactive scenes cannot advance simulation', () async {
    final game = newGame();
    game.model.start();
    final beforeLoad = snapshot(game.model);
    game.update(1);
    expect(snapshot(game.model), beforeLoad);
    await game.onLoad();
    game.model.showMenu();
    final menu = snapshot(game.model);
    game.update(1);
    expect(snapshot(game.model), menu);
    game.model.phase = GamePhase.gameOver;
    final over = snapshot(game.model);
    game.update(1);
    expect(snapshot(game.model), over);
  });

  test('invalid timing samples are ignored', () async {
    final game = newGame();
    await game.onLoad();
    game.startGame();
    final before = snapshot(game.model);
    for (final dt in [0.0, -1.0, double.nan, double.infinity]) {
      game.update(dt);
    }
    expect(snapshot(game.model), before);
  });

  test('every recovered platform frame fits its shipped atlas', () async {
    final game = newGame();
    await game.onLoad();
    for (final level in GameModel.levels) {
      final image = game.images.fromCache(level.cloudsAtlas);
      final offset = level.cloudAtlasStartOffset;
      for (
        var frame = 0;
        frame < level.integer('CloudsAtlasCapacity');
        frame++
      ) {
        final rect = atlasCellRect(
          frame,
          width: level.cloudWidth,
          height: level.cloudHeight,
          columns: (level.cloudsAtlasWidth / level.cloudWidth).floor(),
          offsetX: offset[0],
          offsetY: offset[1],
        );
        expect(rect.left, greaterThanOrEqualTo(0), reason: level.name);
        expect(rect.top, greaterThanOrEqualTo(0), reason: level.name);
        expect(rect.right, lessThanOrEqualTo(image.width), reason: level.name);
        expect(
          rect.bottom,
          lessThanOrEqualTo(image.height),
          reason: level.name,
        );
      }
    }
    for (final name in [
      'red_kitten.png',
      'grey_kitten.png',
      'siam_kitten.png',
      'winter_level_atlas.png',
    ]) {
      final image = game.images.fromCache(name);
      for (var frame = 0; frame < 125; frame++) {
        final rect = atlasCellRect(frame, width: 85, height: 80, columns: 12);
        expect(rect.right, lessThanOrEqualTo(image.width), reason: name);
        expect(rect.bottom, lessThanOrEqualTo(image.height), reason: name);
      }
    }
  });

  test('all eight scenes and original bitmap labels render', () async {
    final game = newGame();
    await game.onLoad();
    game.onGameResize(Vector2(320, 480));
    for (var level = 0; level < GameModel.levels.length; level++) {
      game.model.selectLevel(level);
      game.startGame();
      for (var tick = 0; tick < 50; tick++) {
        game.update(GameModel.tickSeconds);
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      game.render(canvas);
      game.drawOriginalText(
        canvas,
        'Score: 123',
        const ui.Offset(10, 50),
        font: 'small_font',
        scale: 0.5,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 480);
      final pixels = await image.toByteData();
      expect(pixels, isNotNull);
      expect(pixels!.lengthInBytes, 320 * 480 * 4);
      if (const bool.fromEnvironment('RENDER_PREVIEWS')) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('docs/render-previews/level-$level.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(png!.buffer.asUint8List());
      }
      image.dispose();
      picture.dispose();
    }
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets().where(
        (path) => path.startsWith('assets/images/') && path.endsWith('.png'),
      ),
      hasLength(85),
    );
  });
}

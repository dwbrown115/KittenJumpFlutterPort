import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitten_jump/game/game_model.dart';
import 'package:kitten_jump/main.dart';
import 'package:kitten_jump/services/game_store.dart';
import 'package:kitten_jump/ui/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native Christmas reconstruction: eight modes, appearance, controls, audio and local scores',
    (tester) async {
      // Keep QA names and unlocks out of the installed release's preferences.
      SharedPreferences.setMockInitialValues({
        'kittenJumpChristmas.soundOn': false,
        'kittenJumpChristmas.musicOn': false,
      });
      final store = await GameStore.open();
      for (var level = 0; level < 5; level++) {
        await store.saveScore(
          'QA Unlock',
          0,
          levelNumber: level,
          won: true,
          stars: 3,
          percentage: 1,
        );
      }
      await tester.pumpWidget(KittenJumpApp(store: store));
      final state = tester.state<GameScreenState>(find.byType(GameScreen));
      await state.game.toBeLoaded();
      await tester.pump(const Duration(milliseconds: 300));
      final isAndroid = defaultTargetPlatform == TargetPlatform.android;
      if (isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      }
      Future<void> screenshot(String name) async {
        if (!isAndroid) return;
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await binding.takeScreenshot('android-$name');
      }

      Future<void> tap(String key) async {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump(const Duration(milliseconds: 150));
      }

      Future<void> waitForAudio(PlayerState expected) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (FlameAudio.bgm.audioPlayer.state != expected &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          expect(
            find.text('Sound is unavailable. You can keep playing.'),
            findsNothing,
            reason:
                'Native audio reported an initialization or playback error.',
          );
        }
        expect(
          find.text('Sound is unavailable. You can keep playing.'),
          findsNothing,
          reason: 'Native audio reported a playback error.',
        );
        expect(
          FlameAudio.bgm.audioPlayer.state,
          expected,
          reason:
              'Native audio did not reach $expected within 15 real seconds.',
        );
      }

      Future<void> backFromPlaying() async {
        await tap('pause');
        await tap('pause_menu');
        expect(state.model.phase, GamePhase.menu);
      }

      expect(find.byKey(const Key('christmas')), findsOneWidget);
      await screenshot('menu');
      await tap('settings');
      await screenshot('settings');
      for (final (index, skin) in [
        'grey_kitten.png',
        'red_kitten.png',
        'siam_kitten.png',
      ].indexed) {
        await tap('skin_$index');
        expect(store.kittenSkin, skin);
      }
      await tap('skin_1');
      if (isAndroid) {
        await tap('tilt');
        expect(store.tiltOn, true);
      } else {
        await tap('tilt');
        expect(
          find.textContaining('Tilt is available on Android'),
          findsOneWidget,
        );
      }
      await tap('finger');
      expect(store.tiltOn, false);
      await tap('sound');
      expect(store.soundOn, true);
      await tap('music');
      await tester.pump(const Duration(seconds: 1));
      expect(store.musicOn, true);
      await waitForAudio(PlayerState.playing);
      await tap('settings_menu');
      await tap('help');
      await screenshot('help');
      await tap('help_back');

      for (var level = 0; level < 6; level++) {
        await tap('start');
        if (level == 0) await screenshot('level-picker');
        await tap('level_$level');
        expect(state.model.phase, GamePhase.playing);
        expect(state.model.currentLevel.id, level);
        await waitForAudio(PlayerState.playing);
        await screenshot('level-$level');
        await backFromPlaying();
      }
      await tap('classic');
      expect(state.model.currentLevel.id, 6);
      await screenshot('level-6-classic');
      await backFromPlaying();
      await tap('christmas');
      expect(state.model.currentLevel.id, 7);
      await waitForAudio(PlayerState.playing);
      await screenshot('level-7-christmas');

      await tap('playfield');
      expect(state.model.jumping, true);
      await screenshot('jump');
      await tap('pause');
      final frozen = state.model.playerY;
      final frozenTicks = state.model.ticks;
      await tester.pump(const Duration(milliseconds: 250));
      expect(state.model.playerY, frozen);
      expect(state.model.ticks, frozenTicks);
      await waitForAudio(PlayerState.paused);
      await screenshot('pause');
      await tap('resume');
      expect(state.game.paused, false);
      await waitForAudio(PlayerState.playing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      expect(state.model.targetX, 320);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

      // Force the recovered loss boundary instead of waiting for a random run.
      state.game.jump();
      state.model
        ..gotFirstOne = true
        ..score = 7
        ..playerY = -100
        ..velocityY = -5;
      state.game.update(GameModel.tickSeconds);
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.model.phase, GamePhase.gameOver);
      expect(state.model.won, false);
      await screenshot('score-entry');
      await tester.enterText(find.byKey(const Key('player_name')), 'QA Player');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.model.phase, GamePhase.scores);
      expect(store.topTenForLevel(7).single.name, 'QA Player');
      expect(store.topTenForLevel(7).single.score, 7);
      expect(store.topTenForLevel(6), isEmpty);
      await screenshot('scores');
      await tap('scores_replay');
      expect(state.model.phase, GamePhase.playing);
      expect(state.model.currentLevel.id, 7);
      expect(state.model.score, 0);
      await backFromPlaying();
      await tap('scores');
      await tap('scores_menu');
      await tap('settings');
      await tap('music');
      expect(store.musicOn, false);
      await waitForAudio(PlayerState.stopped);
      await tap('sound');
      expect(store.soundOn, false);
      await tap('settings_menu');
      expect(state.model.phase, GamePhase.menu);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    },
  );
}

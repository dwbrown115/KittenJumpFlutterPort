import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kitten_jump/main.dart';
import 'package:kitten_jump/game/game_model.dart';
import 'package:kitten_jump/services/game_store.dart';
import 'package:kitten_jump/ui/game_screen.dart';

Future<GameScreenState> launch(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'kittenJumpChristmas.soundOn': false,
    'kittenJumpChristmas.musicOn': false,
  });
  final store = await GameStore.open();
  late GameScreenState state;
  await tester.runAsync(() async {
    await tester.pumpWidget(KittenJumpApp(store: store));
    state = tester.state<GameScreenState>(find.byType(GameScreen));
    await state.game.toBeLoaded();
  });
  await tester.pump();
  expect(state.game.loadError, isNull);
  expect(state.game.assetsReady, isTrue);
  return state;
}

void forceLoss(GameScreenState state, {int score = 7}) {
  state.game.jump();
  state.model
    ..gotFirstOne = true
    ..score = score
    ..playerY = -100
    ..velocityY = -5;
  state.game.update(GameModel.tickSeconds);
}

void main() {
  testWidgets(
    'score-entry controls retain touch size above a keyboard at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = await launch(tester);
      await tester.tap(find.byKey(const Key('christmas')));
      await tester.pump();
      forceLoss(state, score: 3);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('save')),
        80,
        scrollable: find
            .ancestor(
              of: find.byKey(const Key('save')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester.getRect(find.byKey(const Key('save'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Christmas art loads; pointer jump, pause and keyboard steering work',
    (tester) async {
      final state = await launch(tester);
      expect(find.byKey(const Key('christmas')), findsOneWidget);
      await tester.tap(find.byKey(const Key('christmas')));
      await tester.pump();
      expect(state.model.phase, GamePhase.playing);
      expect(state.model.currentLevel.id, 7);
      await tester.tap(find.byKey(const Key('playfield')));
      await tester.pump(const Duration(milliseconds: 35));
      expect(state.model.jumping, isTrue);
      await tester.tap(find.byKey(const Key('pause')));
      await tester.pump();
      final frozen = state.model.playerY;
      await tester.pump(const Duration(seconds: 1));
      expect(state.model.playerY, frozen);
      await tester.tap(find.byKey(const Key('resume')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.model.targetX, 320);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(state.model.targetX, state.model.playerX);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'campaign picker starts First Jumps and direct Classic starts its own level',
    (tester) async {
      final state = await launch(tester);
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      expect(find.byKey(const Key('level_0')), findsOneWidget);
      expect(find.textContaining('First Jumps'), findsWidgets);
      await tester.tap(find.byKey(const Key('level_0')));
      await tester.pump();
      expect(state.model.currentLevel.id, 0);
      expect(state.model.phase, GamePhase.playing);
      await tester.tap(find.byKey(const Key('pause')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pause_menu')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('classic')));
      await tester.pump();
      expect(state.model.currentLevel.id, 6);
      expect(state.model.phase, GamePhase.playing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'game-over score saves once for Christmas; score selector replays its selected mode',
    (tester) async {
      final state = await launch(tester);
      await tester.tap(find.byKey(const Key('christmas')));
      await tester.pump();
      forceLoss(state);
      await tester.pump();
      expect(state.model.phase, GamePhase.gameOver);
      await tester.enterText(find.byKey(const Key('player_name')), 'Dakota');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.model.phase, GamePhase.scores);
      expect(find.text('Dakota'), findsOneWidget);
      final reloaded = await GameStore.open();
      expect(reloaded.scores.length, 1);
      expect(reloaded.topTenForLevel(7).single.score, 7);
      expect(reloaded.topTenForLevel(6), isEmpty);
      await tester.tap(find.byKey(const Key('scores_level')));
      await tester.pump();
      await tester.tap(find.text('Classic mode').last);
      await tester.pump();
      expect(find.text('Dakota'), findsNothing);
      expect(find.textContaining('No scores yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scores_replay')));
      await tester.pump();
      expect(state.model.phase, GamePhase.playing);
      expect(state.model.currentLevel.id, 6);
      expect(state.model.score, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'kitten appearance and control choice persist; help returns to the original menu',
    (tester) async {
      final state = await launch(tester);
      await tester.tap(find.byKey(const Key('settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('skin_0')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.widget.store.kittenSkin, 'grey_kitten.png');
      expect((await GameStore.open()).kittenSkin, 'grey_kitten.png');
      await tester.tap(find.byKey(const Key('finger')));
      await tester.pump();
      expect(state.widget.store.tiltOn, false);
      await tester.tap(find.byKey(const Key('settings_menu')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('help')));
      await tester.pump();
      expect(find.byKey(const Key('help_back')), findsOneWidget);
      await tester.tap(find.byKey(const Key('help_back')));
      await tester.pump();
      expect(find.byKey(const Key('christmas')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small portrait and wide desktop layouts show empty scores without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await launch(tester);
      await tester.tap(find.byKey(const Key('scores')));
      await tester.pump();
      expect(find.textContaining('No scores yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scores_menu')));
      await tester.pump();
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      expect(find.byKey(const Key('start')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings')));
      await tester.pump();
      expect(find.byKey(const Key('music')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

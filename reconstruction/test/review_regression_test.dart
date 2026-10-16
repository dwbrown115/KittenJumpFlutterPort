import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitten_jump/game/game_model.dart';
import 'package:kitten_jump/services/game_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The failure seam belongs to shared_preferences' platform interface.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'app_flow_test.dart' show launch, forceLoss;

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences()
    : super.withData({
        'flutter.kittenJumpChristmas.soundOn': false,
        'flutter.kittenJumpChristmas.musicOn': false,
      });

  static const scoreKey = 'flutter.kittenJumpChristmas.highScores';
  bool failScoreWrite = false;
  bool throwNameWrite = false;
  Completer<void>? releaseScoreWrite;
  bool scoreWriteStarted = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == scoreKey) {
      scoreWriteStarted = true;
      await releaseScoreWrite?.future;
      if (failScoreWrite) return false;
    }
    if (throwNameWrite && key == 'flutter.kittenJumpChristmas.playerName') {
      throw StateError('Player-name preference could not be written.');
    }
    return super.setValue(valueType, key, value);
  }

  Future<List<dynamic>> persistedScores() async {
    final values = await getAll();
    return jsonDecode(values[scoreKey] as String) as List<dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('typing settings name cannot trigger gameplay shortcuts', (
    tester,
  ) async {
    final state = await launch(tester);
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('settings_name')), 'Dakota');
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyP,
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.escape,
    ]) {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
      expect(state.model.phase, GamePhase.menu);
      expect(find.byKey(const Key('settings_name')), findsOneWidget);
    }
    expect((await GameStore.open()).playerName, 'Dakota');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the entire original top strip pauses instead of jumping', (
    tester,
  ) async {
    final state = await launch(tester);
    await tester.tap(find.byKey(const Key('christmas')));
    await tester.pump();
    final field = tester.getRect(find.byKey(const Key('playfield')));
    for (final fraction in [0.1, 0.5, 0.9]) {
      await tester.tapAt(
        Offset(
          field.left + field.width * fraction,
          field.top + field.height * 30 / 480,
        ),
      );
      await tester.pump();
      expect(state.game.paused, true);
      expect(state.model.jumping, false);
      await tester.tap(find.byKey(const Key('resume')));
      await tester.pump();
      expect(state.game.paused, false);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('holding the pause key cannot resume the frozen game', (
    tester,
  ) async {
    final state = await launch(tester);
    await tester.tap(find.byKey(const Key('christmas')));
    await tester.pump();
    state.game.jump();
    state.game.update(GameModel.tickSeconds);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    final frozenY = state.model.playerY;
    final frozenTicks = state.model.ticks;
    expect(state.game.paused, isTrue);

    for (var repeat = 0; repeat < 3; repeat++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyP);
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.game.paused, isTrue);
      expect(state.model.playerY, frozenY);
      expect(state.model.ticks, frozenTicks);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(state.game.paused, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a completed save cannot replace a game started during the write',
    (tester) async {
      final state = await launch(tester);
      final preferences = _ControlledPreferences()
        ..releaseScoreWrite = Completer<void>();
      SharedPreferencesStorePlatform.instance = preferences;
      state.game.startGame();
      forceLoss(state);
      await tester.pump();
      expect(state.model.phase, GamePhase.gameOver);

      await tester.enterText(find.byKey(const Key('player_name')), 'Dakota');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pump();
      expect(preferences.scoreWriteStarted, isTrue);
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('save'))).onPressed,
        isNull,
      );
      expect(state.widget.store.scores, isEmpty);

      await tester.tap(find.byKey(const Key('replay')));
      await tester.pump();
      expect(state.model.phase, GamePhase.playing);
      expect(state.model.score, 0);
      preferences.releaseScoreWrite!.complete();
      await tester.pump(const Duration(milliseconds: 100));

      expect(state.model.phase, GamePhase.playing);
      expect(state.model.score, 0);
      expect(state.widget.store.scores.single.score, 7);
      expect(state.widget.store.scores.single.name, 'Dakota');
      expect(state.widget.store.topTenForLevel(7).single.score, 7);
      expect((await preferences.persistedScores()).single['score'], 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'a failed score write leaves memory unchanged and retry saves once',
    () async {
      SharedPreferences.resetStatic();
      final preferences = _ControlledPreferences();
      SharedPreferencesStorePlatform.instance = preferences;
      final store = await GameStore.open();
      await store.saveScore('First', 3);

      preferences.failScoreWrite = true;
      await expectLater(store.saveScore('Dakota', 7), throwsStateError);
      expect(store.scores.map((score) => score.score), [3]);
      expect(store.playerName, 'First');
      expect((await preferences.persistedScores()).length, 1);

      preferences.failScoreWrite = false;
      await store.saveScore('Dakota', 7);
      expect(store.scores.map((score) => score.score), [7, 3]);
      expect(store.scores.where((score) => score.name == 'Dakota').length, 1);
      expect((await preferences.persistedScores()).length, 2);
    },
  );

  test(
    'a player-name preference failure does not reject an already saved score',
    () async {
      SharedPreferences.resetStatic();
      final preferences = _ControlledPreferences()..throwNameWrite = true;
      SharedPreferencesStorePlatform.instance = preferences;
      final store = await GameStore.open();

      await expectLater(store.saveScore('Dakota', 7), completes);
      expect(store.scores.single.score, 7);
      expect(store.playerName, 'Dakota');
      expect((await preferences.persistedScores()).single['score'], 7);
    },
  );
}

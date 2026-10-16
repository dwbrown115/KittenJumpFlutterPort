import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kitten_jump/services/game_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Christmas preferences do not read or overwrite the older build',
    () async {
      final oldScores = jsonEncode([
        {
          'name': 'Older player',
          'score': 99,
          'date': '2026-10-08T12:00:00.000',
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'kittenJump.playerName': 'Older player',
        'kittenJump.soundOn': false,
        'kittenJump.tiltOn': true,
        'kittenJump.highScores': oldScores,
      });
      final store = await GameStore.open();
      expect(store.playerName, 'Kitteh');
      expect(store.soundOn, true);
      expect(store.tiltOn, false);
      expect(store.scores, isEmpty);
      await store.saveScore('Christmas player', 7, levelNumber: 7);
      await store.setSound(true);
      await store.setTilt(false);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('kittenJump.playerName'), 'Older player');
      expect(preferences.getString('kittenJump.highScores'), oldScores);
      expect(preferences.getBool('kittenJump.soundOn'), false);
      expect(preferences.getBool('kittenJump.tiltOn'), true);
      expect(
        preferences.getString('kittenJumpChristmas.playerName'),
        'Christmas player',
      );
      final reloaded = await GameStore.open();
      expect(reloaded.scores.single.name, 'Christmas player');
      expect(reloaded.scores.single.score, 7);
      expect(reloaded.soundOn, true);
      expect(reloaded.tiltOn, false);
    },
  );

  test(
    'per-level scores and progress survive reload without erasing history',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await GameStore.open();
      for (var i = 0; i < 12; i++) {
        await store.saveScore('Player $i', i, levelNumber: 7, butterflies: i);
      }
      await store.saveScore(
        'Campaign',
        40,
        levelNumber: 0,
        butterflies: 9,
        percentage: 1,
        won: true,
        stars: 2,
      );
      await store.saveScore('Classic', 4, levelNumber: 6);
      await store.setSound(false);
      await store.setMusic(false);
      await store.setTilt(true);
      final reloaded = await GameStore.open();
      expect(reloaded.scores.length, 14);
      expect(
        reloaded.topTenForLevel(7).map((score) => score.score),
        List.generate(10, (i) => 11 - i),
      );
      expect(reloaded.topTenForLevel(6).single.score, 4);
      final campaign = reloaded.topTenForLevel(0).single;
      expect(campaign.butterflies, 9);
      expect(campaign.percentage, 1);
      expect(campaign.won, true);
      expect(reloaded.starsForLevel(0), 2);
      expect(reloaded.isLevelUnlocked(1), true);
      expect(reloaded.isLevelUnlocked(2), false);
      expect(reloaded.soundOn, false);
      expect(reloaded.musicOn, false);
      expect(reloaded.tiltOn, true);
    },
  );

  test('unlock progress keeps the best completed result and direct modes stay available', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await GameStore.open();
    expect(store.isLevelUnlocked(0), true);
    for (final level in [5, 6, 7]) {
      expect(store.isLevelUnlocked(level), true);
    }
    await store.saveScore(
      'Three stars',
      100,
      levelNumber: 0,
      won: true,
      stars: 3,
      percentage: 1,
    );
    await store.saveScore(
      'Two stars',
      90,
      levelNumber: 0,
      won: true,
      stars: 2,
      percentage: 1,
    );
    expect(store.starsForLevel(0), 3);
    expect(store.isLevelUnlocked(1), true);
    await store.saveScore(
      'One star',
      30,
      levelNumber: 1,
      won: true,
      stars: 1,
      percentage: 1,
    );
    expect(store.isLevelUnlocked(2), true);
    expect(store.isLevelUnlocked(3), false);
    expect((await GameStore.open()).isLevelUnlocked(2), true);
  });

  test('malformed saved records do not block gameplay', () async {
    SharedPreferences.setMockInitialValues({
      'kittenJumpChristmas.highScores': 'not valid json',
    });
    final store = await GameStore.open();
    expect(store.scores, isEmpty);
    await store.saveScore('  ', 9);
    expect(store.scores.single.name, 'Kitteh');
    expect((await GameStore.open()).scores.single.score, 9);
  });
}

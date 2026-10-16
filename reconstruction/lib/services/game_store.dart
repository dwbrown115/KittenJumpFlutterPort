import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class HighScore {
  const HighScore({
    required this.name,
    required this.score,
    required this.date,
    this.levelNumber = 7,
    this.butterflies = 0,
    this.percentage = 0,
    this.won = false,
    this.stars = 0,
  });
  final String name;
  final int score;
  final DateTime date;
  final int levelNumber;
  final int butterflies;
  final double percentage;
  final bool won;
  final int stars;

  Map<String, Object> toJson() => {
    'name': name,
    'score': score,
    'date': date.toIso8601String(),
    'levelNumber': levelNumber,
    'butterflies': butterflies,
    'percentage': percentage,
    'won': won,
    'stars': stars,
  };

  static HighScore? parse(Object? value) {
    if (value is! Map || value['score'] is! int || value['name'] is! String) {
      return null;
    }
    final date = DateTime.tryParse(value['date'].toString());
    final level = value['levelNumber'];
    if (date == null || level is! int || level < 0 || level > 7) return null;
    final progress = value['percentage'];
    return HighScore(
      name: value['name'],
      score: value['score'],
      date: date,
      levelNumber: level,
      butterflies: value['butterflies'] is int ? value['butterflies'] : 0,
      percentage: progress is num && progress.isFinite
          ? progress.toDouble().clamp(0, 1)
          : 0,
      won: value['won'] == true,
      stars: value['stars'] is int ? (value['stars'] as int).clamp(0, 3) : 0,
    );
  }
}

class GameStore {
  GameStore._(this._preferences);
  static const namespace = 'kittenJumpChristmas';
  static const kittenSkins = [
    'grey_kitten.png',
    'red_kitten.png',
    'siam_kitten.png',
  ];
  final SharedPreferences _preferences;
  final List<HighScore> scores = [];
  String playerName = 'Kitteh';
  String kittenSkin = 'red_kitten.png';
  bool soundOn = true;
  bool musicOn = true;
  bool tiltOn = false;

  static Future<GameStore> open() async {
    final preferences = await SharedPreferences.getInstance();
    final store = GameStore._(preferences);
    store.playerName =
        preferences.getString('$namespace.playerName') ?? 'Kitteh';
    store.soundOn = preferences.getBool('$namespace.soundOn') ?? true;
    store.musicOn = preferences.getBool('$namespace.musicOn') ?? true;
    store.tiltOn = preferences.getBool('$namespace.tiltOn') ?? false;
    final skin = preferences.getString('$namespace.kittenSkin');
    if (kittenSkins.contains(skin)) store.kittenSkin = skin!;
    final raw = preferences.getString('$namespace.highScores');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          store.scores.addAll(
            decoded.map(HighScore.parse).whereType<HighScore>(),
          );
        }
      } on FormatException {
        // An interrupted preferences write must not prevent playing.
      }
    }
    store.scores.sort((a, b) => b.score.compareTo(a.score));
    return store;
  }

  List<HighScore> get topTen => scores.take(10).toList(growable: false);
  List<HighScore> topTenForLevel(int level) => scores
      .where((score) => score.levelNumber == level)
      .take(10)
      .toList(growable: false);

  int starsForLevel(int level) => scores
      .where((score) => score.levelNumber == level && score.won)
      .fold(0, (best, score) => math.max(best, score.stars));

  bool isLevelUnlocked(int level) {
    if (level == 0 || (level >= 5 && level <= 7)) return true;
    if (level < 0 || level > 7) return false;
    var stars = 0;
    for (var i = 0; i <= level; i++) {
      stars += starsForLevel(i);
    }
    return stars >= level * 2;
  }

  Future<void> saveScore(
    String name,
    int score, {
    int levelNumber = 7,
    int butterflies = 0,
    double percentage = 0,
    bool won = false,
    int stars = 0,
  }) async {
    if (levelNumber < 0 || levelNumber > 7 || !percentage.isFinite) {
      throw ArgumentError('Invalid level score.');
    }
    final cleanName = name.trim();
    final nextName = cleanName.isEmpty ? 'Kitteh' : cleanName;
    final nextScores = [
      ...scores,
      HighScore(
        name: nextName,
        score: score,
        date: DateTime.now(),
        levelNumber: levelNumber,
        butterflies: butterflies,
        percentage: percentage.clamp(0, 1),
        won: won,
        stars: stars.clamp(0, 3),
      ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    final saved = await _preferences.setString(
      '$namespace.highScores',
      jsonEncode(nextScores.map((score) => score.toJson()).toList()),
    );
    if (!saved) throw StateError('Could not save score.');
    scores
      ..clear()
      ..addAll(nextScores);
    playerName = nextName;
    try {
      await _preferences.setString('$namespace.playerName', nextName);
    } catch (_) {
      // The score is durable; retrying an optional name would duplicate it.
    }
  }

  Future<void> setPlayerName(String value) async {
    final clean = value.trim();
    playerName = clean.isEmpty ? 'Kitteh' : clean;
    await _preferences.setString('$namespace.playerName', playerName);
  }

  Future<void> setSkin(String value) async {
    if (!kittenSkins.contains(value)) throw ArgumentError('Unknown kitten.');
    kittenSkin = value;
    await _preferences.setString('$namespace.kittenSkin', value);
  }

  Future<void> setSound(bool value) async {
    soundOn = value;
    await _preferences.setBool('$namespace.soundOn', value);
  }

  Future<void> setMusic(bool value) async {
    musicOn = value;
    await _preferences.setBool('$namespace.musicOn', value);
  }

  Future<void> setTilt(bool value) async {
    tiltOn = value;
    await _preferences.setBool('$namespace.tiltOn', value);
  }
}

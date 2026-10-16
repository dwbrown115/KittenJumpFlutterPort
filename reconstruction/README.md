# Kitten Jump Christmas reconstruction

Unofficial fan reconstruction, made for the love of the game. We do not own or claim ownership of the original game or its source code and resources. The new reconstruction code is open source under the [MIT license](../LICENSE), within the limits in [LICENSE_SCOPE.md](../LICENSE_SCOPE.md). See the [project README](../README.md) for ownership, archival provenance and repository exclusions.

Original game resources and original-art launcher icons are kept locally and excluded from Git. A fresh checkout needs the asset-restoration steps in the project README before building.

A playable Flutter + Flame reconstruction of the recovered original **paid Kitten Jump 2.1.1 — Christmas Surprise**. It includes all eight modes, the original artwork/audio, three kitten choices, and reconstructed level-specific mechanics.

## Play

- macOS: open `artifacts/Kitten Jump Christmas.app`.
- Android: install `artifacts/KittenJump-Christmas-Android.apk`. It is signed for local testing with the development signing key.
- On the original menu, the Christmas tree starts **Christmas Surprise**; **Play Classic** starts Classic mode. **Play** opens the six-level picker.
- Tap/click or press **Space** for the first jump. Drag, use **Left/Right** or **A/D**, or select Android tilt in Settings to steer.
- **Esc/P** pauses. Missing the first platform lets you retry; falling after your first platform or collectible ends the run.
- Save a result to record its score, collected butterflies/gifts and completion. Story levels award up to three stars, which unlock subsequent levels.
- Settings separates music and sound effects. The grey, orange and Siamese kitten choices apply to the first six modes; Classic and Christmas retain their own original kitten art.

## Coexists with the older build

This is a separate application, with no migration or import of the 1.3 reconstruction's saved data.

| Identity | Christmas 2.1.1 | Older 1.3 |
| --- | --- | --- |
| Android application ID | `com.silvercastledigital.kitten_jump_christmas` | `com.silvercastledigital.kitten_jump` |
| macOS bundle ID | `com.silvercastledigital.kittenJumpChristmas` | `com.silvercastledigital.kittenJump` |
| Preferences namespace | `kittenJumpChristmas` | `kittenJump` |
| App name | Kitten Jump Christmas | Kitten Jump |

These IDs are assigned to the reconstructed packages. The preserved historical IPA still contains its original `com.marksergienko.KittenApp` identifier.

## Develop and verify

```sh
flutter pub get
flutter run -d macos
flutter run -d <android-device-id>
flutter analyze
flutter test
python3 -m unittest discover -s tool -p 'test_convert_assets.py' -v
```

Native smoke tests use temporary mocked preferences, actual platform audio, every level and both control methods. They do not write QA names or unlocks into the normal application's saved data.

```sh
flutter drive --driver=test_driver/platform_driver.dart --target=integration_test/platform_smoke_test.dart -d macos
flutter drive --driver=test_driver/platform_driver.dart --target=integration_test/platform_smoke_test.dart -d <android-device-id>
flutter build apk --release --target=lib/main.dart
flutter build macos --release --target=lib/main.dart
```

The checked lockfile uses Flutter 3.47.2 / Dart 3.13.2 with Flame 1.38.2. Android and macOS are configured. Optimized APKs include ARM64, ARMv7 and x86_64 libraries; the Mac bundle includes Apple silicon and Intel architectures. Native verification here uses an ARM64 emulator and Apple silicon Mac. The Mac bundle uses local ad hoc signing; these are local testing artifacts.

## Evidence and fidelity

The source IPA and unchanged extracted files remain in the parent folder. `assets/manifest.json` records all conversions: 85 PNGs, 34 PCM WAVs and three original BMFont files. Native ImageIO and an independent audio decoder verify the converted assets. Conversion tools are under `tool/`.

`../analysis/` contains artifact identity, prior REA package evidence, the initial REA native dossier, original assembly, Objective-C metadata, and supplemental Ghidra analysis. The initial decompiler incorrectly classified Objective-C dispatch as terminal; its limited result is preserved. A saved script restores returning call flow in temporary analysis databases. It does not modify or execute the original app. The complete supplemental output is identified separately from canonical REA evidence.

`docs/gameplay-port.txt`, `docs/rendering-port.txt` and `docs/asset-conversion.txt` document reconstructed rules and limits. `docs/verification.txt` records completed package and runtime checks.

Physics runs at the recovered 50 Hz cadence and uses the eight original level configurations. The original executable has not been run as a comparison oracle, so exact historical frame pacing, RNG sequence and numerical parity remain unverified. Physical Android tilt feel still needs checking on a phone. Particle bursts, fireworks and some original menu/end-screen choreography remain unreconstructed; the modern score/settings panels and manual Save result flow are deliberate adaptations.

Original game and resources: Mark Sergienko's Kitten Jump. This project is based solely on the recovered 2.1.1 artifact and the earlier Flutter reconstruction scaffold; the ongoing remake was not modified.

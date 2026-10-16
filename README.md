# Kitten Jump Christmas 2.1.1 fan reconstruction

This is an unofficial fan reconstruction of Kitten Jump 2.1.1, built with Flutter and Flame for Android and macOS. It was made for the love of the game and an interest in preserving its gameplay.

The original game is credited to Mark Sergienko in the recovered project evidence. That credit does not establish the identity of every current rights holder.

## Rights, ownership and affiliation

We do not own or claim ownership of the original game, its original source code, compiled code, artwork, audio, fonts, characters, names or branding. Those rights remain with their respective rights holders.

This project contains newly written reconstruction code informed by inspection and reverse engineering of a recovered compiled iOS application. It is not a release of the original developer's source code, and we make no clean-room claim. Reconstructed behavior and converted resources do not transfer ownership of the original material.

This project is not affiliated with, sponsored by or endorsed by the original developer or rights holders. The Kitten Jump name identifies the game being reconstructed.

The archival source documents where the recovered material reportedly came from; it is not a license or evidence of permission. Fan, preservation, educational or noncommercial intent does not by itself authorize copying, adaptation or distribution. We do not claim that the game is public domain, that its rights have expired, or that this project has an established fair-use exemption.

The new reconstruction code, tools and documentation are open source under the [MIT license](LICENSE), to the extent the contributors hold rights in those contributions. See [LICENSE_SCOPE.md](LICENSE_SCOPE.md) for the boundary between new work and preexisting material. The MIT license does not relicense the original game or grant permission to use or distribute its code, artwork, audio, fonts, names or branding. Existing third-party components retain their own licenses and notices.

If you hold rights to material associated with this project, contact the maintainer through the channel where the project was shared, identifying the work and the material of concern. We will review the concern and address corrections, restrictions or removal as appropriate.

This experimental reconstruction is provided as is, without warranties of accuracy, compatibility or noninfringement, to the extent permitted by applicable law. These notices explain the project's intent and limitations; they do not guarantee legal protection or replace legal advice. Permission or a qualified legal assessment should be obtained before distributing protected material.

For background, see the U.S. Copyright Office's [fair-use FAQ](https://www.copyright.gov/help/faq/faq-fairuse.html) and [Copyright in Derivative Works and Compilations](https://www.copyright.gov/circs/circ14.pdf).

## Archival source

The source collection supplied by the maintainer is [94iOSApps on Internet Archive](https://archive.org/download/94iOSApps).

The recovered local IPA is named `KittenJump-Paid-2.1.1-Christmas-bullate.ipa`. The archive lists the same bytes under `iOS Apps IPAs/usenet/Kitten Jump - Christmas Surprise! 2.1.1-bullate.ipa`: its size, SHA-1 and MD5 match our local copy. The local SHA-256 below identifies the exact artifact used for reconstruction. The listing was checked on October 16, 2026 using the collection's [metadata endpoint](https://archive.org/metadata/94iOSApps).

```text
SHA-256: 99cf9a56cb75a3967215b3658272decce94515a20003d132907e456284a4a07a
```

[SOURCE_PROVENANCE.json](SOURCE_PROVENANCE.json) records the filename, checksums and verification limits. Availability on Internet Archive does not establish that the uploader had authorization or that redistribution is permitted.

## Repository contents

The repository tracks the Flutter reconstruction source, Android/macOS project configuration, tests, conversion tools, technical reports, dependency lockfile and asset provenance manifests.

The original IPA, extracted app, original and converted game artwork/audio/fonts, original-art launcher icons, raw reverse-engineering output, local upload receipts, signing material and packaged builds are excluded from Git. Existing local copies remain on disk. The small factual inventory at `analysis/artifact-identity.json` is tracked because the converter uses it to verify input files.

## Build from a fresh checkout

A checkout does not include the original game's resources. Use original material only where you have the necessary rights or other lawful basis.

1. Place the expected IPA beside this README and verify its SHA-256.
2. Extract it into `Extracted/`, preserving `Payload/KJ2.app/`. On macOS, `ditto -x -k 'KittenJump-Paid-2.1.1-Christmas-bullate.ipa' Extracted` extracts the archive.
3. From `reconstruction/`, run `python3 tool/convert_assets.py`. Conversion uses macOS's `afconvert` for audio.
4. Restore the excluded launcher icons from an authorized local working copy, or supply replacement artwork matching the Android `mipmap-*/ic_launcher.png` paths and macOS `AppIcon.appiconset/Contents.json`.
5. Run `flutter pub get`, then build or run using the commands in the [development README](reconstruction/README.md). Flutter may regenerate the ignored Android Gradle wrapper files during setup.

The existing local project already has these resources and saved builds. Build caches regenerate when needed. See the [development README](reconstruction/README.md) for controls, verification history and known fidelity limits.

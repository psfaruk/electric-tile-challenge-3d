# Android Build — Electric Tile Challenge 3D

## What the CI pipeline does (`.github/workflows/android-build.yml`)

Triggered on every push / PR / manual dispatch:

1. **Java 17** (Temurin) — required for APK signing
2. **Android SDK** — command-line tools + `platform-tools` +
   `build-tools;34.0.0` (provides `apksigner`; everything is cached between runs)
3. **Godot 4.3-stable** headless Linux binary + **4.3.stable export templates**
   (cached)
4. **Editor settings** written to `~/.config/godot/editor_settings-4.3.tres`
   pointing at the JDK and Android SDK
5. Quality gates: import (compiles all scripts) → `--check-only` per script →
   **50-level validation** → **headless smoke test** (full gameplay loop)
6. `godot --headless --export-release "Android" build/ElectricTileChallenge3D.apk`
   — signed with the repository release keystore via build-tools `apksigner`
7. Artifact `ElectricTileChallenge3D-APK` uploaded on every run;
   **GitHub Release with the APK** published on `v*` tags

A second, non-blocking job renders **screenshots** of the menu and gameplay via
Mesa software GL + xvfb (`ETC_SHOT=menu|game`) and uploads them as evidence.

## APK facts

| Property | Value |
|---|---|
| Package | `com.electrictile.challenge` |
| Version | 1.0.0 (code 1) |
| ABIs | arm64-v8a + armeabi-v7a (universal-ish APK) |
| Min Android | 5.0 (API 21, Godot 4.3 default) |
| Target SDK | 34 |
| Renderer | Godot Mobile (Vulkan) |
| Approx. size | ~48 MB (two ABIs, all content embedded) |

## Signing — READ THIS BEFORE DISTRIBUTING

`android_signing/electric_tile_release.keystore` is a **demo signing key
committed intentionally** (PKCS12, alias `electrictile`, password
`ETC-electric-2025`) so that:

- CI can produce an installable, release-signed APK out of the box, and
- the app upgrades cleanly over previous builds (stable signature).

Because the key is public in this repository it is **only suitable for
personal/demo distribution**. Before publishing to Google Play (or any
store), replace it:

1. Generate your own keystore:
   `keytool -genkeypair -v -keystore release.keystore -alias electrictile -keyalg RSA -keysize 2048 -validity 10000`
2. Move it to `android_signing/` (and REMOVE the demo key).
3. Store the password in **GitHub Actions secrets** and patch
   `export_presets.cfg` in the workflow instead of committing it.
4. Uninstall the demo-signed build before installing the new one
   (different signature = no in-place upgrade).

## Local build (reproduce CI on your machine)

Requirements: Godot 4.3-stable (editor), its export templates, JDK 17+, Android
SDK build-tools 34, and the editor settings pointing to both (Editor →
Editor Settings → Export → Android).

Then: Project → Export… → **Android** → Export Project, or CLI:

```bash
godot --headless --import --path .
godot --headless --export-release "Android" build/ElectricTileChallenge3D.apk --path .
```

## Install on a device

1. Download the APK (Release page or Actions artifact).
2. On Android: open it; allow your browser/file manager to "install unknown
   apps" when prompted.
3. Or via adb: `adb install -r ElectricTileChallenge3D.apk`

## Building an AAB (Play Store, future)

Flip `gradle_build/use_gradle_build=true` and `gradle_build/export_format=1`
(AAB) in `export_presets.cfg` and install the Android SDK platform bundles
required by the gradle template. Not enabled for this release (APK-only
distribution).

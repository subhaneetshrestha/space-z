# Space Z — Build & Ship Guide

All artifacts start from **`dist/space-z.love`** (a zip of `conf.lua`, `main.lua`, `src/`,
`lib/` renamed to `.love`). Everything below is scripted under `build/`.

```
pwsh build/make-love.ps1                 # -> dist/space-z.love
pwsh build/build-windows.ps1 -LoveDir C:\path\to\love-11.5-win64   # -> dist/windows/SpaceZ.exe
pwsh build/build-android.ps1             # -> dist/android/*.apk (needs one-time SDK setup)
pwsh build/build-web.ps1                 # -> dist/web (static site; -Serve to test locally)
lovec . --icons                          # regenerate launcher icons (then copy from the
                                         #   LÖVE save dir into assets/icons/)
```

## Instant play (no build)

- **Desktop**: install LÖVE 11.x → `love .` from the repo root (or double-click
  `dist/space-z.love`).
- **Android**: install **LÖVE for Android** from Google Play (`org.love2d.android`),
  copy `dist/space-z.love` to the phone, open it. Full game, zero toolchain.

## Windows standalone

`build/build-windows.ps1` fuses `love.exe + space-z.love` into `dist/windows/SpaceZ.exe`
with the LÖVE DLLs alongside. Zip the folder to distribute. No installer needed.

## Android APK (one-time setup, then one command)

The plan flags this honestly: LÖVE's Android build is **not one-click** the first time.
One-time setup:

1. **JDK 17–21** — https://adoptium.net (ensure `java` is on PATH or `JAVA_HOME` is set).
   The script builds against love-android's default branch (AGP 8.13.x + Gradle 8.13),
   which supports modern JDKs; JDK 21 is verified working.
2. **Android SDK** — easiest: install Android Studio once and open its SDK Manager
   (installs platform + build-tools), or use the command-line `sdkmanager`.
   Set `ANDROID_HOME` (e.g. `%LOCALAPPDATA%\Android\Sdk`).
3. `git` on PATH.

Then: `pwsh build/build-android.ps1` — the script clones the official
[love-android](https://github.com/love2d/love-android) Gradle project, embeds
`space-z.love` as the game, sets the app name/id/version/portrait orientation from its
parameters, installs the launcher icons from `assets/icons/`, and runs the
`assembleEmbedNoRecord*` Gradle task (the NDK downloads automatically on first build).

- **Debug APK** (default): directly installable on any device with "unknown sources"
  enabled — right for playtesting.
- **Release APK** (`-Release`): unsigned. Sign before store upload:
  ```
  keytool -genkeypair -v -keystore spacez.keystore -alias spacez -keyalg RSA -validity 10000
  apksigner sign --ks spacez.keystore dist\android\app-embed-noRecord-release-unsigned.apk
  ```
- Store listing assets: `assets/icons/icon_512.png` is the Play Store icon;
  screenshots can be taken from any smoke run (`lovec . --smoke god` captures every
  zone and boss to the LÖVE save dir).

> Status note: this pipeline is fully scripted but was authored on a machine without the
> Android SDK — the first person to run it completes the one-time setup above. Every
> step before Gradle (packaging, identity patching, icons) is exercised by
> `make-love.ps1`, which IS verified (the packaged .love passes the smoke run).

## Web (love.js)

`build/build-web.ps1` converts `space-z.love` into a static site under `dist/web` using
[love.js](https://github.com/Davidobot/love.js) (LÖVE 11.5 compiled to WebAssembly).
Needs Node.js (e.g. `volta install node`); the converter is npm-installed into
`dist/web-tools` on first run and reused after that.

- The **compatibility build** (`-c`, the default here) is used: it avoids
  `SharedArrayBuffer`, so the site works on itch.io, GitHub Pages, or any static host
  without COOP/COEP headers. Trade-off: audio runs on the main thread (may crackle).
- Test locally with `pwsh build/build-web.ps1 -Serve` → http://localhost:8080
  (a plain `file://` open does NOT work — wasm must be served over HTTP).
- To publish: upload the contents of `dist/web` anywhere static (itch.io "HTML" project,
  GitHub Pages, Netlify, ...).

## iOS (requires a Mac — cannot be automated from Windows)

1. On a Mac with Xcode: clone https://github.com/love2d/love-apple-dependencies and
   https://github.com/love2d/love, per the official
   [iOS source instructions](https://love2d.org/wiki/Getting_Started#iOS).
2. Drop `space-z.love` into the Xcode project's resources (embedded game).
3. Set bundle id / display name / portrait-only orientation in the target settings.
4. Building/signing/TestFlight needs the owner's Apple Developer account.

## Store submission checklist (owner)

- Google Play / App Store accounts + fees (owner-held; see PLAN.md "Risks").
- Privacy policy URL (the game stores data only locally — no network, no analytics).
- Content rating questionnaire (fantasy sci-fi violence, no IAP at launch).

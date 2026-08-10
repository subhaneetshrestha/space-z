# Space Z — Build & Ship Guide

All artifacts start from **`dist/space-z.love`** (a zip of `conf.lua`, `main.lua`, `src/`,
`lib/` renamed to `.love`). Everything below is scripted under `build/`.

```
pwsh build/make-love.ps1                 # -> dist/space-z.love
pwsh build/build-windows.ps1 -LoveDir C:\path\to\love-11.5-win64   # -> dist/windows/SpaceZ.exe
pwsh build/build-android.ps1             # -> dist/android/*.apk (needs one-time SDK setup)
pwsh build/build-android.ps1 -Abis armeabi-v7a,arm64-v8a,x86_64   # + emulator support
pwsh build/build-web.ps1                 # -> dist/web (static site; -Serve to test locally)
lovec . --icons                          # regenerate launcher icons (then copy from the
                                         #   LÖVE save dir into assets/icons/)
```

## Continuous builds (GitHub Actions)

`.github/workflows/build.yml` runs the scripts above on every push to `main`, every
pull request, and every `v*` tag. It calls the same `build/*.ps1` scripts through
`pwsh` on Ubuntu runners — there is no second copy of the build logic to keep in sync.

| Job | Output |
|---|---|
| `test` | gate — `lua tests/run.lua`; a failure blocks every build below |
| `version` | resolves the version number and whether to publish |
| `package` | `space-z.love` |
| `windows` | `SpaceZ-<version>-windows-x64.zip` (exe + DLLs + license) |
| `android` | `SpaceZ-<version>-debug.apk` — debug-signed, installs directly |
| `release` | tags the commit and publishes a GitHub Release with all three attached |

**Getting the files:** every push to `main` publishes a
[Release](https://github.com/subhaneetshrestha/space-z/releases) — permanent download
links that need no account. Pull-request builds are not released; find those under the
Actions tab → the `build` run → *Artifacts* (needs a GitHub login, expires after 90 days).

### Versioning

Releases are numbered automatically, starting at **v0.0.1**. Each push to `main` reads the
highest existing `vMAJOR.MINOR.PATCH` tag and bumps it:

| Trigger | Version |
|---|---|
| push to `main` | previous tag + 1 **patch** — `v0.0.3` → `v0.0.4` |
| push to `main`, commit message contains `#minor` | `v0.0.3` → `v0.1.0` |
| push to `main`, commit message contains `#major` | `v0.3.7` → `v1.0.0` |
| `git push origin v1.2.3` | exactly `1.2.3` — the tag wins |
| pull request | `<next>-dev.<run number>`, artifacts only, no release |

The `release` job creates the tag itself as part of publishing, so there is nothing to tag
by hand. The Android `versionCode` is the workflow run number, so it always increases even
when the version name does not. Release notes are generated from the commits since the
previous release.

To publish without pushing a commit (e.g. re-releasing after an infrastructure failure),
run the workflow manually: Actions → `build` → *Run workflow* → tick **release**.

### Build speed

Every job except `android` finishes in seconds; the APK is the whole cost, and nearly all
of it is CMake/ninja compiling LÖVE + megasource once per ABI. Two things keep it down:

- **ABIs.** `build-android.ps1` builds `armeabi-v7a` + `arm64-v8a`, which covers every
  real Android phone. Upstream also builds `x86_64`, which only serves emulators — that
  is a third of the native build and a chunk of APK size for hardware nobody plays on.
  Pass `-Abis armeabi-v7a,arm64-v8a,x86_64` when you do need to run in an emulator.
- **Cache.** The workflow restores the whole `dist/android-build/love-android` tree — the
  `.cxx` objects, Gradle's up-to-date snapshots, *and* the clone they were built from, so
  ninja sees sources older than its objects instead of rebuilding everything. It is keyed
  on love-android's upstream HEAD (the clone is unpinned) plus a hash of
  `build-android.ps1`, and only saved after a green build, so a failed run cannot poison
  it. Expect a full rebuild whenever upstream moves or that script changes.

The APK build also pins `org.gradle.jvmargs=-Xmx4g`, because upstream sets no heap at all
and D8's dex merge runs out of memory on the default — intermittently, which is worse.

The APK is **debug-signed** — right for playtesting, not accepted by Google Play. Store
uploads still need a release keystore (see the Release APK notes below); wire that in as
repository secrets when store submission is actually on the table.

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

# Space Z — Build & Ship Guide

All artifacts start from **`dist/space-z.love`** (a zip of `conf.lua`, `main.lua`, `src/`,
`lib/` renamed to `.love`). Everything below is scripted under `build/`.

```
pwsh build/make-love.ps1                 # -> dist/space-z.love
pwsh build/get-love.ps1                  # fetch the LÖVE pinned in LOVE_VERSION -> dist/love12 (lovec.exe is in it)
pwsh build/build-windows.ps1             # LÖVE as pinned (fetched if needed) -> dist/windows/SpaceZ.exe
pwsh build/build-android.ps1             # -> dist/android/*.apk (needs one-time SDK setup)
pwsh build/build-android.ps1 -PrepareOnly   # check out + patch the pinned love-android, no Gradle build
pwsh build/build-android.ps1 -Abis armeabi-v7a,arm64-v8a,x86_64   # + emulator support
pwsh build/build-web.ps1                 # -> dist/web (static site; -Serve to test locally; see "Web" below)
lovec . --icons                          # regenerate launcher icons (then copy from the
                                         #   LÖVE save dir into assets/icons/)
```

## Which LÖVE

**`LOVE_VERSION`** (repo root) is the one place that says which LÖVE the game is built and tested against.
`conf.lua` reads it at startup (it ships inside the `.love`) and declares that version to LÖVE, so the engine
never shows its "made for another version" dialog; the build scripts and CI read the same file; nothing else
repeats the number (a test fails if a doc or script does).

| Key | Meaning | Used by |
|---|---|---|
| `love` | `MAJOR.MINOR` the game declares | `conf.lua` |
| `love_commit` | the `love2d/love` commit whose CI artifact is the desktop build | `get-love.ps1`, Windows build, CI |
| `love_win64_sha256` | sha256 of the mirrored copy of `love_commit`'s Windows build | `get-love.ps1`, `mirror-love.ps1` |
| `love_android_commit` | the `love2d/love-android` commit the APK is built from | `build-android.ps1`, CI cache key |
| `web_love`, `lovejs_commit` | the browser build's runtime (the one exception) and its `love.js` commit | `build-web.ps1` |

LÖVE 12 is not released yet, so its desktop builds exist only as **GitHub Actions artifacts** of `love2d/love`;
`get-love.ps1` downloads the artifact for the pinned commit with the GitHub CLI (`gh auth login` once). Two
consequences to know about:
- **Artifacts expire** (about 90 days; the pinned one around 2026-12-19), so the pinned build is also kept as a
  **mirror**: a pre-release of this repo, tag `love-<first 7 of love_commit>` (never marked Latest, ignored by the
  version and changelog logic, which only read `v*` tags). `get-love.ps1` uses the mirror first and trusts it only
  by the `love_win64_sha256` pin in `LOVE_VERSION`: a different hash is an error, a missing mirror falls back to the
  artifact (`-NoMirror` skips it). Only the pinned commit's build is mirrored. `build/mirror-love.ps1` makes it
  (see step 2b of "Moving to a newer LÖVE").
- **love-android carries its own LÖVE** (a submodule it updates on its own schedule). At the current pin it is
  older than `love_commit`; every Android build prints the bundled commit and notes when it differs.

Everything is pinned to a commit; no build follows an upstream branch.

## Continuous builds (GitHub Actions)

`.github/workflows/build.yml` runs the scripts above on every push to `main`, every
pull request, and every `v*` tag. It calls the same `build/*.ps1` scripts through
`pwsh` on the runners — there is no second copy of the build logic to keep in sync.

| Job | Output |
|---|---|
| `test` | gate — `lua tests/run.lua` (plain Lua 5.1, no LÖVE); a failure blocks every build below |
| `engine` | gate — the same suite **and a full smoke run inside the pinned LÖVE 12** (`lovec . --test`, `--smoke`), on Windows with Mesa's software OpenGL |
| `version` | resolves the version number and whether to publish (needs `test` and `engine`) |
| `package` | `space-z.love` |
| `windows` | `SpaceZ-<version>-windows-x64.zip` (exe + DLLs + license), fused from the pinned LÖVE |
| `android` | `SpaceZ-<version>-debug.apk` — debug-signed, installs directly, from the pinned love-android |
| `release` | tags the commit and publishes a GitHub Release with all three attached |

**The `engine` job.** A runner has no GPU, so OpenGL comes from **Mesa's software renderer (llvmpipe)**, the recipe
LÖVE's own Windows CI uses: a prebuilt Mesa download, **pinned by version and sha256 and verified before use**, whose
three OpenGL DLLs are copied beside `lovec.exe` in a *separate copy* of the LÖVE folder (never into the cached
`dist/love12`, whose DLLs the Windows build ships). `GALLIUM_DRIVER=llvmpipe` and `--renderers opengl` force the
software renderer, so a GPU a runner happens to have cannot change the result, and the log's `[renderer]` line
(printed by `main.lua`) must say `llvmpipe` or the job fails. The smoke screenshots are kept as an artifact.

The Mesa hash was taken from the download itself: its upstream (`pal1000/mesa-dist-win`) publishes no checksum.
What backs it is that the 24.2.4 asset has not changed since it was uploaded on 2024-10-09, and that the job only
ever runs a pinned file through the same check, so a swapped asset fails the build instead of running. Mesa never
reaches a shipped build. To move to a newer Mesa, download the new `release-msvc` asset, check its upload date and
that it is the one the release page lists, then update `MESA_URL` and `MESA_SHA256` together.

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
  on `LOVE_VERSION` (which pins the love-android commit) plus a hash of
  `build-android.ps1`, and only saved after a green build, so a failed run cannot poison
  it. Expect a full rebuild whenever the pin or that script changes. `build-android.ps1` leaves a
  tree already at the pin untouched (a fresh checkout would give every file a new mtime and
  rebuild the lot): a rebuild after a game-only change took 21 s locally.

The APK build also pins `org.gradle.jvmargs=-Xmx4g`, because upstream sets no heap at all
and D8's dex merge runs out of memory on the default — intermittently, which is worse.

The APK is **debug-signed** — right for playtesting, not accepted by Google Play. Store
uploads still need a release keystore (see the Release APK notes below); wire that in as
repository secrets when store submission is actually on the table.

## Instant play (no build)

- **Desktop**: `pwsh build/get-love.ps1`, then `dist\love12\lovec.exe .` from the repo root (use
  `lovec.exe` to see console output). Any LÖVE of the pinned version works the same way.
- **Android**: use the APK from a release or `build-android.ps1`. The **LÖVE for Android** player on
  Google Play is an older LÖVE than the one this game declares, so opening `space-z.love` there shows
  LÖVE's version warning.

## Windows standalone

`build/build-windows.ps1` fuses `love.exe + space-z.love` into `dist/windows/SpaceZ.exe`
with the LÖVE DLLs alongside. With no arguments it uses the LÖVE pinned in `LOVE_VERSION`
(fetching it into `dist/love12` if needed); `-LoveDir <folder>` uses one you already have, and
refuses it if its recorded commit (or, on Windows, its `love.exe` version) is not the pin. Zip
the folder to distribute. No installer needed. A fused exe keeps its saves in `%APPDATA%\space-z`
(not `%APPDATA%\LOVE\space-z`, which is where `lovec .` keeps them).

## Android APK (one-time setup, then one command)

The plan flags this honestly: LÖVE's Android build is **not one-click** the first time.
One-time setup:

1. **JDK 17** — https://adoptium.net (ensure `java` is on PATH or `JAVA_HOME` is set). CI uses
   Temurin 17, and the pinned love-android (Gradle 9.5, AGP 9.x) was built here with it.
2. **Android SDK** — easiest: install Android Studio once and open its SDK Manager
   (installs platform + build-tools), or use the command-line `sdkmanager`.
   Set `ANDROID_HOME` (e.g. `%LOCALAPPDATA%\Android\Sdk`).
3. `git` on PATH.

Then: `pwsh build/build-android.ps1` — the script checks out the official
[love-android](https://github.com/love2d/love-android) Gradle project **at the commit pinned in
`LOVE_VERSION`** (never its default branch), embeds `space-z.love` as the game, sets the app
name/id/version/portrait orientation from its parameters, installs the launcher icons from
`assets/icons/`, and runs the `assembleEmbedNoRecord*` Gradle task (the NDK, CMake and the Android
platform download automatically on first build into your SDK folder; the first x86_64 build took
about 11 minutes). `-PrepareOnly` stops before Gradle, to check the pin and the patches in seconds.

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

> **Status.** Built and run: an x86_64 debug APK was built from the pinned commit with JDK 17 and
> installed on an Android emulator, where the menu and a run render with no version dialog. Not yet
> checked on a phone, and the CI `android` job has not run on GitHub.
>
> **Two things about the Android runtime.** (1) The LÖVE inside the APK is whatever the pinned
> love-android commit bundles; `build-android.ps1` prints it and warns when it differs from
> `love_commit` (it is currently **older**: love-android has not updated its LÖVE submodule). (2) LÖVE 12
> prefers its Vulkan renderer on Android, and on the Android **emulator** that crashed inside the
> emulator's own Vulkan driver before any game code ran (a null pointer in
> `vkSetDebugUtilsObjectNameEXT`). Forcing OpenGL ES (`t.renderers = { "opengl" }` in `conf.lua`,
> tried as an experiment and not kept) ran fine. Real phones have real Vulkan drivers and the earlier APK
> ran on one, but if a device crashes at startup, that is the first thing to try.

## Moving to a newer LÖVE

A new LÖVE is a routine edit of `LOVE_VERSION`, not a rewrite. LÖVE 12 has no release yet, so a "newer
LÖVE" today means a newer commit.

1. **Find it.** `pwsh build/get-love.ps1 -Commit latest -Out dist/love-new` downloads the newest green
   build from `love2d/love`'s `main` and prints its commit. (Once LÖVE publishes a release, pin that
   instead and change `get-love.ps1` to download the release.)
2. **Edit `LOVE_VERSION`:** set `love` (the `MAJOR.MINOR` the game declares) and `love_commit`. Look at what
   `love_android_commit` bundles (`build-android.ps1 -PrepareOnly` prints it) and move that pin if
   love-android has caught up. Touch `web_love` only if a web port of the new LÖVE exists.
   2b. **Mirror it** (the artifact expires): `pwsh build/get-love.ps1 -NoMirror -Force`, then
   `pwsh build/mirror-love.ps1` packs `dist/love12` and prints the zip's sha256. Put it in `love_win64_sha256`, then
   `pwsh build/mirror-love.ps1 -Publish` uploads that same zip as pre-release `love-<commit>` (public, a one-time
   write: it refuses an existing tag, and a zip that is not the pinned one). Do this before the pull request
   merges, so CI and releases take the mirror. The old mirror stays; it is the build of the old pin.
3. **Run the tests, then run them inside the new LÖVE:** `lua tests/run.lua` (a test fails if `conf.lua`
   and `LOVE_VERSION` disagree, or any doc still names an old version), then
   `dist\love12\lovec.exe . --test` and `... --smoke` on the new build (`get-love.ps1 -Force` to refetch).
   Anything that breaks goes behind `src/compat.lua`, never into scattered version checks. If LÖVE
   removed an API the shim covered, delete the shim.
4. **Build:** `pwsh build/build-windows.ps1`; `pwsh build/build-android.ps1 -PrepareOnly`, then a real
   Android build. Open a pull request: CI's `engine` job runs the suite and the smoke run on the new pin,
   and the `windows` and `android` jobs rebuild (their caches are keyed on `LOVE_VERSION`).
5. **Check the screen**, not only the logs: run the game once on desktop, and install the APK.

## Web (love.js)

`build/build-web.ps1` converts the game into a static site under `dist/web` using
[love.js](https://github.com/Davidobot/love.js) (LÖVE compiled to WebAssembly).
Needs Node.js (e.g. `volta install node`); the converter is npm-installed into
`dist/web-tools` on first run and reused after that.

> **The one exception to LÖVE 12.** love.js has no LÖVE 12 port (upstream stops at 11.5, and
> no other web port targets 12), so the browser build runs an **11.x** runtime while the
> desktop and Android builds run the LÖVE pinned in `LOVE_VERSION`. It is kept on purpose, and
> contained:
> - `LOVE_VERSION` says which runtime the web build has (`web_love`) and pins the love.js
>   commit it installs (`lovejs_commit`). The script installs exactly that commit, never
>   love.js's default branch.
> - The web package is its own file, `dist/space-z-web.love`, built with its own copy of
>   `LOVE_VERSION` declaring `love=<web_love>`, so `conf.lua` tells the runtime the truth and
>   no version-mismatch warning appears. `make-love.ps1 -LoveVersion` does this; the desktop
>   and Android packages are never touched.
> - The game still runs on 11.x because the only engine difference it touches goes through
>   `src/compat.lua`.
> - **This build is not run in CI**, so nothing guards it between uses: if it breaks, it breaks
>   quietly. Run it before publishing.
> - When a LÖVE 12 web port exists, set `web_love` to 12.x (and the pin to its commit), or
>   delete the script and this section.

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

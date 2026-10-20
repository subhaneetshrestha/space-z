# LÖVE 12 findings (task B1)

Run on 2026-10-20 against the game at commit `052ef9b` (branch `feature/frozen-moment-save`), no game code changed.

## The build used

| | |
|---|---|
| Source | `love2d/love` Actions artifact `love-windows-x64`, workflow `continuous-integration` |
| Run | 35517017483 (push to `main`, 2026-09-20) |
| Commit | `b7daef0f7c1dc5888090f5d5b22d4eaf4ffd1d87` |
| Reports | `LOVE 12.0 (Bestest Friend)` |
| Fetched with | `pwsh build/get-love.ps1 -Commit b7daef0f7c1dc5888090f5d5b22d4eaf4ffd1d87 -Out dist/love12` |

The artifact is a `love-12.0-win64/` folder (love.exe, lovec.exe, SDL3 and OpenAL DLLs, `changes.txt`) plus a self-extracting exe of the same folder.
The folder is what `get-love.ps1` unpacks. The same CI run also has Linux AppImages, Android builds and macOS.
The upstream run's own `test-output-windows-x64-opengl-success` and `-opengles-success` artifacts show that LÖVE's own tests pass on Windows runners with GL, which is a good sign for task B4.

**Artifacts expire.** GitHub keeps them about 90 days, so this one disappears around 2026-12-19. A pinned commit needs a
plan for that, or CI breaks on its own (see "Decisions for later tasks").

## Result

| Command | As the repo is today (`t.version = "11.5"`) | With `t.version = "12.0"` (scratch copy) |
|---|---|---|
| `lovec . --test` | **Hangs** on a modal "Compatibility Warning" dialog, so it never runs unattended | `276 passed, 0 failed`, exit 0, nothing on stderr |
| `lovec . --smoke` | Same dialog | `RESULT: OK (time limit)`, exit 0: 320 s run, zone 2, level 11, 381 kills, boss spawned and killed |

The dialog is the one you saw on the phone: LÖVE 12 compares `conf.lua`'s `t.version` with its own version and asks the player
to confirm. On a desktop it blocks everything behind it, including CI. **The whole incompatibility today is this declaration.**
Nothing else in the 276 tests or the smoke run failed on LÖVE 12.

I checked the screenshots from the smoke run (menu, boss fight): sprites, glow, HUD and text render correctly. The new default font
(Noto Sans 13) looks fine in the menu.

## One warning

```
LOVE - Warning: src/render/sprites.lua:660: Using deprecated method Texture:newImageData (renamed to love.graphics.readbackTexture)
```

- It is a **deprecation**, not an error: the method still works in 12.0, but 12 prints it on stdout **and draws it over the
  game** (visible at the bottom of both screenshots).
- Two call sites: `src/render/sprites.lua:660` (building the sprite atlas, runs on every start) and `main.lua:263`
  (`--smoke` screenshots). The warning prints once per method, so only the first showed.
- Fix (task B2): one helper in `src/compat.lua` that uses `love.graphics.readbackTexture` when it exists and `canvas:newImageData()` otherwise.
  The exact signature of `readbackTexture` needs to be confirmed against 12 then.

## Checked in the code, no change needed

A search of `main.lua`, `conf.lua`, `src/` and `tests/` for what `changes.txt` lists as removed or deprecated in 12 found no use of:
`setNewFont`, `love.math.noise`, `newFile`, `love.filesystem.isFile/isDirectory/getSize/getLastModified`, `newText`,
`getImageFormats/getCanvasFormats`, `stencil/setStencilTest`, `t.window.highdpi`, `t.accelerometerjoystick`, `love.data.hash`,
no-argument `SpriteBatch:setColor()` (the game always passes four numbers, `sprites.lua:704`), no-argument `setColorMask`,
`love.window.setMode` with `display`, or slash-style `require`.
`conf.lua`'s `t.modules.joystick/physics/video = false` is still valid.

## Not covered by these runs

- Audio output, touch input and Android rendering (12 adds a Vulkan backend on Android). That needs the phone.
- The first thing to check there is that the compatibility dialog is gone once `conf.lua` says 12.0 (task B5).
- `--smoke` writes `smoke_report.txt` and screenshots to the real LÖVE save folder (`%APPDATA%\LOVE\space-z`). That is today's behaviour, not new.

## Decisions for later tasks

1. **B2:** declare `12.0` in `conf.lua` from a single `LOVE_VERSION` file, and add the `readbackTexture` helper. That is all this run found.
2. **B3:** the pinned desktop artifact expires. Options: (a) re-pin to a newer commit whenever CI can no longer download it, (b) upload the
   unpacked build once as an asset on a GitHub Release of this repository and download that instead (permanent, and it still names the commit).
   I recommend (b); it will be raised with you in B3 before it is built.
3. **B4:** Windows runners have GL (upstream's own CI uses them), so the engine-test job can start on `windows-latest` rather than trying Linux with a virtual display first.

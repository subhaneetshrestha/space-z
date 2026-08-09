# GitHub Actions CI/CD — downloadable Android APK and Windows build

**Date:** 2026-08-09
**Status:** Approved

## Goal

Every push to `main` produces a downloadable Android APK and a Windows standalone
build. Version tags additionally publish a GitHub Release with permanent, public,
no-login download links.

## Constraints

- One source of truth for build logic. The repo already has working PowerShell build
  scripts (`build/make-love.ps1`, `build-windows.ps1`, `build-android.ps1`); CI calls
  them via `pwsh` rather than reimplementing them in bash.
- Ubuntu runners only. The Windows executable is `love.exe` with the `.love` archive
  appended — pure byte concatenation, so it cross-builds on Linux. Ubuntu runners are
  faster and cheaper than Windows ones.
- No secrets required. The workflow must succeed the moment it lands, with no manual
  keystore setup.

## Architecture

Single workflow, `.github/workflows/build.yml`.

**Triggers:** push to `main`, push of a `v*` tag, pull requests, and manual
(`workflow_dispatch`). Feature-branch pushes do not trigger, so PRs build once.

**Jobs:**

| Job | Runs on | Produces |
|---|---|---|
| `test` | ubuntu | Gate. Lua 5.1 + `lua tests/run.lua`. |
| `package` | ubuntu | `space-z.love`, plus the version strings the other jobs consume. |
| `windows` | ubuntu | `SpaceZ-<version>-windows-x64.zip` (exe + DLLs + license). |
| `android` | ubuntu | `SpaceZ-<version>-debug.apk`, debug-signed. |
| `release` | ubuntu | Tag pushes only: a GitHub Release with all three files attached. |

`windows` and `android` both depend on `test` and `package`. Each re-runs
`make-love.ps1` itself (the existing scripts already do this), so the `space-z.love`
artifact exists for download rather than as an inter-job dependency.

## Versioning

Computed once in `package` and passed downstream as job outputs.

- Tag `v1.2.3` → `versionName = 1.2.3`
- Any other ref → `versionName = 0.4.0-dev.<run_number>`
- `versionCode = <run_number>` in both cases — Android requires a monotonically
  increasing integer.

## Signing

Debug-signed APK. Installs directly on any device with "unknown sources" enabled;
requires no secrets. Not valid for a Google Play upload — that needs a release keystore
and is deliberately out of scope until store submission is actually on the table.

## Required repo changes

The three build scripts use Windows path separators and `gradlew.bat`. PowerShell on
Linux does not treat `\` as a path separator, so the scripts must switch to forward
slashes (valid on both platforms) and select `gradlew` vs `gradlew.bat` at runtime.
These are the only source changes; behaviour on Windows is unchanged.

## Error handling

- A failing test blocks every downstream job — no artifacts are published from a red build.
- `unzip -t` verifies the `.love` archive before it reaches the platform builds, so a
  corrupt archive fails loudly in `package` instead of silently producing a broken exe.
- The `release` job runs only on tags and only after all builds succeed, so a partial
  release cannot be published.

## Known limitations

- The fused `SpaceZ.exe` keeps LÖVE's default icon. Changing it requires `rcedit`,
  which is Windows-only tooling; not worth a Windows runner for a cosmetic detail.
- The `android` job clones `love2d/love-android`'s default branch, matching the local
  script. That is a moving upstream and can break through no fault of this repo.
  Pinning to a commit would be more reproducible but would drift from the local script
  and reintroduce the JDK incompatibility documented in `docs/BUILD.md`. Pin only if it
  actually breaks.
- Workflow artifacts expire after 90 days and require a GitHub login to download. Tagged
  releases are the durable, public path.

## Verification

- `make-love.ps1` still produces a valid `.love` on Windows (no local regression).
- The first CI run on `main` is watched end to end; the APK and Windows zip are
  confirmed present and non-trivially sized on the run page.

# build/build-android.ps1 — scripted Android APK via the official love-android
# Gradle project (github.com/love2d/love-android). One-time setup is heavy
# (JDK 17 + Android SDK); after that this script is a single command.
#
#   pwsh build/build-android.ps1                # debug APK (installable directly)
#   pwsh build/build-android.ps1 -Release       # unsigned release (sign before store upload)
#   pwsh build/build-android.ps1 -AppId com.yourdomain.spacez
#   pwsh build/build-android.ps1 -PrepareOnly   # check out the pinned love-android and patch it; no Gradle
#
# love-android is built at the commit pinned in LOVE_VERSION (love_android_commit), never at
# its default branch.
#
# Prerequisites (checked below):
#   - git
#   - JDK 17 on PATH (java -version) or JAVA_HOME
#   - Android SDK with platform + build-tools (set ANDROID_HOME or ANDROID_SDK_ROOT);
#     easiest path: install Android Studio once, or sdkmanager cmdline-tools.
#     The NDK is downloaded automatically by the Gradle build on first run.
param(
  [switch]$Release,
  [string]$AppId = "com.spacez.game",
  [string]$AppName = "Space Z",
  [string]$VersionName = "0.4.0",
  [int]$VersionCode = 4,
  # Every ABI is a full native compile of LÖVE + megasource, so the list is the
  # single biggest lever on build time. These two cover every real Android phone;
  # add 'x86_64' when you need the APK to run on an emulator.
  [string[]]$Abis = @("armeabi-v7a", "arm64-v8a"),
  [string]$WorkDir = "dist/android-build",
  # check out the pinned love-android and patch it, but stop before the Gradle build
  [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  # ---- prerequisite checks -------------------------------------------------
  $missing = @()
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $missing += "git (https://git-scm.com)" }
  if (-not (Get-Command java -ErrorAction SilentlyContinue) -and -not $env:JAVA_HOME) {
    $missing += "JDK 17 (https://adoptium.net) — java on PATH or JAVA_HOME"
  }
  $sdk = $env:ANDROID_HOME
  if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
  if (-not $sdk -or -not (Test-Path $sdk)) {
    $missing += "Android SDK — set ANDROID_HOME (install via Android Studio or cmdline-tools)"
  }
  if ($missing.Count -gt 0) {
    Write-Host "Missing prerequisites:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "See docs/BUILD.md for the one-time setup, then re-run this script."
    exit 1
  }

  # ---- package the game ----------------------------------------------------
  & pwsh -NoProfile -File "build/make-love.ps1"
  if ($LASTEXITCODE -ne 0) { throw "make-love failed" }

  # ---- love-android, at the commit pinned in LOVE_VERSION -------------------
  # Not the default branch: that moves on its own, and following it changed the APK between
  # two pushes (it is how the APK ended up on LÖVE 12 while conf.lua declared an older one). The
  # pinned commit also decides which LÖVE is built in, since love-android carries it as a
  # submodule, so that is printed below. A tree already at the pin (a restored CI cache) is
  # left untouched: checking it out again would give every file a new mtime and rebuild
  # the whole native tree.
  . "$PSScriptRoot/love-version.ps1"
  $pin = Get-LoveVersion
  $sha = $pin.love_android_commit
  if (-not $sha) {
    throw "LOVE_VERSION has no love_android_commit. Pin one: this build will not follow upstream's default branch."
  }
  $repo = "$WorkDir/love-android"
  $head = ""
  if (Test-Path "$repo/.git") { $head = (git -C $repo rev-parse HEAD 2>$null) }
  if ($head -ne $sha) {
    if (-not (Test-Path "$repo/.git")) {
      New-Item -ItemType Directory -Force $repo | Out-Null
      git -C $repo init -q
      if ($LASTEXITCODE -ne 0) { throw "git init failed" }
      git -C $repo remote add origin https://github.com/love2d/love-android
    }
    git -C $repo fetch --depth 1 origin $sha
    if ($LASTEXITCODE -ne 0) { throw "could not fetch love-android $sha" }
    # --force drops the patches below from an older run; they are applied again afterwards
    git -C $repo checkout --force --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "could not check out love-android $sha" }
    git -C $repo submodule update --init --recursive --depth 1 --force
    if ($LASTEXITCODE -ne 0) { throw "could not fetch love-android's submodules" }
  }
  $head = (git -C $repo rev-parse HEAD)
  if ($head -ne $sha) { throw "love-android is at $head, but LOVE_VERSION pins $sha" }
  # `160000 commit <sha><TAB>app/src/main/cpp/love`: the LÖVE this love-android commit builds
  $bundled = ((git -C $repo ls-tree HEAD app/src/main/cpp/love) -split "\s+")[2]
  Write-Host "love-android pinned at $sha, bundling love2d/love $bundled"
  if ($bundled -ne $pin.love_commit) {
    Write-Host "NOTE: the desktop build uses love2d/love $($pin.love_commit); see LOVE_VERSION" -ForegroundColor Yellow
  }

  # ---- embed the game ------------------------------------------------------
  New-Item -ItemType Directory -Force "$repo/app/src/embed/assets" | Out-Null
  Copy-Item "dist/space-z.love" "$repo/app/src/embed/assets/game.love" -Force

  # ---- app identity (gradle.properties) ------------------------------------
  $props = "$repo/gradle.properties"
  $content = Get-Content $props -Raw
  # upstream ships the name as app.name_byte_array (with app.name commented
  # out) and errors if both are set — disable the byte array, set app.name
  $content = $content -replace "(?m)^app\.name_byte_array=.*$", "#app.name_byte_array="
  if ($content -match "(?m)^#?app\.name=") {
    $content = $content -replace "(?m)^#?app\.name=.*$", "app.name=$AppName"
  } else {
    $content = "app.name=$AppName`n" + $content
  }
  $content = $content -replace "(?m)^app\.application_id=.*$", "app.application_id=$AppId"
  $content = $content -replace "(?m)^app\.version_name=.*$", "app.version_name=$VersionName"
  $content = $content -replace "(?m)^app\.version_code=.*$", "app.version_code=$VersionCode"
  $content = $content -replace "(?m)^app\.orientation=.*$", "app.orientation=portrait"

  # ---- build memory --------------------------------------------------------
  # Upstream sets no org.gradle.jvmargs, so the daemon runs at Gradle's default
  # heap and D8's dex merge (mergeExtDex*) OOMs unpredictably — the same commit
  # built fine one day and died the next on identical CI runners. Pin a heap big
  # enough for the merge; matched, not duplicated, when this script re-runs.
  $jvmargs = "org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g"
  if ($content -match "(?m)^org\.gradle\.jvmargs=") {
    $content = $content -replace "(?m)^org\.gradle\.jvmargs=.*$", $jvmargs
  } else {
    $content = $content.TrimEnd() + "`n$jvmargs`n"
  }

  Set-Content $props $content -NoNewline

  # ---- target ABIs (app/build.gradle) --------------------------------------
  # Upstream ships armeabi-v7a + arm64-v8a + x86_64. x86_64 exists for emulators
  # only, so shipping it costs a third of the native build and megabytes of APK
  # that no phone will ever load. Fail loudly rather than silently building all
  # three if upstream ever moves this declaration.
  $gradleFile = "$repo/app/build.gradle"
  $gradle = Get-Content $gradleFile -Raw
  if ($gradle -notmatch "(?m)^\s*abiFilters\s") {
    throw "no abiFilters line in $gradleFile — upstream layout changed, check the ABI patch"
  }
  $abiList = ($Abis | ForEach-Object { "'$_'" }) -join ", "
  $gradle = $gradle -replace "(?m)^(\s*)abiFilters\s.*$", "`${1}abiFilters $abiList"
  Set-Content $gradleFile $gradle -NoNewline
  Write-Host "target ABIs: $($Abis -join ', ')"

  # ---- launcher icons (from assets/icons, generated by `lovec . --icons`) --
  $iconMap = @{
    "mipmap-mdpi" = 48; "mipmap-hdpi" = 96; "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144; "mipmap-xxxhdpi" = 192
  }
  foreach ($dir in $iconMap.Keys) {
    $target = "$repo/app/src/main/res/$dir"
    if (Test-Path $target) {
      $src = "assets/icons/icon_$($iconMap[$dir]).png"
      if (Test-Path $src) {
        Get-ChildItem $target -Filter "*.png" | ForEach-Object {
          Copy-Item $src $_.FullName -Force
        }
      }
    }
  }

  if ($PrepareOnly) {
    Write-Host "OK: love-android prepared at $sha (-PrepareOnly: no Gradle build)"
    return
  }

  # ---- build ---------------------------------------------------------------
  Push-Location $repo
  try {
    $task = if ($Release) { "assembleEmbedNoRecordRelease" } else { "assembleEmbedNoRecordDebug" }
    # the wrapper differs per platform; the repo is also built by CI on Linux
    $onWindows = $IsWindows -or ($env:OS -eq "Windows_NT")
    if ($onWindows) {
      & .\gradlew.bat $task
    } else {
      & chmod +x ./gradlew
      & ./gradlew $task
    }
    if ($LASTEXITCODE -ne 0) { throw "gradle build failed" }
  } finally {
    Pop-Location
  }

  $apks = Get-ChildItem "$repo/app/build/outputs/apk" -Recurse -Filter "*.apk"
  New-Item -ItemType Directory -Force "dist/android" | Out-Null
  foreach ($apk in $apks) {
    Copy-Item $apk.FullName "dist/android/" -Force
    Write-Host "OK: dist/android/$($apk.Name)"
  }
  if ($Release) {
    Write-Host "NOTE: release APKs are unsigned — sign with apksigner before store upload (docs/BUILD.md)."
  }
} finally {
  Pop-Location
}

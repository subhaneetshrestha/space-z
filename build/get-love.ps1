# build/get-love.ps1 — fetch a LÖVE build from love2d/love's CI artifacts.
#
#   pwsh build/get-love.ps1                              # the commit pinned in LOVE_VERSION -> dist/love12
#   pwsh build/get-love.ps1 -Commit <sha> -Out <dir>     # a specific commit
#   pwsh build/get-love.ps1 -Commit latest               # newest green run on main (to pick a new pin)
#   pwsh build/get-love.ps1 -Artifact love-linux-X64.AppImage -Out dist/love12-linux
#   pwsh build/get-love.ps1 -Force                       # fetch again even if -Out already holds the commit
#
# LÖVE 12 has no release tag yet, so its desktop builds only exist as GitHub Actions
# artifacts of the `continuous-integration` workflow. The artifact for the commit is
# downloaded with the GitHub CLI (`gh auth login` once locally; CI sets GH_TOKEN) and
# unpacked into -Out, with the commit written to -Out/COMMIT so a later run can tell
# what the folder holds. Artifacts expire (about 90 days), so a missing one is reported
# with the commit that was asked for instead of silently falling back to another.
#
# Prerequisites: gh (https://cli.github.com), logged in.
param(
  [string]$Commit,
  [string]$Out = "dist/love12",
  [string]$Artifact = "love-windows-x64",
  [string]$Repo = "love2d/love",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  # -Out is deleted and recreated further down, so it must be a folder UNDER dist/: a stray
  # `-Out .`, `-Out ..`, `-Out dist` or a drive root must never be able to wipe anything else.
  $dist = [System.IO.Path]::GetFullPath((Join-Path $root "dist"))
  $outFull = if ([System.IO.Path]::IsPathRooted($Out)) { [System.IO.Path]::GetFullPath($Out) }
             else { [System.IO.Path]::GetFullPath((Join-Path $root $Out)) }
  $prefix = $dist.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $outFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "-Out '$Out' is refused: it is deleted and recreated, so it must be a folder under dist/ (got $outFull)"
  }

  . "$PSScriptRoot/love-version.ps1"
  if (-not $Commit) { $Commit = (Get-LoveVersion)["love_commit"] }

  # already fetched: the folder says which commit it holds
  if (-not $Force -and $Commit -ne "latest" -and (Test-Path "$Out/COMMIT") -and (Test-Path "$Out/love.exe")) {
    if ((Get-Content "$Out/COMMIT" -Raw).Trim() -eq $Commit) {
      Write-Host "OK: $Out already holds commit $Commit"
      return
    }
  }

  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh (GitHub CLI) not found — https://cli.github.com, then 'gh auth login'"
  }

  $workflow = gh api "repos/$Repo/actions/workflows/main.yml" --jq .id
  if ($LASTEXITCODE -ne 0) { throw "could not look up the $Repo workflow (is gh logged in, or GH_TOKEN set?)" }

  if ($Commit -eq "latest") {
    $query = "branch=main&status=success&per_page=1"
  } else {
    $query = "head_sha=$Commit&status=success&per_page=1"
  }
  $run = gh api "repos/$Repo/actions/workflows/$workflow/runs?$query" `
    --jq '.workflow_runs[0] | "\(.id) \(.head_sha)"'
  if ($LASTEXITCODE -ne 0 -or -not $run -or $run -eq "null") {
    throw "no successful CI run found for '$Commit' in $Repo (artifacts expire after ~90 days)"
  }
  $runId, $sha = $run -split " "

  if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
  New-Item -ItemType Directory -Force $Out | Out-Null

  Write-Host "downloading '$Artifact' from run $runId (commit $sha)"
  gh run download $runId --repo $Repo --name $Artifact --dir $Out
  if ($LASTEXITCODE -ne 0) { throw "artifact '$Artifact' not found or expired for run $runId" }

  # the Windows artifact is a zip inside the artifact zip on some runs; flatten it
  Get-ChildItem $Out -Filter *.zip | ForEach-Object {
    Expand-Archive $_.FullName -DestinationPath $Out -Force
    Remove-Item $_.FullName
  }
  # The Windows artifact is love-<version>-win64/ (love.exe, lovec.exe, DLLs) next to a
  # self-extracting .exe of the same folder. Keep the folder's contents at the top
  # of -Out, so `-LoveDir <Out>` and `<Out>/lovec.exe` just work.
  $loveExe = Get-ChildItem $Out -Recurse -Filter love.exe | Select-Object -First 1
  if ($loveExe -and $loveExe.Directory.FullName -ne (Resolve-Path $Out).Path) {
    $dir = $loveExe.Directory
    Get-ChildItem $Out | Where-Object { $_.FullName -ne $dir.FullName } |
      Remove-Item -Recurse -Force
    Get-ChildItem $dir.FullName | Move-Item -Destination $Out
    Remove-Item $dir.FullName -Recurse -Force
  }

  Set-Content "$Out/COMMIT" $sha -NoNewline
  Write-Host "OK: $Out (commit $sha)"
} finally {
  Pop-Location
}

# Builds a new signed APK and publishes it so the app can offer "Update".
# Usage (from the repo root):  .\scripts\release.ps1 -Repo yourname/cukup-releases -Notes "What changed"
# Needs: Flutter, the GitHub CLI (gh) signed in, and a PUBLIC repo for -Repo (it only holds the APK and version.json).
param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [string]$Notes = ''
)
$ErrorActionPreference = 'Stop'
$env:Path += ';C:\src\flutter\bin'
$root = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $root 'app\pubspec.yaml'

# 1. Bump the build number: 1.0.0+3 becomes 1.0.0+4
$text = Get-Content $pubspec -Raw
if ($text -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Could not read version: from pubspec.yaml' }
$name = $Matches[1]
$build = [int]$Matches[2] + 1
$text = $text -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $name+$build"
Set-Content $pubspec $text -NoNewline

# 2. Build
Push-Location (Join-Path $root 'app')
flutter build apk --release --target-platform android-arm64
$built = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'
Pop-Location
if (-not (Test-Path $built)) { throw 'Build failed: no APK produced' }

# 3. Publish: the APK plus a small version.json that the app reads
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$apk = Join-Path $dist 'cukup.apk'
Copy-Item $built $apk -Force
$tag = "v$build"
$json = @{ build = $build; name = $name; apk = "https://github.com/$Repo/releases/download/$tag/cukup.apk"; notes = $Notes } | ConvertTo-Json
[System.IO.File]::WriteAllText((Join-Path $dist 'version.json'), $json, (New-Object System.Text.UTF8Encoding($false))) # no byte-order mark
gh release create $tag $apk (Join-Path $dist 'version.json') --repo $Repo --title "Cukup $name ($build)" --notes "$Notes"
Write-Host "Published $tag. Open Cukup, Settings, Check."

# Makes the public copy of this repo: the committed files, with personal settings swapped for placeholders.
# Usage (from the repo root):  .\scripts\export-public.ps1 [-Dest ..\cukup-public]
# The destination keeps its own .git folder, so afterwards: review, commit and push from there.
# This script holds no secrets itself: it finds the lines to replace by their shape, not by their value.
param([string]$Dest = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Dest) { $Dest = Join-Path (Split-Path -Parent $root) 'cukup-public' }
$enc = New-Object System.Text.UTF8Encoding($false)

# 1. Only committed files, never the working folder (so ignored secrets cannot leak).
$zip = Join-Path $env:TEMP 'cukup-export.zip'
$tmp = Join-Path $env:TEMP 'cukup-export'
if (Test-Path $zip) { Remove-Item $zip }
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
git -C $root archive --format=zip -o $zip HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
Expand-Archive $zip $tmp
Remove-Item $zip

# 2. Replace the destination's files, keeping its git history.
New-Item -ItemType Directory -Force $Dest | Out-Null
Get-ChildItem $Dest -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
Copy-Item (Join-Path $tmp '*') $Dest -Recurse -Force
Copy-Item (Join-Path $tmp '.gitignore') $Dest -Force
Remove-Item -Recurse -Force $tmp

function Swap([string]$file, [string]$pattern, [string]$with) {
  $p = Join-Path $Dest $file
  $t = [IO.File]::ReadAllText($p, $enc)
  if (-not [regex]::IsMatch($t, $pattern)) { throw "Nothing to replace in $file for: $pattern" }
  [IO.File]::WriteAllText($p, [regex]::Replace($t, $pattern, $with), $enc)
}

# 3. Personal settings become placeholders.
Swap 'app\lib\core\config.dart' "const apiBase = '[^']*';" "const apiBase = 'https://cukup-worker.YOUR-SUBDOMAIN.workers.dev';"
Swap 'app\lib\core\config.dart' "const defaultPayLink = '[^']*';" "const defaultPayLink = 'https://example.com/your-payment-link';"
Swap 'worker\wrangler.toml' 'database_id = "[^"]*"' 'database_id = "REPLACE_WITH_YOUR_D1_DATABASE_ID"'
Swap 'worker\migrations\0002_seed.sql' '(?s)INSERT INTO bills.*?;\r?\n' ''
Swap 'worker\migrations\0002_seed.sql' "\('emergency_target_cents','\d+'\)" "('emergency_target_cents','300000')"
Swap 'worker\migrations\0002_seed.sql' "'Emergency fund',\d+" "'Emergency fund',300000"

# 4. The payment QR is personal: ship a placeholder image instead.
Add-Type -AssemblyName System.Drawing
$bmp = New-Object Drawing.Bitmap 600, 600
$g = [Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::White)
$pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(180, 180, 190)), 6
$pen.DashStyle = 'Dash'
$g.DrawRectangle($pen, 40, 40, 520, 520)
$font = New-Object Drawing.Font 'Segoe UI', 28, ([Drawing.FontStyle]::Bold)
$fmt = New-Object Drawing.StringFormat
$fmt.Alignment = 'Center'
$fmt.LineAlignment = 'Center'
$brush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(110, 110, 125))
$g.DrawString("Replace with`nyour payment QR`n(app/assets/tng_qr.png)", $font, $brush, (New-Object Drawing.RectangleF 40, 40, 520, 520), $fmt)
$bmp.Save((Join-Path $Dest 'app\assets\tng_qr.png'), [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

# 5. Last check: stop if anything that looks personal or secret is still there.
$bad = '(?<!YOUR-SUBDOMAIN)\.workers\.dev|payment\.tngdigital|@gmail\.com|database_id = "[0-9a-f]{8}-|AIza[0-9A-Za-z_-]{20}|gh[pos]_[0-9A-Za-z]{20}|BEGIN [A-Z ]*PRIVATE KEY|storePassword=\S{4}'
$hits = Get-ChildItem $Dest -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Extension -notin '.png', '.ttf', '.jar' -and $_.Name -ne 'export-public.ps1' } | Select-String -Pattern $bad
if ($hits) {
  $hits | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber)" }
  throw 'Found something that should not be public. Nothing was pushed. Fix it and run again.'
}
Write-Host "Public copy is ready in $Dest. Review it, then commit and push from there."

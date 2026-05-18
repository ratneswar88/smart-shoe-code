
param(
  [string]$ProjectPath = "."
)

function Backup-File($Path) {
  if (Test-Path $Path) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $Path "$Path.bak.$stamp" -Force
    Write-Host "Backup created: $Path.bak.$stamp"
  }
}

$Pubspec = Join-Path $ProjectPath "pubspec.yaml"
$Main    = Join-Path $ProjectPath "lib\main.dart"
if (!(Test-Path $Pubspec)) { Write-Error "pubspec.yaml not found"; exit 1 }
if (!(Test-Path $Main)) { Write-Error "lib/main.dart not found"; exit 1 }

# --- 1) pubspec: ensure fl_chart present (no duplicates) ---
Backup-File $Pubspec
$yaml = Get-Content $Pubspec -Raw

# Remove duplicate lines for these pkgs
$yaml = [regex]::Replace($yaml, "(?m)^\s*fl_chart\s*:\s*.*\r?\n", "")
$yaml = [regex]::Replace($yaml, "(?m)^\s*geolocator\s*:\s*.*\r?\n", "")
$yaml = [regex]::Replace($yaml, "(?m)^\s*connectivity_plus\s*:\s*.*\r?\n", "")
$yaml = [regex]::Replace($yaml, "(?m)^\s*app_settings\s*:\s*.*\r?\n", "")

if ($yaml -notmatch "(?m)^\s*dependencies:\s*$") { $yaml += "`n`ndependencies:`n" }
$yaml = $yaml -replace "(?m)^(\s*dependencies:\s*\r?\n)", "`${1}  fl_chart: ^0.66.2`r`n  geolocator: ^13.0.4`r`n  connectivity_plus: ^6.0.3`r`n"

Set-Content $Pubspec $yaml -Encoding UTF8
Write-Host "pubspec.yaml patched (fl_chart, geolocator, connectivity_plus)."

# --- 2) main.dart edits ---
Backup-File $Main
$code = Get-Content $Main -Raw

# (a) Remove app_settings import and usages; normalize to Geolocator.openAppSettings()
$code = [regex]::Replace($code, "(?m)^\s*import\s+'package:app_settings/app_settings\.dart';\s*\r?\n", "")
$code = $code -replace "AppSettings\.openWIFISettings\(\)", "Geolocator.openAppSettings()"
$code = $code -replace "AppSettings\.openAppSettings\([^\)]*\)", "Geolocator.openAppSettings()"
$code = $code -replace "AppSettingsType\.\w+", ""

# (b) Ensure imports exist
function EnsureImport([string]$src, [string]$imp) {
  if ($src -notmatch [Regex]::Escape($imp)) {
    if ($src -match "(?m)^import\s+'package:flutter/material.dart';") {
      return ($src -replace "(?m)^(import\s+'package:flutter/material.dart';\s*)", "`${1}${imp}`r`n")
    } else {
      return $imp + "`r`n" + $src
    }
  }
  return $src
}
$code = EnsureImport $code "import 'package:fl_chart/fl_chart.dart';"
$code = EnsureImport $code "import 'package:geolocator/geolocator.dart';"
$code = EnsureImport $code "import 'package:connectivity_plus/connectivity_plus.dart';"
$code = EnsureImport $code "import 'package:latlong2/latlong.dart';"

# (c) Deduplicate _posSub (ensure exactly one, non-final)
$code = $code -replace "(?m)^\s*final\s+StreamSubscription<Position>\?\s*_posSub\s*;", "StreamSubscription<Position>? _posSub;"
$decls = [regex]::Matches($code, "(?m)^\s*StreamSubscription<Position>\?\s*_posSub\s*;")
if ($decls.Count -gt 1) {
  $first = $decls[0]
  $keepEnd = $first.Index + $first.Length
  $head = $code.Substring(0, $keepEnd)
  $tail = $code.Substring($keepEnd)
  $tail = [regex]::Replace($tail, "(?m)^\s*StreamSubscription<Position>\?\s*_posSub\s*;\s*\r?\n", "")
  $code = $head + $tail
}

# (d) Ensure fields in _TrainingPageState: _isCapturing, _distanceMeters
if ($code -match "class\s+_TrainingPageState\s+extends\s+State<") {
  $code = [regex]::Replace($code, '(?s)(class\s+_TrainingPageState\s+extends\s+State<[^>]+>\s*\{)',
    { param($m)
      $body = $m.Groups[1].Value
      $add = ""
      if ($code -notmatch "(?s)class\s+_TrainingPageState.*?\bbool\s+_isCapturing\b") {
        $add += "`n  bool _isCapturing = false;"
      }
      if ($code -notmatch "(?s)class\s+_TrainingPageState.*?\bdouble\s+_distanceMeters\b") {
        $add += "`n  double _distanceMeters = 0;"
      }
      return $body + $add + "`n"
    })
}

# (e) Clean up any stray 'fitCamera removed' tokens and dangling awaits
$code = [regex]::Replace($code, "(?m)^\s*[\w\.]+\s*/\*\s*fitCamera removed: using initialCameraFit\s*\*/\s*;?\s*$", "")
$code = [regex]::Replace($code, "(?m)^\s*await\s+Future\.delayed\(\s*const\s+Duration\(milliseconds:\s*1200\)\s*\)\s*;\s*$", "")

Set-Content $Main $code -Encoding UTF8
Write-Host "main.dart updated (imports, AppSettings removed, _posSub deduped, capture fields added)."

Write-Host "`nNow run:" -ForegroundColor Cyan
Write-Host "  flutter clean"
Write-Host "  flutter pub get"
Write-Host "  flutter build apk --release --target-platform=android-arm,android-arm64 --split-per-abi"

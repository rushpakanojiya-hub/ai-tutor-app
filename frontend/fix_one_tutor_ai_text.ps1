$ErrorActionPreference = "Stop"

# ===== Fix 1: AndroidManifest.xml - home screen label =====
$manifestPath = Join-Path $PSScriptRoot "android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifestPath)) { Write-Host "ERROR: AndroidManifest.xml not found"; exit 1 }

$rawManifest = [System.IO.File]::ReadAllText($manifestPath)
$manifestContent = $rawManifest -replace "`r`n", "`n"
$originalManifest = $manifestContent

$oldLabel = 'android:label="One Tutor App"'
$newLabel = 'android:label="One Tutor AI"'

if ($manifestContent.Contains($oldLabel)) {
    $manifestContent = $manifestContent.Replace($oldLabel, $newLabel)
    Write-Host "AndroidManifest.xml: label updated to 'One Tutor AI'."
} else {
    Write-Host "AndroidManifest.xml: pattern not found - no changes made."
}

if ($manifestContent -ne $originalManifest) {
    [System.IO.File]::WriteAllText($manifestPath, $manifestContent, [System.Text.Encoding]::UTF8)
    Write-Host "AndroidManifest.xml saved."
}

# ===== Fix 2: splash_screen.dart - splash text =====
$splashPath = Join-Path $PSScriptRoot "lib\screens\splash\splash_screen.dart"
if (-not (Test-Path $splashPath)) { Write-Host "ERROR: splash_screen.dart not found"; exit 1 }

$rawSplash = [System.IO.File]::ReadAllText($splashPath)
$splashContent = $rawSplash -replace "`r`n", "`n"
$originalSplash = $splashContent

$oldText = "'One Tutor App',"
$newText = "'One Tutor AI',"

if ($splashContent.Contains($oldText)) {
    $splashContent = $splashContent.Replace($oldText, $newText)
    Write-Host "splash_screen.dart: text updated to 'One Tutor AI'."
} else {
    Write-Host "splash_screen.dart: pattern not found - no changes made."
}

if ($splashContent -ne $originalSplash) {
    [System.IO.File]::WriteAllText($splashPath, $splashContent, [System.Text.Encoding]::UTF8)
    Write-Host "splash_screen.dart saved."
}

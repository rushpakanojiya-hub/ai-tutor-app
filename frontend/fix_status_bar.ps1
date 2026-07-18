$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\main.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

# Step 1: add the services.dart import if not present
$importOld = "import 'package:flutter/material.dart';"
$importNew = "import 'package:flutter/material.dart';`nimport 'package:flutter/services.dart';"
if ($content.Contains($importOld) -and -not $content.Contains("package:flutter/services.dart")) {
    $content = $content.Replace($importOld, $importNew)
    Write-Host "Import added."
} else {
    Write-Host "Import already present or anchor not found - skipped."
}

# Step 2: set the status bar overlay style before runApp
$mainOld = "void main() {`n  runApp(const AiTutorApp());`n}"
$mainNew = @'
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fix: the status bar rendered solid black on some devices because
  // nothing ever set an overlay style - Flutter doesn't auto-theme the
  // status bar without an AppBar on every screen, so it fell back to the
  // OS/theme default (black on this device) instead of matching the
  // app's light background.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const AiTutorApp());
}
'@ -replace "`r`n", "`n"

if ($content.Contains($mainOld)) {
    $content = $content.Replace($mainOld, $mainNew)
    Write-Host "main() updated with status bar fix."
} else {
    Write-Host "main() pattern not found - no changes made there. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\main.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = @'
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

$new = @'
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fix ("Black status bar / safe area issue - all screens"): setting
  // ONLY the overlay style (colors) isn't enough on several Android
  // versions/OEM skins - without also telling Android to actually draw
  // edge-to-edge, the OS can still paint its own default system bar
  // background (black) behind/around our "transparent" request instead
  // of truly letting the app's own background show through. Enabling
  // edge-to-edge mode is what makes the transparent status/nav bar
  // colors below actually take effect consistently.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  runApp(const AiTutorApp());
}
'@ -replace "`r`n", "`n"

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "main.dart: edge-to-edge mode enabled and nav bar colors added."
} else {
    Write-Host "Pattern not found - no changes made. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

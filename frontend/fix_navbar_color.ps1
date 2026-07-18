$ErrorActionPreference = "Stop"

# ===== Fix main.dart =====
$mainPath = Join-Path $PSScriptRoot "lib\main.dart"
if (-not (Test-Path $mainPath)) { Write-Host "ERROR: main.dart not found"; exit 1 }

$rawMain = [System.IO.File]::ReadAllText($mainPath)
$mainContent = $rawMain -replace "`r`n", "`n"
$originalMain = $mainContent

$old1 = @'
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
'@ -replace "`r`n", "`n"

$new1 = @'
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
'@ -replace "`r`n", "`n"

if ($mainContent.Contains($old1)) {
    $mainContent = $mainContent.Replace($old1, $new1)
    Write-Host "main.dart: navigation bar color added."
} else {
    Write-Host "main.dart: pattern not found - skipped."
}

if ($mainContent -ne $originalMain) {
    [System.IO.File]::WriteAllText($mainPath, $mainContent, [System.Text.Encoding]::UTF8)
    Write-Host "main.dart saved."
}

# ===== Fix app_theme.dart =====
$themePath = Join-Path $PSScriptRoot "lib\core\theme\app_theme.dart"
if (-not (Test-Path $themePath)) { Write-Host "ERROR: app_theme.dart not found"; exit 1 }

$rawTheme = [System.IO.File]::ReadAllText($themePath)
$themeContent = $rawTheme -replace "`r`n", "`n"
$originalTheme = $themeContent

$old2 = @'
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
'@ -replace "`r`n", "`n"

$new2 = @'
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
'@ -replace "`r`n", "`n"

if ($themeContent.Contains($old2)) {
    $themeContent = $themeContent.Replace($old2, $new2)
    Write-Host "app_theme.dart: navigation bar color added."
} else {
    Write-Host "app_theme.dart: pattern not found - skipped."
}

if ($themeContent -ne $originalTheme) {
    [System.IO.File]::WriteAllText($themePath, $themeContent, [System.Text.Encoding]::UTF8)
    Write-Host "app_theme.dart saved."
}

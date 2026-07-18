$ErrorActionPreference = "Stop"

# ===== Fix 1: app_theme.dart - add systemOverlayStyle to AppBarTheme =====
$themePath = Join-Path $PSScriptRoot "lib\core\theme\app_theme.dart"
if (-not (Test-Path $themePath)) {
    Write-Host "ERROR: File not found at $themePath"
    exit 1
}

$rawTheme = [System.IO.File]::ReadAllText($themePath)
$themeContent = $rawTheme -replace "`r`n", "`n"
$originalTheme = $themeContent

$importOld = "import 'package:flutter/material.dart';`nimport 'package:google_fonts/google_fonts.dart';"
$importNew = "import 'package:flutter/material.dart';`nimport 'package:flutter/services.dart';`nimport 'package:google_fonts/google_fonts.dart';"
if ($themeContent.Contains($importOld) -and -not $themeContent.Contains("package:flutter/services.dart")) {
    $themeContent = $themeContent.Replace($importOld, $importNew)
    Write-Host "app_theme.dart: services.dart import added."
}

$appBarOld = @'
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
'@ -replace "`r`n", "`n"

$appBarNew = @'
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        // Fix: without this, every AppBar computes its own status bar
        // style automatically, which could silently disagree with the
        // global style set at app startup and leave a solid black bar on
        // some screens/devices. Setting it explicitly here makes every
        // AppBar-based screen consistent.
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
'@ -replace "`r`n", "`n"

if ($themeContent.Contains($appBarOld)) {
    $themeContent = $themeContent.Replace($appBarOld, $appBarNew)
    Write-Host "app_theme.dart: systemOverlayStyle added to AppBarTheme."
} else {
    Write-Host "app_theme.dart: AppBarTheme pattern not found - skipped."
}

if ($themeContent -ne $originalTheme) {
    [System.IO.File]::WriteAllText($themePath, $themeContent, [System.Text.Encoding]::UTF8)
    Write-Host "app_theme.dart saved."
} else {
    Write-Host "app_theme.dart: nothing to save."
}

# ===== Fix 2: main.dart - wrap MaterialApp.router in AnnotatedRegion =====
$mainPath = Join-Path $PSScriptRoot "lib\main.dart"
if (-not (Test-Path $mainPath)) {
    Write-Host "ERROR: File not found at $mainPath"
    exit 1
}

$rawMain = [System.IO.File]::ReadAllText($mainPath)
$mainContent = $rawMain -replace "`r`n", "`n"
$originalMain = $mainContent

$buildOld = @'
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AI Tutor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: _router,
    );
  }
}
'@ -replace "`r`n", "`n"

$buildNew = @'
  @override
  Widget build(BuildContext context) {
    // Fallback status bar style for screens with no AppBar (e.g. the
    // Home/Dashboard screen) - using AnnotatedRegion (not a raw
    // SystemChrome call) so it participates in the same override/restore
    // stack that AppBar's systemOverlayStyle uses, instead of the two
    // mechanisms silently fighting each other during navigation.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: MaterialApp.router(
        title: 'AI Tutor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
      ),
    );
  }
}
'@ -replace "`r`n", "`n"

if ($mainContent.Contains($buildOld)) {
    $mainContent = $mainContent.Replace($buildOld, $buildNew)
    Write-Host "main.dart: AnnotatedRegion wrapper added."
} else {
    Write-Host "main.dart: build() pattern not found - skipped."
}

if ($mainContent -ne $originalMain) {
    [System.IO.File]::WriteAllText($mainPath, $mainContent, [System.Text.Encoding]::UTF8)
    Write-Host "main.dart saved."
} else {
    Write-Host "main.dart: nothing to save."
}

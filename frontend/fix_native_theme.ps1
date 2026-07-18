$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "android\app\src\main\res\values\styles.xml"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = @'
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
'@ -replace "`r`n", "`n"

$new = @'
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
        <!-- Native-level safety net alongside the Flutter-side SystemChrome
             fix in main.dart: makes sure the status/nav bar never default
             to opaque black even in the brief window before Flutter's own
             Dart code runs. -->
        <item name="android:windowDrawsSystemBarBackgrounds">true</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/white</item>
    </style>
'@ -replace "`r`n", "`n"

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "styles.xml: native theme updated with transparent status bar / white nav bar."
} else {
    Write-Host "Pattern not found - no changes made. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

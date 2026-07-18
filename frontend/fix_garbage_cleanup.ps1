$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\courses\lesson_management_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = "  }ontext).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));`n      _load();`n    }`n  }`n  Future<void> _showLessonDialog({AdminLessonModel? existing}) async {"
$new = "  }`n  Future<void> _showLessonDialog({AdminLessonModel? existing}) async {"

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "Garbage fragment removed successfully."
} else {
    Write-Host "Pattern not found - no changes made. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

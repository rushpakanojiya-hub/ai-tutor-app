$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\courses\lesson_management_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    Write-Host "Make sure this script is sitting in your 'frontend' folder before running it."
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
# Normalize to \n for reliable matching regardless of how the file was saved.
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

# Fix A - _reorder()
$old1 = "    try {`n      await _service.reorderLessons(widget.courseId, items);`n    } catch (e) {`n      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));`n      _load();`n    }`n  }"
$new1 = "    try {`n      await _service.reorderLessons(widget.courseId, items);`n    } catch (e) {`n      if (!mounted) return;`n      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));`n      _load();`n    }`n  }"
if ($content.Contains($old1)) { $content = $content.Replace($old1, $new1); Write-Host "Fix A applied (reorder)" } else { Write-Host "Fix A: pattern not found - skipped" }

# Fix B - _showLessonDialog()
$old2 = "        _load();`n      } catch (e) {`n        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save lesson.')));`n      }"
$new2 = "        if (!mounted) return;`n        _load();`n      } catch (e) {`n        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save lesson.')));`n      }"
if ($content.Contains($old2)) { $content = $content.Replace($old2, $new2); Write-Host "Fix B applied (showLessonDialog)" } else { Write-Host "Fix B: pattern not found - skipped" }

# Fix C - _confirmDeleteLesson()
$old3 = "    try {`n      await _service.deleteLesson(lesson.id);`n      _load();`n    } catch (e) {`n      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete lesson.')));`n    }`n  }"
$new3 = "    try {`n      await _service.deleteLesson(lesson.id);`n      if (!mounted) return;`n      _load();`n    } catch (e) {`n      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete lesson.')));`n    }`n  }"
if ($content.Contains($old3)) { $content = $content.Replace($old3, $new3); Write-Host "Fix C applied (confirmDeleteLesson)" } else { Write-Host "Fix C: pattern not found - skipped" }

# Fix D - _uploadFile()
$old4 = "      if (mounted) {`n        ScaffoldMessenger.of(context).hideCurrentSnackBar();`n        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete.')));`n      }`n      _load();"
$new4 = "      if (mounted) {`n        ScaffoldMessenger.of(context).hideCurrentSnackBar();`n        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete.')));`n        _load();`n      }"
if ($content.Contains($old4)) { $content = $content.Replace($old4, $new4); Write-Host "Fix D applied (uploadFile)" } else { Write-Host "Fix D: pattern not found - skipped" }

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved successfully."
} else {
    Write-Host "No changes were made - nothing matched. Please tell Claude so it can check the file contents."
}

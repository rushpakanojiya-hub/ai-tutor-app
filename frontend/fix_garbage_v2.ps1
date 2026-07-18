$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\courses\lesson_management_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$lines = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($path))

$garbageIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -like "*ontext).showSnackBar(const SnackBar(content: Text(*Failed to save new order*") {
        $garbageIndex = $i
        break
    }
}

if ($garbageIndex -eq -1) {
    Write-Host "Could not find the garbage line. Showing lines 50-65 for inspection instead:"
    for ($i = 49; $i -lt 65 -and $i -lt $lines.Count; $i++) {
        Write-Host "$($i+1): $($lines[$i])"
    }
    exit 0
}

Write-Host "Found garbage marker at line $($garbageIndex + 1): $($lines[$garbageIndex])"

# Fix line: everything up to and including the FIRST "}" on that line stays, rest is discarded.
$closingBraceIndex = $lines[$garbageIndex].IndexOf('}')
$lines[$garbageIndex] = $lines[$garbageIndex].Substring(0, $closingBraceIndex + 1)

# Remove the next lines until we find "Future<void> _showLessonDialog"
$removeCount = 0
while (($garbageIndex + 1) -lt $lines.Count -and $lines[$garbageIndex + 1] -notlike "*Future<void> _showLessonDialog*") {
    $lines.RemoveAt($garbageIndex + 1)
    $removeCount++
    if ($removeCount -gt 10) {
        Write-Host "Safety stop - removed 10 lines without finding _showLessonDialog. Aborting to avoid damage."
        exit 1
    }
}

Write-Host "Removed $removeCount orphaned line(s) after the garbage marker."

[System.IO.File]::WriteAllLines($path, $lines, [System.Text.Encoding]::UTF8)
Write-Host "File saved successfully."

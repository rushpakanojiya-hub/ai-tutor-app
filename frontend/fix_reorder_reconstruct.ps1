$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\courses\lesson_management_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$lines = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($path))

# Find the exact broken spot: a line that is exactly "      if (!mounted) return;"
# immediately followed by a line containing "Future<void> _showLessonDialog"
$targetIndex = -1
for ($i = 0; $i -lt ($lines.Count - 1); $i++) {
    if ($lines[$i].Trim() -eq "if (!mounted) return;" -and $lines[$i+1] -like "*Future<void> _showLessonDialog*") {
        $targetIndex = $i
        break
    }
}

if ($targetIndex -eq -1) {
    Write-Host "Could not find the exact broken spot. No changes made. Showing lines 50-62 for inspection:"
    for ($i = 49; $i -lt 62 -and $i -lt $lines.Count; $i++) {
        Write-Host "$($i+1): $($lines[$i])"
    }
    exit 0
}

Write-Host "Found the broken spot at line $($targetIndex + 1)."

# Insert the missing lines right after "if (!mounted) return;" (index $targetIndex),
# before the "Future<void> _showLessonDialog" line.
$missingLines = @(
    "      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));",
    "      _load();",
    "    }",
    "  }",
    ""
)
$lines.InsertRange($targetIndex + 1, $missingLines)

[System.IO.File]::WriteAllLines($path, $lines, [System.Text.Encoding]::UTF8)
Write-Host "File reconstructed and saved successfully."

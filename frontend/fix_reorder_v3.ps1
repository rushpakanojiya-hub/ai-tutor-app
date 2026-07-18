$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\courses\lesson_management_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$lines = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($path))

$targetIndex = -1
for ($i = 0; $i -lt ($lines.Count - 1); $i++) {
    if ($lines[$i].Trim() -eq "if (!mounted) return;") {
        # look ahead up to 3 lines for the _showLessonDialog marker, allowing blank lines in between
        for ($j = $i + 1; $j -lt ($i + 4) -and $j -lt $lines.Count; $j++) {
            if ($lines[$j] -like "*Future<void> _showLessonDialog*") {
                $targetIndex = $i
                break
            }
        }
    }
    if ($targetIndex -ne -1) { break }
}

if ($targetIndex -eq -1) {
    Write-Host "Still could not find it. No changes made."
    exit 0
}

Write-Host "Found the broken spot at line $($targetIndex + 1)."

# Remove any blank lines directly after $targetIndex before inserting, to avoid double blank lines
while (($targetIndex + 1) -lt $lines.Count -and $lines[$targetIndex + 1].Trim() -eq "") {
    $lines.RemoveAt($targetIndex + 1)
}

$missingLines = @(
    "      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));",
    "      _load();",
    "    }",
    "  }",
    ""
)
$insertAt = $targetIndex + 1
foreach ($line in $missingLines) {
    $lines.Insert($insertAt, $line)
    $insertAt++
}

[System.IO.File]::WriteAllLines($path, $lines, [System.Text.Encoding]::UTF8)
Write-Host "File reconstructed and saved successfully."

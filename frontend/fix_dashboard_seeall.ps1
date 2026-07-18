$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\dashboard\dashboard_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = "_sectionHeader('New Assignments', onSeeAll: () => context.push('/assignment-detail', extra: {'assignmentId': _pendingAssignments.first.id})),"
$new = "_sectionHeader('New Assignments', onSeeAll: () => Navigator.of(context).push(`n              MaterialPageRoute(builder: (_) => const StudentAssignmentsScreen()),`n            )),"

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "Fix applied successfully."
} else {
    Write-Host "Pattern not found - no changes made. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

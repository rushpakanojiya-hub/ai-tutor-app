$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "backend\docker-compose.yml"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$lines = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($path))
$changed = $false

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^(\s*)GROQ_API_KEY:\s*"gsk_[^"]*"') {
        $indent = $Matches[1]
        $lines[$i] = "$indent" + 'GROQ_API_KEY: "${GROQ_API_KEY}"'
        Write-Host "Line $($i+1): GROQ_API_KEY now references the environment variable."
        $changed = $true
    }
    if ($lines[$i] -match '^(\s*)YOUTUBE_API_KEY:\s*"[^"]*"') {
        $indent = $Matches[1]
        $lines[$i] = "$indent" + 'YOUTUBE_API_KEY: "${YOUTUBE_API_KEY}"'
        Write-Host "Line $($i+1): YOUTUBE_API_KEY now references the environment variable."
        $changed = $true
    }
}

if ($changed) {
    [System.IO.File]::WriteAllLines($path, $lines, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "No matching lines found - no changes made. Please tell Claude."
}

$ErrorActionPreference = "Stop"

# ===== Fix 1: web/index.html =====
$htmlPath = Join-Path $PSScriptRoot "web\index.html"
if (-not (Test-Path $htmlPath)) { Write-Host "ERROR: web/index.html not found"; exit 1 }

$rawHtml = [System.IO.File]::ReadAllText($htmlPath)
$htmlContent = $rawHtml -replace "`r`n", "`n"
$originalHtml = $htmlContent

$htmlReplacements = @(
    @{ old = '<meta name="description" content="A new Flutter project.">'; new = '<meta name="description" content="One Tutor AI - Learn smarter, every day.">' },
    @{ old = '<meta name="apple-mobile-web-app-title" content="ai_tutor_app">'; new = '<meta name="apple-mobile-web-app-title" content="One Tutor AI">' },
    @{ old = '<title>ai_tutor_app</title>'; new = '<title>One Tutor AI</title>' }
)

foreach ($r in $htmlReplacements) {
    if ($htmlContent.Contains($r.old)) {
        $htmlContent = $htmlContent.Replace($r.old, $r.new)
        Write-Host "index.html: updated '$($r.old)'"
    } else {
        Write-Host "index.html: pattern not found - '$($r.old)'"
    }
}

if ($htmlContent -ne $originalHtml) {
    [System.IO.File]::WriteAllText($htmlPath, $htmlContent, [System.Text.Encoding]::UTF8)
    Write-Host "index.html saved."
}

# ===== Fix 2: web/manifest.json =====
$manifestPath = Join-Path $PSScriptRoot "web\manifest.json"
if (-not (Test-Path $manifestPath)) { Write-Host "ERROR: web/manifest.json not found"; exit 1 }

$rawManifest = [System.IO.File]::ReadAllText($manifestPath)
$manifestContent = $rawManifest -replace "`r`n", "`n"
$originalManifest = $manifestContent

$manifestReplacements = @(
    @{ old = '"name": "ai_tutor_app",'; new = '"name": "One Tutor AI",' },
    @{ old = '"short_name": "ai_tutor_app",'; new = '"short_name": "One Tutor AI",' },
    @{ old = '"description": "A new Flutter project.",'; new = '"description": "One Tutor AI - Learn smarter, every day.",' }
)

foreach ($r in $manifestReplacements) {
    if ($manifestContent.Contains($r.old)) {
        $manifestContent = $manifestContent.Replace($r.old, $r.new)
        Write-Host "manifest.json: updated '$($r.old)'"
    } else {
        Write-Host "manifest.json: pattern not found - '$($r.old)'"
    }
}

if ($manifestContent -ne $originalManifest) {
    [System.IO.File]::WriteAllText($manifestPath, $manifestContent, [System.Text.Encoding]::UTF8)
    Write-Host "manifest.json saved."
}

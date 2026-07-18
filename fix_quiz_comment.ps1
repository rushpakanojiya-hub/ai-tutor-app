$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "frontend\lib\services\quiz_service.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = "      // SECURITY TODO: toAnsweredJson() currently sends the answer key`n      // back to the server (backend trusts it - see the detailed note on`n      // that method). Needs a backend-side fix (server-stored answer key`n      // looked up by generation id) before this can be locked down.`n      'questions': questions.map((q) => q.toAnsweredJson()).toList(),"

$new = "      // Each question carries its own `signature` (an HMAC the backend`n      // computed over its real answer key at /generate time) alongside`n      // correct_option/correct_options/correct_text. The backend`n      // re-verifies that signature on submit (verifyAnswerKey in`n      // quiz/service.go) - if a client edits the answer key before`n      // submitting, the signature no longer matches and the whole`n      // submission is rejected rather than graded, so echoing this data`n      // back is safe even though there's no server-stored quiz bank for`n      // freeform quizzes to look it up from instead.`n      'questions': questions.map((q) => q.toAnsweredJson()).toList(),"

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

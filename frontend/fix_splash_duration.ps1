$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\splash\splash_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = "    WidgetsBinding.instance.addPostFrameCallback((_) {`n      context.read<AuthProvider>().tryAutoLogin();`n    });"

$new = "    WidgetsBinding.instance.addPostFrameCallback((_) {`n      // tryAutoLogin() only reads local storage, so it normally resolves`n      // in a few milliseconds - too fast for the splash branding to`n      // actually be seen. Waiting on both together means navigation only`n      // happens once BOTH are done: at least 2 seconds have passed AND`n      // the auth check has finished (so a slow device/storage read still`n      // extends the wait rather than cutting the check short).`n      Future.wait([`n        context.read<AuthProvider>().tryAutoLogin(),`n        Future.delayed(const Duration(seconds: 2)),`n      ]);`n    });"

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "Fix applied successfully - splash screen now shows for a minimum of 2 seconds."
} else {
    Write-Host "Pattern not found - no changes made. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

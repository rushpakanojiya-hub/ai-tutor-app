$ErrorActionPreference = "Stop"

# ===== Fix 1: auth_provider.dart - move the delay to wrap the actual status change =====
$providerPath = Join-Path $PSScriptRoot "lib\providers\auth_provider.dart"
if (-not (Test-Path $providerPath)) { Write-Host "ERROR: auth_provider.dart not found"; exit 1 }

$rawProvider = [System.IO.File]::ReadAllText($providerPath)
$providerContent = $rawProvider -replace "`r`n", "`n"
$originalProvider = $providerContent

$oldProvider = "  /// Called once at app startup to check for a previously saved session.`n  Future<void> tryAutoLogin() async {`n    final token = await _storage.getString(AppConstants.keyAuthToken);`n    final userId = await _storage.getInt(AppConstants.keyUserId);`n    final userName = await _storage.getString(AppConstants.keyUserName);`n    final userRole = await _storage.getString(AppConstants.keyUserRole);`n`n    if (token != null && userId != null && userName != null && userRole != null) {`n      currentUser = UserModel(id: userId, name: userName, role: userRole);`n      _setStatus(AuthStatus.authenticated);`n    } else {`n      _setStatus(AuthStatus.unauthenticated);`n    }`n    notifyListeners();`n  }"

$newProvider = @'
  /// Called once at app startup to check for a previously saved session.
  ///
  /// QA fix ("Splash screen disappears in milliseconds"): the storage
  /// reads below finish almost instantly, and _setStatus() is what
  /// actually triggers GoRouter's redirect via statusNotifier - so
  /// wrapping the CALLER's await in a delay (e.g. in splash_screen.dart)
  /// doesn't help, since the status change itself already fired before
  /// that delay even starts. The minimum-duration wait has to live here,
  /// wrapping the status change directly - the real storage check and a
  /// 2-second timer run together, and whichever finishes last is what
  /// _setStatus waits on.
  Future<void> tryAutoLogin() async {
    String? token;
    int? userId;
    String? userName;
    String? userRole;

    Future<void> readSession() async {
      token = await _storage.getString(AppConstants.keyAuthToken);
      userId = await _storage.getInt(AppConstants.keyUserId);
      userName = await _storage.getString(AppConstants.keyUserName);
      userRole = await _storage.getString(AppConstants.keyUserRole);
    }

    await Future.wait([
      readSession(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    if (token != null && userId != null && userName != null && userRole != null) {
      currentUser = UserModel(id: userId!, name: userName!, role: userRole!);
      _setStatus(AuthStatus.authenticated);
    } else {
      _setStatus(AuthStatus.unauthenticated);
    }
    notifyListeners();
  }
'@ -replace "`r`n", "`n"

if ($providerContent.Contains($oldProvider)) {
    $providerContent = $providerContent.Replace($oldProvider, $newProvider)
    Write-Host "auth_provider.dart: tryAutoLogin updated with the minimum-duration delay."
} else {
    Write-Host "auth_provider.dart: pattern not found - no changes made. Please tell Claude."
}

if ($providerContent -ne $originalProvider) {
    [System.IO.File]::WriteAllText($providerPath, $providerContent, [System.Text.Encoding]::UTF8)
    Write-Host "auth_provider.dart saved."
}

# ===== Fix 2: splash_screen.dart - revert to a simple call (delay now lives in the provider) =====
$splashPath = Join-Path $PSScriptRoot "lib\screens\splash\splash_screen.dart"
if (-not (Test-Path $splashPath)) { Write-Host "ERROR: splash_screen.dart not found"; exit 1 }

$rawSplash = [System.IO.File]::ReadAllText($splashPath)
$splashContent = $rawSplash -replace "`r`n", "`n"
$originalSplash = $splashContent

$oldSplash = "    WidgetsBinding.instance.addPostFrameCallback((_) {`n      // tryAutoLogin() only reads local storage, so it normally resolves`n      // in a few milliseconds - too fast for the splash branding to`n      // actually be seen. Waiting on both together means navigation only`n      // happens once BOTH are done: at least 2 seconds have passed AND`n      // the auth check has finished (so a slow device/storage read still`n      // extends the wait rather than cutting the check short).`n      Future.wait([`n        context.read<AuthProvider>().tryAutoLogin(),`n        Future.delayed(const Duration(seconds: 2)),`n      ]);`n    });"

$newSplash = "    WidgetsBinding.instance.addPostFrameCallback((_) {`n      // The minimum 2-second splash duration is enforced inside`n      // tryAutoLogin() itself (see auth_provider.dart) - it has to wrap`n      // the actual status change there, not the await here, since it's`n      // that status change which triggers navigation via GoRouter.`n      context.read<AuthProvider>().tryAutoLogin();`n    });"

if ($splashContent.Contains($oldSplash)) {
    $splashContent = $splashContent.Replace($oldSplash, $newSplash)
    Write-Host "splash_screen.dart: reverted to a simple call."
} else {
    Write-Host "splash_screen.dart: pattern not found (may already be simple) - no changes made."
}

if ($splashContent -ne $originalSplash) {
    [System.IO.File]::WriteAllText($splashPath, $splashContent, [System.Text.Encoding]::UTF8)
    Write-Host "splash_screen.dart saved."
}

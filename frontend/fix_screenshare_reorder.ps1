$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\liveclass\live_class_room_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old = @'
  Future<void> _toggleScreenShare() async {
    if (_screenShareBusy) return; // ignore taps while a toggle is in flight
    _screenShareBusy = true;
    try {
      final newState = !_screenSharing;
      if (newState) {
        // Must start BEFORE setScreenShareEnabled(true) - Android 14+
        // kills the app if MediaProjection.start() is called without an
        // active foregroundServiceType="mediaProjection" service running.
        await _screenShareChannel.invokeMethod('startScreenShareService');
        // Give the service's onStartCommand -> startForeground() a beat to
        // actually run before we ask the OS for the MediaProjection token -
        // startForegroundService() only queues the start, it doesn't
        // guarantee startForeground() has executed by the time this
        // await returns.
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await _room.localParticipant?.setScreenShareEnabled(newState);
      if (!newState) {
        await _screenShareChannel.invokeMethod('stopScreenShareService');
      }
      // ignore: avoid_print
      print('[LiveClassRoom] Screen share toggled to $newState successfully');
      if (mounted) setState(() => _screenSharing = newState);
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[LiveClassRoom] Screen share toggle failed: $e');
      // ignore: avoid_print
      print(stackTrace);
      await _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
      _showToast('Could not ${_screenSharing ? "stop" : "start"} screen sharing on this device.');
    } finally {
      _screenShareBusy = false;
    }
  }
'@ -replace "`r`n", "`n"

$new = @'
  Future<void> _toggleScreenShare() async {
    if (_screenShareBusy) return; // ignore taps while a toggle is in flight
    _screenShareBusy = true;
    try {
      final newState = !_screenSharing;

      if (newState) {
        // Real-device testing showed Android enforces this check based on
        // the device's actual OS build, not just our targetSdk: a
        // foreground service of type "mediaProjection" can only start
        // AFTER the MediaProjection permission is already granted (the
        // "project_media" AppOp). Starting our own foreground service
        // BEFORE the permission dialog even appears (the old order)
        // always throws a SecurityException and crashes the whole app.
        // So: request the permission / start capture FIRST via
        // setScreenShareEnabled, and only THEN start our foreground
        // service - best-effort, since losing just the persistent
        // notification isn't worth failing the whole feature over.
        await _room.localParticipant?.setScreenShareEnabled(true);
        try {
          await _screenShareChannel.invokeMethod('startScreenShareService');
        } catch (_) {
          // Non-fatal - screen share itself is already running.
        }
      } else {
        await _room.localParticipant?.setScreenShareEnabled(false);
        await _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
      }

      // ignore: avoid_print
      print('[LiveClassRoom] Screen share toggled to $newState successfully');
      if (mounted) setState(() => _screenSharing = newState);
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[LiveClassRoom] Screen share toggle failed: $e');
      // ignore: avoid_print
      print(stackTrace);
      await _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
      _showToast('Could not ${_screenSharing ? "stop" : "start"} screen sharing on this device.');
    } finally {
      _screenShareBusy = false;
    }
  }
'@ -replace "`r`n", "`n"

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "Fix applied successfully - permission now requested before foreground service starts."
} else {
    Write-Host "Pattern not found - no changes made. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

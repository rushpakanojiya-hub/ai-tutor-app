$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\liveclass\live_class_room_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

# --- Step 1: add the flutter_webrtc import if not already present ---
$importOld = "import 'package:livekit_client/livekit_client.dart' as lk;"
$importNew = "import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;`nimport 'package:livekit_client/livekit_client.dart' as lk;"
if ($content.Contains($importOld) -and -not $content.Contains("package:flutter_webrtc/flutter_webrtc.dart")) {
    $content = $content.Replace($importOld, $importNew)
    Write-Host "Import added."
} else {
    Write-Host "Import: already present or anchor not found - skipped."
}

# --- Step 2: replace _toggleScreenShare with the correct sequence ---
$old = @'
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

$new = @'
  Future<void> _toggleScreenShare() async {
    if (_screenShareBusy) return; // ignore taps while a toggle is in flight
    _screenShareBusy = true;
    try {
      final newState = !_screenSharing;

      if (newState) {
        // The LiveKit-documented, Android-verified correct sequence:
        // https://docs.livekit.io/transport/media/screenshare/ -
        // "Before starting the background service and enabling screen
        // share, you MUST call Helper.requestCapturePermission() from
        // flutter_webrtc, and only proceed if it returns true."
        //
        // Calling setScreenShareEnabled() directly (without this step)
        // bundles "ask permission" and "start capturing" into one native
        // call - flutter_webrtc's getDisplayMedia() calls
        // MediaProjectionManager.getMediaProjection() immediately after
        // the permission dialog closes, which crashes with
        // "Media projections require a foreground service of type
        // ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION" because
        // our foreground service isn't running yet at that instant.
        //
        // Correct order: request permission only (Helper) -> start our
        // foreground service -> THEN call setScreenShareEnabled, which
        // now succeeds because both Android requirements (permission
        // granted, service running) are already satisfied.
        final granted = await webrtc.Helper.requestCapturePermission();
        if (!granted) {
          _showToast('Screen recording permission is required to share your screen.');
          return;
        }

        await _screenShareChannel.invokeMethod('startScreenShareService');
        await Future.delayed(const Duration(milliseconds: 300));
        await _room.localParticipant?.setScreenShareEnabled(true);
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
    Write-Host "_toggleScreenShare fixed with the correct permission-first sequence."
} else {
    Write-Host "Pattern not found for _toggleScreenShare - no changes made there. Please tell Claude."
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

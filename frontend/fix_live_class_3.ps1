$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\liveclass\live_class_room_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$fixes = @(
    @{
        old = "  Future<void> _toggleLockRoom() async {`n    try {`n      if (!_roomLocked) {`n        await _classService.lockRoom(widget.classId);`n      } else {`n        await _classService.unlockRoom(widget.classId);`n      }`n      setState(() => _roomLocked = !_roomLocked);`n    } catch (e) {`n      _showToast('Failed to update room lock');`n    }`n  }"
        new = "  Future<void> _toggleLockRoom() async {`n    try {`n      if (!_roomLocked) {`n        await _classService.lockRoom(widget.classId);`n      } else {`n        await _classService.unlockRoom(widget.classId);`n      }`n      if (mounted) setState(() => _roomLocked = !_roomLocked);`n    } catch (e) {`n      _showToast('Failed to update room lock');`n    }`n  }"
        name = "_toggleLockRoom"
    },
    @{
        old = "  Future<void> _toggleSpeakerphone() async {`n    final newState = !_speakerphoneOn;`n    try {`n      await lk.Hardware.instance.setSpeakerphoneOn(newState);`n      setState(() => _speakerphoneOn = newState);`n    } catch (e) {`n      _showToast('Could not change audio output on this device.');`n    }`n  }"
        new = "  Future<void> _toggleSpeakerphone() async {`n    final newState = !_speakerphoneOn;`n    try {`n      await lk.Hardware.instance.setSpeakerphoneOn(newState);`n      if (mounted) setState(() => _speakerphoneOn = newState);`n    } catch (e) {`n      _showToast('Could not change audio output on this device.');`n    }`n  }"
        name = "_toggleSpeakerphone"
    },
    @{
        old = "  Future<void> _toggleMic() async {`n    final newState = !_micEnabled;`n    await _room.localParticipant?.setMicrophoneEnabled(newState);`n    setState(() => _micEnabled = newState);`n  }"
        new = "  Future<void> _toggleMic() async {`n    final newState = !_micEnabled;`n    await _room.localParticipant?.setMicrophoneEnabled(newState);`n    if (mounted) setState(() => _micEnabled = newState);`n  }"
        name = "_toggleMic"
    },
    @{
        old = "  Future<void> _toggleCamera() async {`n    final newState = !_cameraEnabled;`n    await _room.localParticipant?.setCameraEnabled(newState);`n    setState(() => _cameraEnabled = newState);`n  }"
        new = "  Future<void> _toggleCamera() async {`n    final newState = !_cameraEnabled;`n    await _room.localParticipant?.setCameraEnabled(newState);`n    if (mounted) setState(() => _cameraEnabled = newState);`n  }"
        name = "_toggleCamera"
    }
)

foreach ($fix in $fixes) {
    if ($content.Contains($fix.old)) {
        $content = $content.Replace($fix.old, $fix.new)
        Write-Host "Fixed $($fix.name)"
    } else {
        Write-Host "$($fix.name): pattern not found - skipped"
    }
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

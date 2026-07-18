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
        old = "  Future<void> _acceptHand(String identity) async {`n    await _publish({'type': 'hand_accepted', 'identity': identity});`n    setState(() => _raisedHandsAt.remove(identity));`n  }"
        new = "  Future<void> _acceptHand(String identity) async {`n    await _publish({'type': 'hand_accepted', 'identity': identity});`n    if (mounted) setState(() => _raisedHandsAt.remove(identity));`n  }"
        name = "_acceptHand"
    },
    @{
        old = "  Future<void> _lowerHand(String identity) async {`n    await _publish({'type': 'hand_lowered_by_teacher', 'identity': identity});`n    setState(() => _raisedHandsAt.remove(identity));`n  }"
        new = "  Future<void> _lowerHand(String identity) async {`n    await _publish({'type': 'hand_lowered_by_teacher', 'identity': identity});`n    if (mounted) setState(() => _raisedHandsAt.remove(identity));`n  }"
        name = "_lowerHand"
    },
    @{
        old = "  Future<void> _clearAllHands() async {`n    await _publish({'type': 'hands_cleared', 'identity': _room.localParticipant?.identity ?? ''});`n    setState(() => _raisedHandsAt.clear());`n  }"
        new = "  Future<void> _clearAllHands() async {`n    await _publish({'type': 'hands_cleared', 'identity': _room.localParticipant?.identity ?? ''});`n    if (mounted) setState(() => _raisedHandsAt.clear());`n  }"
        name = "_clearAllHands"
    }
)

foreach ($fix in $fixes) {
    if ($content.Contains($fix.old)) {
        $content = $content.Replace($fix.old, $fix.new)
        Write-Host "Fixed $($fix.name)"
    } else {
        Write-Host "$($fix.name): pattern not found - skipped (may already be fixed)"
    }
}

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

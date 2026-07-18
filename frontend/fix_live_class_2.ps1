$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "lib\screens\liveclass\live_class_room_screen.dart"

if (-not (Test-Path $path)) {
    Write-Host "ERROR: File not found at $path"
    exit 1
}

$raw = [System.IO.File]::ReadAllText($path)
$content = $raw -replace "`r`n", "`n"
$originalContent = $content

$old1 = "      setState(() => _resources = [resource, ..._resources]);`n      await _publish({'type': 'resource_shared', 'identity': _room.localParticipant?.identity ?? '', 'name': resource.fileName});"
$new1 = "      if (mounted) setState(() => _resources = [resource, ..._resources]);`n      await _publish({'type': 'resource_shared', 'identity': _room.localParticipant?.identity ?? '', 'name': resource.fileName});"
if ($content.Contains($old1)) { $content = $content.Replace($old1, $new1); Write-Host "Fixed _uploadResource" } else { Write-Host "_uploadResource: pattern not found - skipped" }

$old2 = "  Future<void> _deleteResource(ClassResourceModel resource) async {`n    try {`n      await _classService.deleteResource(widget.classId, resource.id);`n      setState(() => _resources.removeWhere((r) => r.id == resource.id));`n    } catch (e) {`n      _showToast('Failed to delete file.');`n    }`n  }"
$new2 = "  Future<void> _deleteResource(ClassResourceModel resource) async {`n    try {`n      await _classService.deleteResource(widget.classId, resource.id);`n      if (mounted) setState(() => _resources.removeWhere((r) => r.id == resource.id));`n    } catch (e) {`n      _showToast('Failed to delete file.');`n    }`n  }"
if ($content.Contains($old2)) { $content = $content.Replace($old2, $new2); Write-Host "Fixed _deleteResource" } else { Write-Host "_deleteResource: pattern not found - skipped" }

if ($content -ne $originalContent) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
    Write-Host "File saved."
} else {
    Write-Host "Nothing to save."
}

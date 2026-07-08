import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';

/// Real video call screen backed by LiveKit. Handles connect, local
/// camera/mic preview, rendering remote participants in a grid, mute/
/// camera toggles, and leave/end. This is the first integration pass -
/// screen share, whiteboard, chat, and raise-hand are NOT included here
/// (separate future phases per the agreed scope).
class LiveClassRoomScreen extends StatefulWidget {
  final String url;
  final String token;
  final String classTitle;
  final bool isTeacher;
  final Future<void> Function()? onEndClass; // teacher only - calls the End API

  const LiveClassRoomScreen({
    super.key,
    required this.url,
    required this.token,
    required this.classTitle,
    required this.isTeacher,
    this.onEndClass,
  });

  @override
  State<LiveClassRoomScreen> createState() => _LiveClassRoomScreenState();
}

class _LiveClassRoomScreenState extends State<LiveClassRoomScreen> {
  late final lk.Room _room;
  lk.EventsListener<lk.RoomEvent>? _listener;

  bool _connecting = true;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _switchingCamera = false;
  lk.CameraPosition _cameraPosition = lk.CameraPosition.front;
  String? _error;

  @override
  void initState() {
    super.initState();
    _room = lk.Room();
    _connect();
  }

  Timer? _fallbackRebuildTimer;

  Future<void> _connect() async {
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();
      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
      if (!cameraGranted || !micGranted) {
        if (mounted) setState(() {
          _connecting = false;
          _error = 'Camera and microphone access are required to join a live class. Please allow them in your device settings.';
        });
        return;
      }

      _listener = _room.createListener();
      _listener!
        ..on<lk.ParticipantConnectedEvent>((_) => setState(() {}))
        ..on<lk.ParticipantDisconnectedEvent>((_) => setState(() {}))
        ..on<lk.TrackSubscribedEvent>((_) => setState(() {}))
        ..on<lk.TrackUnsubscribedEvent>((_) => setState(() {}))
        ..on<lk.TrackPublishedEvent>((_) => setState(() {}))
        ..on<lk.TrackUnpublishedEvent>((_) => setState(() {}))
        ..on<lk.TrackMutedEvent>((_) => setState(() {}))
        ..on<lk.TrackUnmutedEvent>((_) => setState(() {}))
        ..on<lk.LocalTrackPublishedEvent>((_) => setState(() {}))
        ..on<lk.LocalTrackUnpublishedEvent>((_) => setState(() {}))
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (mounted) Navigator.of(context).pop();
        });

      // Belt-and-suspenders: some track state transitions don't fire a
      // dedicated event on every SDK version - a light periodic rebuild
      // guarantees the UI (camera-on/off placeholder in particular) never
      // gets stuck showing a stale frame.
      _fallbackRebuildTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });

      await _room.connect(
        widget.url,
        widget.token,
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      await _room.localParticipant?.setCameraEnabled(true);
      await _room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) setState(() => _connecting = false);
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[LiveClassRoom] Connection failed: $e');
      // ignore: avoid_print
      print(stackTrace);
      if (mounted) setState(() {
        _connecting = false;
        _error = 'Could not connect to the class. Please check your connection and try again.';
      });
    }
  }

  Future<void> _toggleMic() async {
    final newState = !_micEnabled;
    await _room.localParticipant?.setMicrophoneEnabled(newState);
    setState(() => _micEnabled = newState);
  }

  Future<void> _toggleCamera() async {
    final newState = !_cameraEnabled;
    await _room.localParticipant?.setCameraEnabled(newState);
    setState(() => _cameraEnabled = newState);
  }

  Future<void> _switchCamera() async {
    if (!_cameraEnabled || _switchingCamera) return;
    setState(() => _switchingCamera = true);
    try {
      final newPosition = _cameraPosition == lk.CameraPosition.front ? lk.CameraPosition.back : lk.CameraPosition.front;
      final pubs = _room.localParticipant?.videoTrackPublications ?? [];
      for (final pub in pubs) {
        final track = pub.track;
        if (track is lk.LocalVideoTrack) {
          await track.setCameraPosition(newPosition);
          _cameraPosition = newPosition;
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not switch camera on this device.')));
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.isTeacher ? 'End class for everyone?' : 'Leave class?'),
        content: Text(widget.isTeacher ? 'This will disconnect all students.' : 'You can rejoin while the class is still live.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.isTeacher ? 'End Class' : 'Leave', style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _room.disconnect();
    if (widget.isTeacher && widget.onEndClass != null) {
      await widget.onEndClass!();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _fallbackRebuildTimer?.cancel();
    _listener?.dispose();
    _room.dispose();
    super.dispose();
  }

  lk.VideoTrack? _videoTrackOf(lk.Participant participant) {
    for (final pub in participant.videoTrackPublications) {
      final track = pub.track;
      if (track is lk.VideoTrack && !pub.muted) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
              ],
            ),
          ),
        ),
      );
    }

    final remoteParticipants = _room.remoteParticipants.values.toList();
    final localParticipant = _room.localParticipant;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.classTitle, overflow: TextOverflow.ellipsis),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: remoteParticipants.isEmpty
                ? const Center(child: Text('Waiting for others to join...', style: TextStyle(color: Colors.white70)))
                : GridView.count(
                    crossAxisCount: remoteParticipants.length > 1 ? 2 : 1,
                    padding: const EdgeInsets.all(8),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: remoteParticipants.map((p) => _participantTile(p, isLocal: false)).toList(),
                  ),
          ),
          if (localParticipant != null)
            Container(
              height: 130,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 100, child: _participantTile(localParticipant, isLocal: true)),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Colors.grey.shade900,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _controlButton(_micEnabled ? Icons.mic : Icons.mic_off, _micEnabled ? Colors.white24 : AppColors.error, _toggleMic),
                const SizedBox(width: 16),
                _controlButton(_cameraEnabled ? Icons.videocam : Icons.videocam_off, _cameraEnabled ? Colors.white24 : AppColors.error, _toggleCamera),
                const SizedBox(width: 16),
                _controlButton(Icons.cameraswitch_rounded, _cameraEnabled ? Colors.white24 : Colors.white10, _cameraEnabled ? _switchCamera : () {}),
                const SizedBox(width: 16),
                _controlButton(Icons.call_end, AppColors.error, _leave),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, Color bg, VoidCallback onTap) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: Icon(icon, color: Colors.white)),
      ),
    );
  }

  Widget _participantTile(lk.Participant participant, {required bool isLocal}) {
    final videoTrack = _videoTrackOf(participant);
    final displayName = participant.name.isNotEmpty ? participant.name : participant.identity;
    final isTeacherRole = participant.identity.startsWith('teacher-');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Container(
      // Keying on identity + whether video is currently present forces
      // Flutter to fully dispose the old renderer widget (and its native
      // texture) instead of trying to update it in place - this is what
      // actually fixes the "last frame freezes" bug, not just re-querying
      // the track on every build.
      key: ValueKey('${participant.identity}-${videoTrack != null}'),
      decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            lk.VideoTrackRenderer(videoTrack)
          else
            Container(
              color: Colors.grey.shade800,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.purple,
                      child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(isTeacherRole ? 'Teacher' : 'Student', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_rounded, color: Colors.white.withOpacity(0.5), size: 14),
                        const SizedBox(width: 4),
                        Text('Camera Off', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
}

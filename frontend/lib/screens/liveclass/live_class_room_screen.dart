import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../services/live_class_service.dart';

/// Real video call screen backed by LiveKit - redesigned this round to
/// look like a modern classroom (Zoom/Meet-style): one large primary
/// video, a floating draggable self-view, a minimal 4-button toolbar
/// with a "More" sheet for secondary actions, and slide-up panels for
/// Participants/Chat instead of a fixed side column.
///
/// IMPORTANT: this is a UI-only pass. Every existing method, event
/// listener, and backend call below is untouched - only how they're
/// triggered/displayed changed. Attachments/Settings aren't wired to any
/// real feature yet, so they're intentionally left out of the More menu
/// rather than added as dead buttons.
class LiveClassRoomScreen extends StatefulWidget {
  final int classId;
  final String url;
  final String token;
  final String classTitle;
  final bool isTeacher;
  final String subjectName; // display-only, for the redesigned waiting state
  final String lessonTitle; // display-only, for the redesigned waiting state
  final Future<void> Function()? onEndClass; // teacher only - calls the End API

  const LiveClassRoomScreen({
    super.key,
    required this.classId,
    required this.url,
    required this.token,
    required this.classTitle,
    required this.isTeacher,
    this.subjectName = '',
    this.lessonTitle = '',
    this.onEndClass,
  });

  @override
  State<LiveClassRoomScreen> createState() => _LiveClassRoomScreenState();
}

class _ChatMessage {
  final String identity;
  final String name;
  final String text;
  final DateTime time;
  _ChatMessage({required this.identity, required this.name, required this.text, required this.time});
}

enum _SidePanel { none, chat, participants }

class _LiveClassRoomScreenState extends State<LiveClassRoomScreen> with SingleTickerProviderStateMixin {
  late final lk.Room _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final LiveClassService _classService = LiveClassService();

  bool _connecting = true;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _switchingCamera = false;
  lk.CameraPosition _cameraPosition = lk.CameraPosition.front;
  String? _error;

  bool _speakerView = true; // redesign default: one large focused tile, not a grid
  bool _speakerphoneOn = true;
  bool _roomLocked = false;

  Timer? _fallbackRebuildTimer;

  Set<String> _activeSpeakerIdentities = {};
  final Map<String, lk.ConnectionQuality> _connectionQuality = {};
  final List<_ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;
  final Set<String> _raisedHands = {};
  bool _localHandRaised = false;
  _SidePanel _sidePanel = _SidePanel.none;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // Draggable floating self-view position (top-left offset), redesign-only.
  Offset _pipOffset = const Offset(16, 90);

  @override
  void initState() {
    super.initState();
    _room = lk.Room();
    _connect();
  }

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
        ..on<lk.ActiveSpeakersChangedEvent>((event) {
          setState(() => _activeSpeakerIdentities = event.speakers.map((p) => p.identity).toSet());
        })
        ..on<lk.ParticipantConnectionQualityUpdatedEvent>((event) {
          setState(() => _connectionQuality[event.participant.identity] = event.connectionQuality);
        })
        ..on<lk.DataReceivedEvent>((event) => _handleDataReceived(event))
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

  // --- Chat + Raise Hand (LiveKit data channel - not persisted) ---

  void _handleDataReceived(lk.DataReceivedEvent event) {
    try {
      final decoded = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final identity = decoded['identity'] as String? ?? '';
      final localIdentity = _room.localParticipant?.identity ?? '';

      if (type == 'chat') {
        if (identity == localIdentity) return;
        setState(() {
          _chatMessages.add(_ChatMessage(
            identity: identity,
            name: decoded['name'] as String? ?? 'Unknown',
            text: decoded['text'] as String? ?? '',
            time: DateTime.tryParse(decoded['ts'] as String? ?? '') ?? DateTime.now(),
          ));
          if (_sidePanel != _SidePanel.chat) _unreadChatCount++;
        });
        _scrollChatToBottom();
      } else if (type == 'raise_hand') {
        final raised = decoded['raised'] as bool? ?? false;
        setState(() {
          if (raised) {
            _raisedHands.add(identity);
          } else {
            _raisedHands.remove(identity);
          }
        });
      }
    } catch (_) {
      // Ignore malformed data messages from other clients/versions.
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(_chatScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final local = _room.localParticipant;
    final identity = local?.identity ?? '';
    final name = local?.name.isNotEmpty == true ? local!.name : identity;

    setState(() {
      _chatMessages.add(_ChatMessage(identity: identity, name: name, text: text, time: DateTime.now()));
    });
    _chatController.clear();
    _scrollChatToBottom();

    final payload = jsonEncode({'type': 'chat', 'identity': identity, 'name': name, 'text': text, 'ts': DateTime.now().toIso8601String()});
    try {
      await local?.publishData(utf8.encode(payload));
    } catch (_) {}
  }

  Future<void> _toggleRaiseHand() async {
    final local = _room.localParticipant;
    final identity = local?.identity ?? '';
    final name = local?.name.isNotEmpty == true ? local!.name : identity;
    final newState = !_localHandRaised;

    setState(() {
      _localHandRaised = newState;
      if (newState) {
        _raisedHands.add(identity);
      } else {
        _raisedHands.remove(identity);
      }
    });

    final payload = jsonEncode({'type': 'raise_hand', 'identity': identity, 'name': name, 'raised': newState});
    try {
      await local?.publishData(utf8.encode(payload));
    } catch (_) {}
  }

  void _openPanel(_SidePanel panel) {
    setState(() {
      _sidePanel = _sidePanel == panel ? _SidePanel.none : panel;
      if (_sidePanel == _SidePanel.chat) _unreadChatCount = 0;
    });
  }

  // --- Teacher moderation (calls the existing admin API - unchanged) ---

  Future<void> _muteParticipant(String identity) async {
    try {
      await _classService.muteParticipant(widget.classId, identity);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Participant muted.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to mute participant.')));
    }
  }

  Future<void> _removeParticipant(String identity, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove participant?'),
        content: Text('$name will be disconnected from the class.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _classService.removeParticipant(widget.classId, identity);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove participant.')));
    }
  }

  Future<void> _muteAll() async {
    try {
      await _classService.muteAll(widget.classId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All participants muted.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to mute all.')));
    }
  }

  Future<void> _toggleLockRoom() async {
    try {
      if (!_roomLocked) {
        await _classService.lockRoom(widget.classId);
      } else {
        await _classService.unlockRoom(widget.classId);
      }
      setState(() => _roomLocked = !_roomLocked);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update room lock.')));
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            _moreMenuTile(Icons.people_alt_rounded, 'Participants', () {
              Navigator.pop(context);
              _openPanel(_SidePanel.participants);
            }, badge: (_room.remoteParticipants.length + 1)),
            _moreMenuTile(Icons.chat_bubble_rounded, 'Chat', () {
              Navigator.pop(context);
              _openPanel(_SidePanel.chat);
            }, badge: _unreadChatCount),
            _moreMenuTile(_localHandRaised ? Icons.back_hand_rounded : Icons.back_hand_outlined, _localHandRaised ? 'Lower Hand' : 'Raise Hand', () {
              Navigator.pop(context);
              _toggleRaiseHand();
            }, highlighted: _localHandRaised),
            _moreMenuTile(Icons.cameraswitch_rounded, 'Switch Camera', _cameraEnabled ? () {
              Navigator.pop(context);
              _switchCamera();
            } : null),
            _moreMenuTile(_speakerphoneOn ? Icons.volume_up_rounded : Icons.hearing_rounded, _speakerphoneOn ? 'Speaker' : 'Earpiece', () {
              Navigator.pop(context);
              _toggleSpeakerphone();
            }),
            _moreMenuTile(_speakerView ? Icons.grid_view_rounded : Icons.view_agenda_rounded, _speakerView ? 'Grid View' : 'Speaker View', () {
              Navigator.pop(context);
              _toggleViewMode();
            }),
            if (widget.isTeacher) ...[
              const Divider(color: Colors.white12, height: 20),
              _moreMenuTile(Icons.mic_off_rounded, 'Mute All', () {
                Navigator.pop(context);
                _muteAll();
              }),
              _moreMenuTile(
                _roomLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                _roomLocked ? 'Unlock Room' : 'Lock Room',
                () {
                  Navigator.pop(context);
                  _toggleLockRoom();
                },
                subtitle: _roomLocked ? 'Allow new students to join' : 'Stop new students from joining',
                highlighted: _roomLocked,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _moreMenuTile(IconData icon, String title, VoidCallback? onTap, {String? subtitle, int badge = 0, bool highlighted = false}) {
    return ListTile(
      enabled: onTap != null,
      leading: Icon(icon, color: highlighted ? AppColors.orange : (onTap != null ? Colors.white70 : Colors.white24)),
      title: Text(title, style: TextStyle(color: onTap != null ? Colors.white : Colors.white24, fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)) : null,
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            )
          : null,
      onTap: onTap,
    );
  }

  void _toggleViewMode() => setState(() => _speakerView = !_speakerView);

  Future<void> _toggleSpeakerphone() async {
    final newState = !_speakerphoneOn;
    try {
      await lk.Hardware.instance.setSpeakerphoneOn(newState);
      setState(() => _speakerphoneOn = newState);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not change audio output on this device.')));
    }
  }

  // --- Camera / mic controls ---

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
    _chatController.dispose();
    _chatScrollController.dispose();
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

  bool _isMicOn(lk.Participant participant) {
    for (final pub in participant.audioTrackPublications) {
      if (!pub.muted) return true;
    }
    return false;
  }

  /// Picks who gets the big main tile: the teacher first (always the
  /// focus per the redesign brief), then whoever's currently speaking,
  /// then just the first remote participant.
  lk.RemoteParticipant? _primaryParticipant(List<lk.RemoteParticipant> remoteParticipants) {
    if (remoteParticipants.isEmpty) return null;
    final teacher = remoteParticipants.where((p) => p.identity.startsWith('teacher-')).toList();
    if (teacher.isNotEmpty) return teacher.first;
    final speaking = remoteParticipants.where((p) => _activeSpeakerIdentities.contains(p.identity)).toList();
    if (speaking.isNotEmpty) return speaking.first;
    return remoteParticipants.first;
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
    final List<lk.Participant> allParticipants = [if (localParticipant != null) localParticipant, ...remoteParticipants];
    final primary = _primaryParticipant(remoteParticipants);
    final others = remoteParticipants.where((p) => p.identity != primary?.identity).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // --- Main video area: fills almost the whole screen ---
            Positioned.fill(
              bottom: 84,
              child: remoteParticipants.isEmpty
                  ? _buildWaitingState()
                  : (_speakerView
                      ? _buildFocusedLayout(primary, others)
                      : GridView.count(
                          crossAxisCount: remoteParticipants.length > 1 ? 2 : 1,
                          padding: const EdgeInsets.all(8),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          children: remoteParticipants.map((p) => _participantTile(p)).toList(),
                        )),
            ),

            // --- Class title, minimal top bar ---
            Positioned(
              top: 4,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                      child: Text(widget.classTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),

            // --- Floating draggable self-view (picture-in-picture) ---
            if (localParticipant != null) _buildDraggablePip(localParticipant),

            // --- Minimal bottom toolbar ---
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildToolbar(),
            ),

            // --- Slide-up panel (Chat / Participants) ---
            _buildSlideUpPanel(allParticipants),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.purple,
                child: Text(
                  widget.classTitle.isNotEmpty ? widget.classTitle[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.classTitle, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            if (widget.subjectName.isNotEmpty || widget.lessonTitle.isNotEmpty)
              Text(
                [widget.subjectName, widget.lessonTitle].where((s) => s.isNotEmpty).join(' \u2022 '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
            const SizedBox(height: 14),
            const Text('Waiting for participants to join', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusedLayout(lk.RemoteParticipant? primary, List<lk.RemoteParticipant> others) {
    return Column(
      children: [
        Expanded(child: primary != null ? _participantTile(primary) : const SizedBox.shrink()),
        if (others.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox(width: 84, child: _participantTile(others[index])),
            ),
          ),
      ],
    );
  }

  Widget _buildDraggablePip(lk.LocalParticipant localParticipant) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 80),
      left: _pipOffset.dx,
      top: _pipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final size = MediaQuery.of(context).size;
            final newX = (_pipOffset.dx + details.delta.dx).clamp(0.0, size.width - 96);
            final newY = (_pipOffset.dy + details.delta.dy).clamp(0.0, size.height - 220);
            _pipOffset = Offset(newX, newY);
          });
        },
        child: SizedBox(
          width: 96,
          height: 128,
          child: _participantTile(localParticipant, isLocal: true),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toolbarButton(_micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded, _micEnabled ? Colors.white24 : AppColors.error, _toggleMic),
          const SizedBox(width: 22),
          _toolbarButton(_cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded, _cameraEnabled ? Colors.white24 : AppColors.error, _toggleCamera),
          const SizedBox(width: 22),
          _toolbarButton(Icons.call_end_rounded, AppColors.error, _leave, large: true),
          const SizedBox(width: 22),
          _badgedToolbarButton(Icons.more_horiz_rounded, Colors.white24, _showMoreMenu, badgeCount: _unreadChatCount + (widget.isTeacher ? _raisedHands.length : 0)),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, Color bg, VoidCallback onTap, {bool large = false}) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(large ? 16 : 14), child: Icon(icon, color: Colors.white, size: large ? 26 : 22)),
      ),
    );
  }

  Widget _badgedToolbarButton(IconData icon, Color bg, VoidCallback onTap, {int badgeCount = 0}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _toolbarButton(icon, bg, onTap),
        if (badgeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text('$badgeCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  // --- Slide-up panel (redesigned Chat/Participants - not a fixed side column) ---

  Widget _buildSlideUpPanel(List<lk.Participant> allParticipants) {
    final open = _sidePanel != _SidePanel.none;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: open ? 84 : -560,
      height: MediaQuery.of(context).size.height * 0.55,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 200) setState(() => _sidePanel = _SidePanel.none);
        },
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, -6))],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      _sidePanel == _SidePanel.chat ? 'Chat' : 'Participants (${allParticipants.length})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), onPressed: () => setState(() => _sidePanel = _SidePanel.none)),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(child: _sidePanel == _SidePanel.chat ? _buildChatPanel() : _buildParticipantsPanel(allParticipants)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel() {
    return Column(
      children: [
        Expanded(
          child: _chatMessages.isEmpty
              ? const Center(child: Text('No messages yet.', style: TextStyle(color: Colors.white38, fontSize: 12)))
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) {
                    final m = _chatMessages[index];
                    final isMe = m.identity == (_room.localParticipant?.identity ?? '');
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.purple : Colors.grey.shade800,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(m.name, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700))),
                            Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.grey.shade800,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.purple,
                  shape: const CircleBorder(),
                  child: InkWell(customBorder: const CircleBorder(), onTap: _sendChat, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.send_rounded, color: Colors.white, size: 20))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsPanel(List<lk.Participant> allParticipants) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: allParticipants.length,
      itemBuilder: (context, index) {
        final p = allParticipants[index];
        final isTeacherRole = p.identity.startsWith('teacher-');
        final isSelf = p.identity == (_room.localParticipant?.identity ?? '');
        final micOn = _isMicOn(p);
        final camOn = _videoTrackOf(p) != null;
        final handRaised = _raisedHands.contains(p.identity);
        final quality = _connectionQuality[p.identity];
        final canModerate = widget.isTeacher && !isSelf;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.purple,
            child: Text((p.name.isNotEmpty ? p.name[0] : '?').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          title: Text('${p.name.isNotEmpty ? p.name : p.identity}${isSelf ? ' (You)' : ''}', style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(isTeacherRole ? 'Teacher' : 'Student', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (handRaised) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.back_hand_rounded, color: AppColors.orange, size: 16)),
              Icon(_qualityIcon(quality), color: _qualityColor(quality), size: 16),
              const SizedBox(width: 6),
              Icon(micOn ? Icons.mic_rounded : Icons.mic_off_rounded, color: micOn ? Colors.white70 : AppColors.error, size: 16),
              const SizedBox(width: 6),
              Icon(camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, color: camOn ? Colors.white70 : AppColors.error, size: 16),
              if (canModerate)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18),
                  color: const Color(0xFF2C2C2E),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'mute', child: Text('Mute', style: TextStyle(color: Colors.white, fontSize: 13))),
                    const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                  onSelected: (value) {
                    if (value == 'mute') _muteParticipant(p.identity);
                    if (value == 'remove') _removeParticipant(p.identity, p.name.isNotEmpty ? p.name : p.identity);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _qualityIcon(lk.ConnectionQuality? q) {
    switch (q) {
      case lk.ConnectionQuality.excellent:
        return Icons.signal_cellular_alt_rounded;
      case lk.ConnectionQuality.good:
        return Icons.signal_cellular_alt_2_bar_rounded;
      case lk.ConnectionQuality.poor:
        return Icons.signal_cellular_alt_1_bar_rounded;
      default:
        return Icons.signal_cellular_connected_no_internet_0_bar_rounded;
    }
  }

  Color _qualityColor(lk.ConnectionQuality? q) {
    switch (q) {
      case lk.ConnectionQuality.excellent:
        return AppColors.green;
      case lk.ConnectionQuality.good:
        return AppColors.orange;
      case lk.ConnectionQuality.poor:
        return AppColors.error;
      default:
        return Colors.white38;
    }
  }

  Widget _participantTile(lk.Participant participant, {bool isLocal = false}) {
    final videoTrack = _videoTrackOf(participant);
    final displayName = participant.name.isNotEmpty ? participant.name : participant.identity;
    final isTeacherRole = participant.identity.startsWith('teacher-');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final isSpeaking = _activeSpeakerIdentities.contains(participant.identity);
    final handRaised = _raisedHands.contains(participant.identity);
    final quality = _connectionQuality[participant.identity];

    return Container(
      key: ValueKey('${participant.identity}-${videoTrack != null}'),
      margin: isLocal ? EdgeInsets.zero : const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(isLocal ? 14 : 16),
        border: isSpeaking ? Border.all(color: AppColors.green, width: 3) : Border.all(color: Colors.white10, width: 1),
        boxShadow: isSpeaking ? [BoxShadow(color: AppColors.green.withOpacity(0.5), blurRadius: 12, spreadRadius: 1)] : [const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
      ),
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
                      radius: isLocal ? 18 : 28,
                      backgroundColor: AppColors.purple,
                      child: Text(initial, style: TextStyle(color: Colors.white, fontSize: isLocal ? 14 : 22, fontWeight: FontWeight.w700)),
                    ),
                    if (!isLocal) ...[
                      const SizedBox(height: 8),
                      Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(isTeacherRole ? 'Teacher' : 'Student', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                    ],
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
              child: Text(isLocal ? 'You' : displayName, style: const TextStyle(color: Colors.white, fontSize: 10), overflow: TextOverflow.ellipsis),
            ),
          ),
          if (!isLocal)
            Positioned(right: 6, top: 6, child: Icon(_qualityIcon(quality), color: _qualityColor(quality), size: 16)),
          if (handRaised)
            Positioned(
              right: 6,
              top: isLocal ? 6 : 26,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                child: const Icon(Icons.back_hand_rounded, color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}

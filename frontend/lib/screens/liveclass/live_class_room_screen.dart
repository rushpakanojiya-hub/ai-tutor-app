import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../services/live_class_service.dart';

/// Real video call screen backed by LiveKit. Handles connect, local
/// camera/mic preview, rendering remote participants in a grid, mute/
/// camera toggles, leave/end, active-speaker highlighting, connection
/// quality, a participant list, raise-hand, and in-call chat.
///
/// Raise-hand and chat ride on LiveKit's built-in data channel
/// (publishData/DataReceivedEvent) rather than a new backend - so chat
/// history does NOT persist after the call ends. Teacher mute/remove,
/// mute-all, and lock-room are NOT included here - those need
/// server-side LiveKit admin API calls (a real backend addition),
/// deferred to a future round.
class LiveClassRoomScreen extends StatefulWidget {
  final int classId;
  final String url;
  final String token;
  final String classTitle;
  final bool isTeacher;
  final Future<void> Function()? onEndClass; // teacher only - calls the End API

  const LiveClassRoomScreen({
    super.key,
    required this.classId,
    required this.url,
    required this.token,
    required this.classTitle,
    required this.isTeacher,
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

class _LiveClassRoomScreenState extends State<LiveClassRoomScreen> {
  late final lk.Room _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final LiveClassService _classService = LiveClassService();

  bool _connecting = true;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _switchingCamera = false;
  lk.CameraPosition _cameraPosition = lk.CameraPosition.front;
  String? _error;

  // --- Speaker/Gallery view + audio output + room lock (this round) ---
  bool _speakerView = false;
  bool _speakerphoneOn = true;
  bool _roomLocked = false;

  Timer? _fallbackRebuildTimer;

  // --- New this round: active speaker / connection quality / chat / raise hand ---
  Set<String> _activeSpeakerIdentities = {};
  final Map<String, lk.ConnectionQuality> _connectionQuality = {};
  final List<_ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;
  final Set<String> _raisedHands = {};
  bool _localHandRaised = false;
  _SidePanel _sidePanel = _SidePanel.none;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

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
        if (identity == localIdentity) return; // we already appended our own message locally
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
    } catch (_) {
      // Message still shows locally even if the network send fails.
    }
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

  // --- Teacher moderation (server-side LiveKit admin API via our backend) ---

  Future<void> _muteParticipant(String identity) async {
    try {
      await _classService.muteParticipant(widget.classId, identity);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to mute all participants.')));
    }
  }

  Future<void> _toggleLockRoom() async {
    final newState = !_roomLocked;
    try {
      if (newState) {
        await _classService.lockRoom(widget.classId);
      } else {
        await _classService.unlockRoom(widget.classId);
      }
      setState(() => _roomLocked = newState);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newState ? 'Class locked - no new students can join.' : 'Class unlocked.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update lock status.')));
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mic_off_rounded, color: Colors.white70),
              title: const Text('Mute All', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _muteAll();
              },
            ),
            ListTile(
              leading: Icon(_roomLocked ? Icons.lock_open_rounded : Icons.lock_rounded, color: Colors.white70),
              title: Text(_roomLocked ? 'Unlock Room' : 'Lock Room', style: const TextStyle(color: Colors.white)),
              subtitle: Text(_roomLocked ? 'Allow new students to join' : 'Stop new students from joining', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _toggleLockRoom();
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- View mode + audio output ---

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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.classTitle, overflow: TextOverflow.ellipsis),
        automaticallyImplyLeading: false,
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: remoteParticipants.isEmpty
                      ? const Center(child: Text('Waiting for others to join...', style: TextStyle(color: Colors.white70)))
                      : _speakerView
                          ? _buildSpeakerView(remoteParticipants)
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: Colors.grey.shade900,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _controlButton(_micEnabled ? Icons.mic : Icons.mic_off, _micEnabled ? Colors.white24 : AppColors.error, _toggleMic),
                        const SizedBox(width: 10),
                        _controlButton(_cameraEnabled ? Icons.videocam : Icons.videocam_off, _cameraEnabled ? Colors.white24 : AppColors.error, _toggleCamera),
                        const SizedBox(width: 10),
                        _controlButton(Icons.cameraswitch_rounded, _cameraEnabled ? Colors.white24 : Colors.white10, _cameraEnabled ? _switchCamera : () {}),
                        const SizedBox(width: 10),
                        _badgedControlButton(
                          Icons.back_hand_rounded,
                          _localHandRaised ? AppColors.orange : Colors.white24,
                          _toggleRaiseHand,
                          badgeCount: widget.isTeacher ? _raisedHands.length : 0,
                        ),
                        const SizedBox(width: 10),
                        _badgedControlButton(Icons.chat_bubble_rounded, _sidePanel == _SidePanel.chat ? AppColors.purple : Colors.white24, () => _openPanel(_SidePanel.chat), badgeCount: _unreadChatCount),
                        const SizedBox(width: 10),
                        _badgedControlButton(Icons.people_alt_rounded, _sidePanel == _SidePanel.participants ? AppColors.purple : Colors.white24, () => _openPanel(_SidePanel.participants), badgeCount: allParticipants.length),
                        const SizedBox(width: 10),
                        _controlButton(_speakerView ? Icons.grid_view_rounded : Icons.view_carousel_rounded, Colors.white24, _toggleViewMode),
                        const SizedBox(width: 10),
                        _controlButton(_speakerphoneOn ? Icons.volume_up_rounded : Icons.hearing_rounded, Colors.white24, _toggleSpeakerphone),
                        if (widget.isTeacher) ...[
                          const SizedBox(width: 10),
                          _controlButton(Icons.more_vert_rounded, _roomLocked ? AppColors.orange : Colors.white24, _showMoreMenu),
                        ],
                        const SizedBox(width: 10),
                        _controlButton(Icons.call_end, AppColors.error, _leave),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_sidePanel != _SidePanel.none) _buildSidePanel(allParticipants),
        ],
      ),
    );
  }

  Widget _buildSidePanel(List<lk.Participant> allParticipants) {
    return Container(
      width: 280,
      color: Colors.grey.shade900,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(_sidePanel == _SidePanel.chat ? 'Chat' : 'Participants (${allParticipants.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 20), onPressed: () => setState(() => _sidePanel = _SidePanel.none)),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Expanded(child: _sidePanel == _SidePanel.chat ? _buildChatPanel() : _buildParticipantsPanel(allParticipants)),
          ],
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
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) {
                    final m = _chatMessages[index];
                    final isMe = m.identity == (_room.localParticipant?.identity ?? '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isMe ? 'You' : m.name, style: TextStyle(color: isMe ? AppColors.purpleLight : Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.purple), onPressed: _sendChat),
            ],
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
        final micOn = _isMicOn(p);
        final camOn = _videoTrackOf(p) != null;
        final handRaised = _raisedHands.contains(p.identity);
        final quality = _connectionQuality[p.identity];
        final isSelf = p.identity == (_room.localParticipant?.identity ?? '');
        final canModerate = widget.isTeacher && !isSelf;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.purple,
            child: Text((p.name.isNotEmpty ? p.name[0] : '?').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          title: Text(p.name.isNotEmpty ? p.name : p.identity, style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(isTeacherRole ? 'Teacher' : 'Student', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (handRaised) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.back_hand_rounded, color: AppColors.orange, size: 16)),
              Icon(_qualityIcon(quality), color: _qualityColor(quality), size: 16),
              const SizedBox(width: 6),
              Icon(micOn ? Icons.mic : Icons.mic_off, color: micOn ? Colors.white70 : AppColors.error, size: 16),
              const SizedBox(width: 6),
              Icon(camOn ? Icons.videocam : Icons.videocam_off, color: camOn ? Colors.white70 : AppColors.error, size: 16),
              if (canModerate)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 16),
                  color: Colors.grey.shade800,
                  onSelected: (value) {
                    if (value == 'mute') _muteParticipant(p.identity);
                    if (value == 'remove') _removeParticipant(p.identity, p.name.isNotEmpty ? p.name : p.identity);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'mute', child: Text('Mute', style: TextStyle(color: Colors.white))),
                    const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.error))),
                  ],
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

  Widget _buildSpeakerView(List<lk.RemoteParticipant> remoteParticipants) {
    // Feature whoever's currently speaking among remotes; fall back to
    // the first remote participant if no one is actively talking.
    lk.RemoteParticipant featured = remoteParticipants.first;
    for (final p in remoteParticipants) {
      if (_activeSpeakerIdentities.contains(p.identity)) {
        featured = p;
        break;
      }
    }
    final others = remoteParticipants.where((p) => p.identity != featured.identity).toList();

    return Column(
      children: [
        Expanded(child: Padding(padding: const EdgeInsets.all(8), child: _participantTile(featured, isLocal: false))),
        if (others.isNotEmpty)
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox(width: 90, child: _participantTile(others[index], isLocal: false)),
            ),
          ),
      ],
    );
  }

  Widget _controlButton(IconData icon, Color bg, VoidCallback onTap) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, color: Colors.white, size: 20)),
      ),
    );
  }

  Widget _badgedControlButton(IconData icon, Color bg, VoidCallback onTap, {int badgeCount = 0}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _controlButton(icon, bg, onTap),
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

  Widget _participantTile(lk.Participant participant, {required bool isLocal}) {
    final videoTrack = _videoTrackOf(participant);
    final displayName = participant.name.isNotEmpty ? participant.name : participant.identity;
    final isTeacherRole = participant.identity.startsWith('teacher-');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final isSpeaking = _activeSpeakerIdentities.contains(participant.identity);
    final handRaised = _raisedHands.contains(participant.identity);
    final quality = _connectionQuality[participant.identity];

    return Container(
      // Keying on identity + whether video is currently present forces
      // Flutter to fully dispose the old renderer widget (and its native
      // texture) instead of trying to update it in place - this is what
      // actually fixes the "last frame freezes" bug, not just re-querying
      // the track on every build.
      key: ValueKey('${participant.identity}-${videoTrack != null}'),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: isSpeaking ? Border.all(color: AppColors.green, width: 3) : null,
        boxShadow: isSpeaking ? [BoxShadow(color: AppColors.green.withOpacity(0.5), blurRadius: 12, spreadRadius: 1)] : null,
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
          Positioned(
            right: 6,
            top: 6,
            child: Icon(_qualityIcon(quality), color: _qualityColor(quality), size: 16),
          ),
          if (handRaised)
            Positioned(
              right: 6,
              top: 26,
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

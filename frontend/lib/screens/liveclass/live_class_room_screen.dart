import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../models/assignment_model.dart';
import '../../models/live_class_model.dart';
import '../../services/assignment_service.dart';
import '../../services/live_class_service.dart';
import '../assignments/assignment_detail_screen.dart';
import 'resource_pdf_viewer_screen.dart';
import 'resource_image_viewer_screen.dart';
import 'resource_video_viewer_screen.dart';

/// Real video call screen backed by LiveKit - modern classroom UI with
/// full-screen primary video, floating draggable self-view, a minimal
/// toolbar + More menu, slide-up panels (Chat/Participants/Raised Hands/
/// Class Info/Attachments), pinned announcements, and in-meeting toasts.
///
/// Chat, announcements, and raise-hand all ride on LiveKit's data channel
/// (publishData/DataReceivedEvent) - no new backend, so none of it
/// persists after the call ends. Attachments reuses the EXISTING
/// AssignmentService (real data, no new backend). Message "Sent" only
/// means it was published locally - there's no delivery-receipt protocol
/// over a data channel, so no "Delivered"/"Read" state is shown (that
/// would be dishonest without a real ack mechanism).
class LiveClassRoomScreen extends StatefulWidget {
  final int classId;
  final String url;
  final String token;
  final String classTitle;
  final bool isTeacher;
  final String subjectName;
  final String lessonTitle;
  final String description;
  final int? subjectId;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final Future<void> Function()? onEndClass;

  const LiveClassRoomScreen({
    super.key,
    required this.classId,
    required this.url,
    required this.token,
    required this.classTitle,
    required this.isTeacher,
    this.subjectName = '',
    this.lessonTitle = '',
    this.description = '',
    this.subjectId,
    this.scheduledStart,
    this.scheduledEnd,
    this.onEndClass,
  });

  @override
  State<LiveClassRoomScreen> createState() => _LiveClassRoomScreenState();
}

class _ChatMessage {
  final String id;
  final String identity;
  final String name;
  final String text;
  final DateTime time;
  final bool isTeacher;
  _ChatMessage({required this.id, required this.identity, required this.name, required this.text, required this.time, required this.isTeacher});
}

class _Announcement {
  final String id;
  final String text;
  final String teacherName;
  final DateTime time;
  _Announcement({required this.id, required this.text, required this.teacherName, required this.time});
}

enum _SidePanel { none, chat, participants, raiseQueue, classInfo, attachments }

class _Stroke {
  final String id;
  final List<Offset> points;
  final Color color;
  final double width;
  _Stroke({required this.id, required this.points, required this.color, required this.width});
}

class _LiveClassRoomScreenState extends State<LiveClassRoomScreen> {
  late final lk.Room _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final LiveClassService _classService = LiveClassService();
  final AssignmentService _assignmentService = AssignmentService();

  bool _connecting = true;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _switchingCamera = false;
  lk.CameraPosition _cameraPosition = lk.CameraPosition.front;
  String? _error;

  bool _speakerView = true;
  bool _speakerphoneOn = true;
  bool _roomLocked = false;

  // Teacher Pin Mode (default ON - teacher is always the large video until
  // they manually unpin), Spotlight (teacher highlights a specific
  // student, overrides pin), and tap-to-highlight (only takes effect when
  // not pinned/spotlighted).
  bool _teacherPinned = true;
  String? _spotlightIdentity;
  String? _manualPrimaryIdentity;

  // Screen share: uses LiveKit's built-in screen capture - no backend
  // needed, it's just another video track on the same room/token.
  bool _screenSharing = false;

  // Whiteboard: strokes ride on the LiveKit data channel (like chat) -
  // ephemeral, resets when the call ends, and doesn't sync to students
  // who join mid-drawing (they see it fill in from that point on).
  bool _whiteboardOpen = false;
  final List<_Stroke> _whiteboardStrokes = [];
  List<Offset> _currentStrokePoints = [];
  Color _whiteboardColor = Colors.red;
  double _whiteboardStrokeWidth = 4;

  Timer? _fallbackRebuildTimer;
  Timer? _endingSoonTimer;
  bool _endingSoonNotified = false;

  Set<String> _activeSpeakerIdentities = {};
  final Map<String, lk.ConnectionQuality> _connectionQuality = {};

  int _msgCounter = 0;
  final List<_ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;
  bool _chatSearchOpen = false;
  final TextEditingController _chatSearchController = TextEditingController();

  final List<_Announcement> _announcements = [];

  // identity -> time raised (queue order + "raised Xm ago" display)
  final Map<String, DateTime> _raisedHandsAt = {};
  bool _localHandRaised = false;

  _SidePanel _sidePanel = _SidePanel.none;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  List<AssignmentModel> _attachments = [];
  List<ClassResourceModel> _resources = [];
  bool _loadingAttachments = false;
  bool _uploadingResource = false;
  double _uploadProgress = 0;
  String? _attachmentsError;

  Offset _pipOffset = const Offset(16, 90);

  @override
  void initState() {
    super.initState();
    _room = lk.Room();
    _connect();
    _startEndingSoonWatcher();
  }

  void _startEndingSoonWatcher() {
    if (widget.scheduledEnd == null) return;
    _endingSoonTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_endingSoonNotified) return;
      final remaining = widget.scheduledEnd!.difference(DateTime.now());
      if (remaining.inMinutes <= 5 && remaining.inSeconds > 0) {
        _endingSoonNotified = true;
        _showToast('Class ending in about ${remaining.inMinutes} minute${remaining.inMinutes == 1 ? '' : 's'}');
      }
    });
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
        ..on<lk.ParticipantConnectedEvent>((event) {
          setState(() {});
          _showToast('${event.participant.name.isNotEmpty ? event.participant.name : event.participant.identity} joined');
        })
        ..on<lk.ParticipantDisconnectedEvent>((event) {
          setState(() {
            if (_spotlightIdentity == event.participant.identity) _spotlightIdentity = null;
            if (_manualPrimaryIdentity == event.participant.identity) _manualPrimaryIdentity = null;
          });
          _showToast('${event.participant.name.isNotEmpty ? event.participant.name : event.participant.identity} left');
        })
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
          // Auto Exit: a single pop() could land on an intermediate
          // screen (e.g. the Waiting Room) instead of the Live Classes
          // list. Popping all the way back to the first route in this
          // flow guarantees the student always lands back on Live
          // Classes automatically, whether the teacher ended the class
          // or the connection simply dropped.
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });

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

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey.shade900,
        margin: const EdgeInsets.only(bottom: 100, left: 60, right: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  String _newMsgId() {
    _msgCounter++;
    final identity = _room.localParticipant?.identity ?? 'local';
    return '$identity-${DateTime.now().millisecondsSinceEpoch}-$_msgCounter';
  }

  // --- Data channel: chat, delete, announcements, raise hand ---

  void _handleDataReceived(lk.DataReceivedEvent event) {
    try {
      final decoded = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final identity = decoded['identity'] as String? ?? '';
      final localIdentity = _room.localParticipant?.identity ?? '';

      switch (type) {
        case 'chat':
          if (identity == localIdentity) return;
          setState(() {
            _chatMessages.add(_ChatMessage(
              id: decoded['id'] as String? ?? _newMsgId(),
              identity: identity,
              name: decoded['name'] as String? ?? 'Unknown',
              text: decoded['text'] as String? ?? '',
              time: DateTime.tryParse(decoded['ts'] as String? ?? '') ?? DateTime.now(),
              isTeacher: identity.startsWith('teacher-'),
            ));
            if (_sidePanel != _SidePanel.chat) _unreadChatCount++;
          });
          _scrollChatToBottom();
          break;

        case 'chat_delete':
          final msgId = decoded['id'] as String? ?? '';
          setState(() => _chatMessages.removeWhere((m) => m.id == msgId));
          break;

        case 'announcement':
          setState(() {
            _announcements.add(_Announcement(
              id: decoded['id'] as String? ?? _newMsgId(),
              text: decoded['text'] as String? ?? '',
              teacherName: decoded['name'] as String? ?? 'Teacher',
              time: DateTime.now(),
            ));
          });
          _showToast('\u{1F4E2} New announcement');
          break;

        case 'announcement_remove':
          final annId = decoded['id'] as String? ?? '';
          setState(() => _announcements.removeWhere((a) => a.id == annId));
          break;

        case 'raise_hand':
          final raised = decoded['raised'] as bool? ?? false;
          setState(() {
            if (raised) {
              _raisedHandsAt[identity] = DateTime.now();
              if (widget.isTeacher) _showToast('${decoded['name'] as String? ?? 'A student'} raised their hand');
            } else {
              _raisedHandsAt.remove(identity);
            }
          });
          break;

        case 'hand_lowered_by_teacher':
          // Sent by the teacher targeting a specific student's identity.
          if (identity == localIdentity) {
            setState(() => _localHandRaised = false);
            _showToast('The teacher lowered your hand');
          }
          setState(() => _raisedHandsAt.remove(identity));
          break;

        case 'hand_accepted':
          if (identity == localIdentity) _showToast('The teacher acknowledged your raised hand');
          break;

        case 'hands_cleared':
          setState(() {
            _raisedHandsAt.clear();
            _localHandRaised = false;
          });
          break;

        case 'whiteboard_open':
          setState(() => _whiteboardOpen = true);
          break;

        case 'whiteboard_close':
          setState(() => _whiteboardOpen = false);
          break;

        case 'whiteboard_stroke':
          final pointsRaw = decoded['points'] as List<dynamic>? ?? [];
          setState(() {
            _whiteboardStrokes.add(_Stroke(
              id: decoded['id'] as String? ?? _newMsgId(),
              points: pointsRaw.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList(),
              color: Color(decoded['color'] as int? ?? Colors.red.value),
              width: (decoded['width'] as num?)?.toDouble() ?? 4,
            ));
          });
          break;

        case 'whiteboard_clear':
          setState(() => _whiteboardStrokes.clear());
          break;

        case 'whiteboard_undo':
          setState(() {
            if (_whiteboardStrokes.isNotEmpty) _whiteboardStrokes.removeLast();
          });
          break;

        case 'resource_shared':
          if (identity != localIdentity) {
            _showToast('\u{1F4CE} ${decoded['name'] as String? ?? 'A file'} was shared');
          }
          break;
      }
    } catch (_) {
      // Ignore malformed/unknown data messages from other clients/versions.
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(_chatScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _publish(Map<String, dynamic> payload) async {
    try {
      await _room.localParticipant?.publishData(utf8.encode(jsonEncode(payload)));
    } catch (_) {}
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || text.length > 500) return;
    final local = _room.localParticipant;
    final identity = local?.identity ?? '';
    final name = local?.name.isNotEmpty == true ? local!.name : identity;
    final id = _newMsgId();

    setState(() {
      _chatMessages.add(_ChatMessage(id: id, identity: identity, name: name, text: text, time: DateTime.now(), isTeacher: widget.isTeacher));
    });
    _chatController.clear();
    _scrollChatToBottom();

    await _publish({'type': 'chat', 'id': id, 'identity': identity, 'name': name, 'text': text, 'ts': DateTime.now().toIso8601String()});
  }

  void _deleteMessage(_ChatMessage m) {
    final localIdentity = _room.localParticipant?.identity ?? '';
    final canDelete = widget.isTeacher || m.identity == localIdentity;
    if (!canDelete) return;
    setState(() => _chatMessages.removeWhere((msg) => msg.id == m.id));
    _publish({'type': 'chat_delete', 'id': m.id, 'identity': localIdentity});
  }

  Future<void> _postAnnouncement() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Post Announcement', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 200,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Message all students...', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;

    final local = _room.localParticipant;
    final name = local?.name.isNotEmpty == true ? local!.name : 'Teacher';
    final id = _newMsgId();
    setState(() => _announcements.add(_Announcement(id: id, text: text, teacherName: name, time: DateTime.now())));
    await _publish({'type': 'announcement', 'id': id, 'identity': local?.identity ?? '', 'name': name, 'text': text});
  }

  void _removeAnnouncement(_Announcement a) {
    setState(() => _announcements.removeWhere((x) => x.id == a.id));
    _publish({'type': 'announcement_remove', 'id': a.id, 'identity': _room.localParticipant?.identity ?? ''});
  }

  Future<void> _toggleRaiseHand() async {
    final local = _room.localParticipant;
    final identity = local?.identity ?? '';
    final name = local?.name.isNotEmpty == true ? local!.name : identity;
    final newState = !_localHandRaised;

    setState(() {
      _localHandRaised = newState;
      if (newState) {
        _raisedHandsAt[identity] = DateTime.now();
      } else {
        _raisedHandsAt.remove(identity);
      }
    });

    await _publish({'type': 'raise_hand', 'identity': identity, 'name': name, 'raised': newState});
  }

  Future<void> _acceptHand(String identity) async {
    await _publish({'type': 'hand_accepted', 'identity': identity});
    if (mounted) setState(() => _raisedHandsAt.remove(identity));
  }

  Future<void> _lowerHand(String identity) async {
    await _publish({'type': 'hand_lowered_by_teacher', 'identity': identity});
    if (mounted) setState(() => _raisedHandsAt.remove(identity));
  }

  Future<void> _clearAllHands() async {
    await _publish({'type': 'hands_cleared', 'identity': _room.localParticipant?.identity ?? ''});
    if (mounted) setState(() => _raisedHandsAt.clear());
  }

  // --- Screen Share (LiveKit built-in - no backend, just another track) ---

  static const _screenShareChannel = MethodChannel('ai_tutor_app/screen_share');
  bool _screenShareBusy = false;

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

  lk.VideoTrack? _screenShareTrackOf(lk.Participant participant) {
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == lk.TrackSource.screenShareVideo) {
        final track = pub.track;
        if (track is lk.VideoTrack && !pub.muted) return track;
      }
    }
    return null;
  }

  /// Finds whoever is currently sharing their screen (local or remote) -
  /// screen share always takes over the main view when active.
  lk.Participant? _activeScreenSharer(List<lk.Participant> allParticipants) {
    for (final p in allParticipants) {
      if (_screenShareTrackOf(p) != null) return p;
    }
    return null;
  }

  // --- Whiteboard (LiveKit data channel - ephemeral, teacher draws only) ---

  Future<void> _openWhiteboard() async {
    setState(() => _whiteboardOpen = true);
    await _publish({'type': 'whiteboard_open', 'identity': _room.localParticipant?.identity ?? ''});
  }

  Future<void> _closeWhiteboard() async {
    setState(() => _whiteboardOpen = false);
    await _publish({'type': 'whiteboard_close', 'identity': _room.localParticipant?.identity ?? ''});
  }

  void _onWhiteboardPanStart(DragStartDetails details) {
    if (!widget.isTeacher) return;
    _currentStrokePoints = [details.localPosition];
    setState(() {});
  }

  void _onWhiteboardPanUpdate(DragUpdateDetails details) {
    if (!widget.isTeacher) return;
    setState(() => _currentStrokePoints = [..._currentStrokePoints, details.localPosition]);
  }

  Future<void> _onWhiteboardPanEnd(DragEndDetails details) async {
    if (!widget.isTeacher || _currentStrokePoints.isEmpty) return;
    final stroke = _Stroke(id: _newMsgId(), points: _currentStrokePoints, color: _whiteboardColor, width: _whiteboardStrokeWidth);
    setState(() {
      _whiteboardStrokes.add(stroke);
      _currentStrokePoints = [];
    });
    await _publish({
      'type': 'whiteboard_stroke',
      'id': stroke.id,
      'identity': _room.localParticipant?.identity ?? '',
      'points': stroke.points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'color': stroke.color.value,
      'width': stroke.width,
    });
  }

  Future<void> _clearWhiteboard() async {
    setState(() => _whiteboardStrokes.clear());
    await _publish({'type': 'whiteboard_clear', 'identity': _room.localParticipant?.identity ?? ''});
  }

  Future<void> _undoWhiteboard() async {
    setState(() {
      if (_whiteboardStrokes.isNotEmpty) _whiteboardStrokes.removeLast();
    });
    await _publish({'type': 'whiteboard_undo', 'identity': _room.localParticipant?.identity ?? ''});
  }

  void _openPanel(_SidePanel panel) {
    setState(() {
      _sidePanel = _sidePanel == panel ? _SidePanel.none : panel;
      if (_sidePanel == _SidePanel.chat) _unreadChatCount = 0;
    });
    if (panel == _SidePanel.attachments && _attachments.isEmpty && _resources.isEmpty && !_loadingAttachments) {
      _loadAttachments();
    }
  }

  Future<void> _loadAttachments() async {
    setState(() {
      _loadingAttachments = true;
      _attachmentsError = null;
    });
    try {
      final futures = <Future>[
        _classService.fetchResources(widget.classId),
        if (widget.subjectId != null) _assignmentService.fetchForSubject(widget.subjectId!) else Future.value(<AssignmentModel>[]),
      ];
      final results = await Future.wait(futures);
      _resources = results[0] as List<ClassResourceModel>;
      _attachments = results[1] as List<AssignmentModel>;
    } catch (e) {
      _attachmentsError = 'Could not load class resources.';
    }
    if (mounted) setState(() => _loadingAttachments = false);
  }

  Future<void> _uploadResource() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'ppt', 'pptx', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png', 'mp4', 'mov'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = result.files.single;
    if (file.size > 25 * 1024 * 1024) {
      _showToast('File is too large (max 25MB).');
      return;
    }

    setState(() {
      _uploadingResource = true;
      _uploadProgress = 0;
    });
    try {
      final resource = await _classService.uploadResource(
        widget.classId,
        file.path!,
        file.name,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (mounted) setState(() => _resources = [resource, ..._resources]);
      await _publish({'type': 'resource_shared', 'identity': _room.localParticipant?.identity ?? '', 'name': resource.fileName});
      _showToast('Shared "${resource.fileName}" with the class');
    } catch (e) {
      _showToast('Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() {
        _uploadingResource = false;
        _uploadProgress = 0;
      });
    }
  }

  Future<void> _deleteResource(ClassResourceModel resource) async {
    try {
      await _classService.deleteResource(widget.classId, resource.id);
      if (mounted) setState(() => _resources.removeWhere((r) => r.id == resource.id));
    } catch (e) {
      _showToast('Failed to delete file.');
    }
  }

  Future<void> _openResource(ClassResourceModel resource) async {
    switch (resource.fileType) {
      case 'pdf':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourcePdfViewerScreen(url: resource.fileUrl, fileName: resource.fileName)));
        break;
      case 'image':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceImageViewerScreen(url: resource.fileUrl, fileName: resource.fileName)));
        break;
      case 'video':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceVideoViewerScreen(url: resource.fileUrl, fileName: resource.fileName)));
        break;
      default:
        // PPT/DOC/XLS - no in-app renderer available in Flutter without a
        // heavy/server-side conversion pipeline, so these download/open
        // via the system's own viewer instead of a broken in-app preview.
        final uri = Uri.tryParse(resource.fileUrl);
        if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          _showToast('Could not open this file.');
        }
    }
  }

  // --- Teacher moderation (existing admin API - unchanged) ---

  Future<void> _muteParticipant(String identity) async {
    try {
      await _classService.muteParticipant(widget.classId, identity);
      _showToast('Participant muted');
    } catch (e) {
      _showToast('Failed to mute participant');
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
      _showToast('Failed to remove participant');
    }
  }

  Future<void> _muteAll() async {
    try {
      await _classService.muteAll(widget.classId);
      _showToast('All participants muted');
    } catch (e) {
      _showToast('Failed to mute all');
    }
  }

  Future<void> _toggleLockRoom() async {
    try {
      if (!_roomLocked) {
        await _classService.lockRoom(widget.classId);
      } else {
        await _classService.unlockRoom(widget.classId);
      }
      if (mounted) setState(() => _roomLocked = !_roomLocked);
    } catch (e) {
      _showToast('Failed to update room lock');
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
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
              if (widget.isTeacher)
                _moreMenuTile(
                  _teacherPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  _teacherPinned ? 'Unpin Myself' : 'Pin Myself as Main View',
                  () {
                    Navigator.pop(context);
                    _toggleTeacherPin();
                  },
                  subtitle: _teacherPinned ? 'Students can be tapped to highlight' : 'You are always the main view',
                  highlighted: _teacherPinned,
                ),
              if (widget.isTeacher && _spotlightIdentity != null)
                _moreMenuTile(Icons.highlight_off_rounded, 'Remove Spotlight', () {
                  Navigator.pop(context);
                  _setSpotlight(null);
                }, highlighted: true),
              if (widget.isTeacher)
                _moreMenuTile(Icons.front_hand_rounded, 'Raised Hands Queue', () {
                  Navigator.pop(context);
                  _openPanel(_SidePanel.raiseQueue);
                }, badge: _raisedHandsAt.length),
              _moreMenuTile(Icons.info_outline_rounded, 'Class Information', () {
                Navigator.pop(context);
                _openPanel(_SidePanel.classInfo);
              }),
              _moreMenuTile(Icons.attach_file_rounded, 'Attachments', () {
                Navigator.pop(context);
                _openPanel(_SidePanel.attachments);
              }),
              if (widget.isTeacher)
                _moreMenuTile(
                  _screenSharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                  _screenSharing ? 'Stop Screen Share' : 'Share Screen',
                  () {
                    Navigator.pop(context);
                    _toggleScreenShare();
                  },
                  highlighted: _screenSharing,
                ),
              if (widget.isTeacher)
                _moreMenuTile(
                  _whiteboardOpen ? Icons.close_fullscreen_rounded : Icons.draw_rounded,
                  _whiteboardOpen ? 'Close Whiteboard' : 'Open Whiteboard',
                  () {
                    Navigator.pop(context);
                    if (_whiteboardOpen) {
                      _closeWhiteboard();
                    } else {
                      _openWhiteboard();
                    }
                  },
                  highlighted: _whiteboardOpen,
                ),
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
      if (mounted) setState(() => _speakerphoneOn = newState);
    } catch (e) {
      _showToast('Could not change audio output on this device.');
    }
  }

  Future<void> _toggleMic() async {
    final newState = !_micEnabled;
    await _room.localParticipant?.setMicrophoneEnabled(newState);
    if (mounted) setState(() => _micEnabled = newState);
  }

  Future<void> _toggleCamera() async {
    final newState = !_cameraEnabled;
    await _room.localParticipant?.setCameraEnabled(newState);
    if (mounted) setState(() => _cameraEnabled = newState);
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
      _showToast('Could not switch camera on this device.');
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
    if (_screenSharing) {
      _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
    }
    _fallbackRebuildTimer?.cancel();
    _endingSoonTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatSearchController.dispose();
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

  /// Resolves who gets the large video, in priority order:
  /// Spotlight (teacher's explicit choice) > Teacher Pin (default mode,
  /// teacher always primary) > manual tap-to-highlight > auto (active
  /// speaker, then just the first participant).
  lk.RemoteParticipant? _primaryParticipant(List<lk.RemoteParticipant> remoteParticipants) {
    if (remoteParticipants.isEmpty) return null;

    if (_spotlightIdentity != null) {
      final spotlighted = remoteParticipants.where((p) => p.identity == _spotlightIdentity).toList();
      if (spotlighted.isNotEmpty) return spotlighted.first;
    }

    final teacher = remoteParticipants.where((p) => p.identity.startsWith('teacher-')).toList();
    if (_teacherPinned && teacher.isNotEmpty) return teacher.first;

    if (_manualPrimaryIdentity != null) {
      final manual = remoteParticipants.where((p) => p.identity == _manualPrimaryIdentity).toList();
      if (manual.isNotEmpty) return manual.first;
    }

    if (teacher.isNotEmpty) return teacher.first;
    final speaking = remoteParticipants.where((p) => _activeSpeakerIdentities.contains(p.identity)).toList();
    if (speaking.isNotEmpty) return speaking.first;
    return remoteParticipants.first;
  }

  /// Tap-to-highlight a thumbnail. Per the classroom brief, this does
  /// nothing while the teacher is pinned or spotlighting someone - the
  /// student just gets a brief explanation instead of a silent no-op.
  void _onTileTap(lk.RemoteParticipant tapped) {
    if (_spotlightIdentity != null) {
      _showToast('The teacher is spotlighting a participant right now.');
      return;
    }
    if (_teacherPinned) {
      _showToast('The teacher has pinned themselves as the main view.');
      return;
    }
    setState(() => _manualPrimaryIdentity = _manualPrimaryIdentity == tapped.identity ? null : tapped.identity);
  }

  Future<void> _toggleTeacherPin() async {
    setState(() {
      _teacherPinned = !_teacherPinned;
      if (_teacherPinned) _manualPrimaryIdentity = null;
    });
  }

  void _setSpotlight(String? identity) {
    setState(() => _spotlightIdentity = identity);
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String _fmtTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_connecting || _error != null) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave this class?'),
            content: const Text('You will be disconnected from the live session.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
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
    final screenSharer = _activeScreenSharer(allParticipants);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              bottom: 84,
              child: _whiteboardOpen
                  ? _buildWhiteboardView(remoteParticipants)
                  : (screenSharer != null
                      ? _buildScreenShareView(screenSharer, allParticipants.where((p) => p.identity != screenSharer.identity).toList())
                      : (remoteParticipants.isEmpty
                          ? _buildWaitingState()
                          : (_speakerView
                              ? _buildFocusedLayout(primary, others)
                              : GridView.count(
                                  crossAxisCount: remoteParticipants.length > 1 ? 2 : 1,
                                  padding: const EdgeInsets.all(8),
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  children: remoteParticipants.map((p) => _participantTile(p)).toList(),
                                )))),
            ),

            Positioned(
              top: 4,
              left: 12,
              right: 12,
              child: _screenSharing
                  ? Material(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(24),
                      elevation: 4,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _toggleScreenShare,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.screen_share_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text('You are presenting your screen', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              Icon(Icons.stop_circle_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text('Stop Sharing', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Row(
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

            // --- Pinned announcements ---
            if (_announcements.isNotEmpty)
              Positioned(
                top: 44,
                left: 12,
                right: 12,
                child: Column(
                  children: _announcements.map((a) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.campaign_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('${a.teacherName} \u2022 ${_fmtTime(a.time)}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                          if (widget.isTeacher)
                            InkWell(onTap: () => _removeAnnouncement(a), child: const Icon(Icons.close_rounded, color: Colors.white, size: 16)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            if (localParticipant != null) _buildDraggablePip(localParticipant),

            Positioned(left: 0, right: 0, bottom: 0, child: _buildToolbar()),

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
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
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
        // ~68% of the available video area for the primary tile, per the
        // "teacher always the focus" classroom layout.
        Expanded(
          flex: 68,
          child: primary != null ? _participantTile(primary, isPrimary: true) : const SizedBox.shrink(),
        ),
        if (others.isNotEmpty)
          Expanded(
            flex: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final p = others[index];
                return SizedBox(width: 84, child: _participantTile(p, onTap: () => _onTileTap(p)));
              },
            ),
          ),
      ],
    );
  }

  Widget _buildScreenShareView(lk.Participant sharer, List<lk.Participant> others) {
    final track = _screenShareTrackOf(sharer);
    final isMe = sharer.identity == (_room.localParticipant?.identity ?? '');
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black,
            // Fix: never render the local user's OWN screen-share track
            // back to themselves. With "Entire Screen" capture, doing so
            // recaptures the app showing that same video, creating an
            // infinite recursive mirror. Other participants still see
            // the real VideoTrackRenderer normally - only the sharer's
            // own view is replaced with a static placeholder.
            child: isMe
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.screen_share_rounded, color: Colors.white54, size: 48),
                        SizedBox(height: 12),
                        Text('You are presenting your screen', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Other participants can see your shared screen', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  )
                : (track != null ? lk.VideoTrackRenderer(track) : const Center(child: CircularProgressIndicator(color: Colors.white54))),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: Text(
              isMe ? 'You are sharing your screen' : '${sharer.name.isNotEmpty ? sharer.name : sharer.identity} is sharing their screen',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        // Presenter's own camera as a small PiP over the shared screen.
        Positioned(
          top: 44,
          right: 12,
          child: SizedBox(width: 84, height: 112, child: _participantTile(sharer)),
        ),
        if (others.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(width: 76, child: _participantTile(others[index])),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWhiteboardView(List<lk.RemoteParticipant> remoteParticipants) {
    const colors = [Colors.red, Colors.blue, Colors.green, Colors.black, Colors.orange];
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: _onWhiteboardPanStart,
              onPanUpdate: _onWhiteboardPanUpdate,
              onPanEnd: _onWhiteboardPanEnd,
              child: CustomPaint(
                painter: _WhiteboardPainter(strokes: _whiteboardStrokes, currentPoints: _currentStrokePoints, currentColor: _whiteboardColor, currentWidth: _whiteboardStrokeWidth),
                size: Size.infinite,
              ),
            ),
          ),
          Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (widget.isTeacher) ...[
                  ...colors.map((c) => GestureDetector(
                        onTap: () => setState(() => _whiteboardColor = c),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: _whiteboardColor == c ? Border.all(color: Colors.black, width: 2) : null),
                        ),
                      )),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.undo_rounded, size: 20), onPressed: _undoWhiteboard),
                  IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), onPressed: _clearWhiteboard),
                ] else
                  const Expanded(child: Text('Teacher\u2019s Whiteboard', style: TextStyle(fontSize: 12, color: Colors.black54))),
                const Spacer(),
                if (widget.isTeacher)
                  TextButton.icon(onPressed: _closeWhiteboard, icon: const Icon(Icons.close_rounded, size: 18), label: const Text('Close')),
              ],
            ),
          ),
        ],
      ),
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
        child: SizedBox(width: 96, height: 128, child: _participantTile(localParticipant, isLocal: true)),
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
          _badgedToolbarButton(Icons.more_horiz_rounded, Colors.white24, _showMoreMenu, badgeCount: _unreadChatCount + (widget.isTeacher ? _raisedHandsAt.length : 0)),
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

  Widget _buildSlideUpPanel(List<lk.Participant> allParticipants) {
    final open = _sidePanel != _SidePanel.none;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: open ? 84 : -600,
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
                    Text(_panelTitle(allParticipants.length), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    if (_sidePanel == _SidePanel.chat)
                      IconButton(icon: Icon(_chatSearchOpen ? Icons.close_rounded : Icons.search_rounded, color: Colors.white70, size: 20), onPressed: () => setState(() => _chatSearchOpen = !_chatSearchOpen)),
                    IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), onPressed: () => setState(() => _sidePanel = _SidePanel.none)),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(child: _panelBody(allParticipants)),
            ],
          ),
        ),
      ),
    );
  }

  String _panelTitle(int participantCount) {
    switch (_sidePanel) {
      case _SidePanel.chat:
        return 'Chat';
      case _SidePanel.participants:
        return 'Participants ($participantCount)';
      case _SidePanel.raiseQueue:
        return 'Raised Hands (${_raisedHandsAt.length})';
      case _SidePanel.classInfo:
        return 'Class Information';
      case _SidePanel.attachments:
        return 'Attachments';
      case _SidePanel.none:
        return '';
    }
  }

  Widget _panelBody(List<lk.Participant> allParticipants) {
    switch (_sidePanel) {
      case _SidePanel.chat:
        return _buildChatPanel();
      case _SidePanel.participants:
        return _buildParticipantsPanel(allParticipants);
      case _SidePanel.raiseQueue:
        return _buildRaiseQueuePanel(allParticipants);
      case _SidePanel.classInfo:
        return _buildClassInfoPanel(allParticipants.length);
      case _SidePanel.attachments:
        return _buildAttachmentsPanel();
      case _SidePanel.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildChatPanel() {
    final query = _chatSearchController.text.trim().toLowerCase();
    final visible = query.isEmpty ? _chatMessages : _chatMessages.where((m) => m.text.toLowerCase().contains(query)).toList();

    return Column(
      children: [
        if (_chatSearchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextField(
              controller: _chatSearchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search messages...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                filled: true,
                fillColor: Colors.grey.shade800,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(query.isEmpty ? 'No messages yet.' : 'No messages match "$query".', style: const TextStyle(color: Colors.white38, fontSize: 12)))
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final m = visible[index];
                    final localIdentity = _room.localParticipant?.identity ?? '';
                    final isMe = m.identity == localIdentity;
                    final canDelete = widget.isTeacher || isMe;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: canDelete ? () => _deleteMessage(m) : null,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.purple : (m.isTeacher ? AppColors.orange.withOpacity(0.85) : Colors.grey.shade800),
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
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    children: [
                                      Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                      if (m.isTeacher) ...[
                                        const SizedBox(width: 4),
                                        const Text('\u2022 Teacher', style: TextStyle(color: Colors.white70, fontSize: 9, fontStyle: FontStyle.italic)),
                                      ],
                                    ],
                                  ),
                                ),
                              Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_fmtTime(m.time), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9)),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.done_rounded, size: 11, color: Colors.white.withOpacity(0.6)),
                                  ],
                                ],
                              ),
                            ],
                          ),
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
                    maxLength: 500,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      counterText: '',
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
        final handRaised = _raisedHandsAt.containsKey(p.identity);
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
                    PopupMenuItem(
                      value: 'spotlight',
                      child: Text(_spotlightIdentity == p.identity ? 'Remove Spotlight' : 'Spotlight', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    const PopupMenuItem(value: 'mute', child: Text('Mute', style: TextStyle(color: Colors.white, fontSize: 13))),
                    const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                  onSelected: (value) {
                    if (value == 'spotlight') _setSpotlight(_spotlightIdentity == p.identity ? null : p.identity);
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

  Widget _buildRaiseQueuePanel(List<lk.Participant> allParticipants) {
    final entries = _raisedHandsAt.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    if (entries.isEmpty) {
      return const Center(child: Text('No raised hands right now.', style: TextStyle(color: Colors.white38, fontSize: 12)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _clearAllHands, icon: const Icon(Icons.clear_all_rounded, size: 16, color: AppColors.error), label: const Text('Clear All', style: TextStyle(color: AppColors.error, fontSize: 12))),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final identity = entries[index].key;
              final time = entries[index].value;
              final participant = allParticipants.where((p) => p.identity == identity).firstOrNull;
              final name = participant?.name.isNotEmpty == true ? participant!.name : identity;
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.orange, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: Text('Raised ${_timeAgo(time)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: () => _acceptHand(identity), child: const Text('Accept', style: TextStyle(fontSize: 12))),
                    TextButton(onPressed: () => _lowerHand(identity), child: const Text('Lower', style: TextStyle(color: Colors.white54, fontSize: 12))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClassInfoPanel(int participantCount) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.description.isNotEmpty) ...[
          const Text('Description', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(widget.description, style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 16),
        ],
        _infoRow(Icons.menu_book_outlined, 'Subject', widget.subjectName.isNotEmpty ? widget.subjectName : '\u2014'),
        _infoRow(Icons.play_lesson_outlined, 'Lesson', widget.lessonTitle.isNotEmpty ? widget.lessonTitle : '\u2014'),
        if (widget.scheduledStart != null) _infoRow(Icons.event_outlined, 'Start Time', _fmtTime(widget.scheduledStart!)),
        if (widget.scheduledStart != null && widget.scheduledEnd != null)
          _infoRow(Icons.timer_outlined, 'Duration', '${widget.scheduledEnd!.difference(widget.scheduledStart!).inMinutes} min'),
        _infoRow(Icons.live_tv_rounded, 'Meeting Status', 'Live'),
        _infoRow(Icons.people_outline_rounded, 'Participants', '$participantCount'),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 10),
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildAttachmentsPanel() {
    return Column(
      children: [
        if (widget.isTeacher)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploadingResource ? null : _uploadResource,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                icon: _uploadingResource
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
                label: Text(_uploadingResource ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%' : 'Upload File (PDF, PPT, Image, Doc, Video)', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        Expanded(
          child: _loadingAttachments
              ? const Center(child: CircularProgressIndicator(color: Colors.white54))
              : (_attachmentsError != null
                  ? Center(child: Text(_attachmentsError!, style: const TextStyle(color: Colors.white54, fontSize: 12)))
                  : (_resources.isEmpty && _attachments.isEmpty
                      ? const Center(child: Text('Nothing shared yet.', style: TextStyle(color: Colors.white38, fontSize: 12)))
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            if (_resources.isNotEmpty) ...[
                              const Padding(padding: EdgeInsets.only(bottom: 6, left: 4), child: Text('Shared Files', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700))),
                              ..._resources.map((r) => _resourceCard(r)),
                              const SizedBox(height: 12),
                            ],
                            if (_attachments.isNotEmpty) ...[
                              const Padding(padding: EdgeInsets.only(bottom: 6, left: 4), child: Text('Assignments', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700))),
                              ..._attachments.map((a) => _assignmentCard(a)),
                            ],
                          ],
                        ))),
        ),
      ],
    );
  }

  IconData _resourceIcon(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'ppt':
        return Icons.slideshow_rounded;
      case 'doc':
        return Icons.description_rounded;
      case 'xls':
        return Icons.grid_on_rounded;
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.videocam_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _resourceCard(ClassResourceModel r) {
    final canDelete = widget.isTeacher;
    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_resourceIcon(r.fileType), color: AppColors.purple),
        title: Text(r.fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
        subtitle: Text('${_formatFileSize(r.fileSizeBytes)} \u2022 Shared by teacher', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: canDelete
            ? IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18), onPressed: () => _deleteResource(r))
            : const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 16),
        onTap: () => _openResource(r),
      ),
    );
  }

  Widget _assignmentCard(AssignmentModel a) {
    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.assignment_rounded, color: AppColors.purple),
        title: Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
        subtitle: Text('${a.maxMarks} marks \u2022 ${a.difficulty}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: () {
          // Pushes on top of this screen - the LiveKit Room object stays
          // connected in the background since this State isn't disposed,
          // so returning here keeps the call live.
          Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentDetailScreen(assignmentId: a.id)));
        },
      ),
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

  Widget _participantTile(lk.Participant participant, {bool isLocal = false, bool isPrimary = false, VoidCallback? onTap}) {
    final videoTrack = _videoTrackOf(participant);
    final displayName = participant.name.isNotEmpty ? participant.name : participant.identity;
    final isTeacherRole = participant.identity.startsWith('teacher-');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final isSpeaking = _activeSpeakerIdentities.contains(participant.identity);
    final isSpotlighted = _spotlightIdentity == participant.identity;
    final handRaised = _raisedHandsAt.containsKey(participant.identity);
    final quality = _connectionQuality[participant.identity];

    final tile = Container(
      key: ValueKey('${participant.identity}-${videoTrack != null}'),
      margin: isLocal ? EdgeInsets.zero : const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(isLocal ? 14 : (isPrimary ? 20 : 16)),
        border: isSpotlighted
            ? Border.all(color: AppColors.orange, width: 3)
            : (isSpeaking ? Border.all(color: AppColors.blue, width: 3) : Border.all(color: Colors.white10, width: 1)),
        boxShadow: isSpeaking
            ? [BoxShadow(color: AppColors.blue.withOpacity(0.5), blurRadius: 12, spreadRadius: 1)]
            : [const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
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

    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}

/// Renders all committed whiteboard strokes plus the one currently being
/// drawn (if any) - repaints only when strokes actually change.
class _WhiteboardPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  _WhiteboardPainter({required this.strokes, required this.currentPoints, required this.currentColor, required this.currentWidth});

  void _paintStroke(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke.points, stroke.color, stroke.width);
    }
    _paintStroke(canvas, currentPoints, currentColor, currentWidth);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) {
    return oldDelegate.strokes.length != strokes.length || oldDelegate.currentPoints.length != currentPoints.length;
  }
}

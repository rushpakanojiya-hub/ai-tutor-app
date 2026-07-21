import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/subject_model.dart';
import '../../providers/ai_provider.dart';
import '../../services/subject_service.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/recommendation_card.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/voice_input_button.dart';

/// Single ChatGPT-style AI Tutor screen: replaces the old separate
/// Ask Question / Homework Help / Chat History / Recommendations pages.
///
/// Everything lives here: a drawer for chat history + "New Chat", subject
/// chips and personalized recommendations shown on a fresh chat, a
/// Homework Mode toggle, follow-up suggestion chips after each answer,
/// and message actions (copy/retry/regenerate/delete) via ChatBubble.
class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({super.key});

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final SubjectService _subjectService = SubjectService();

  List<SubjectModel> _subjects = [];
  bool _loadingSubjects = true;
  bool _extractingImage = false;

  // BUG FIX ("Chat feels hung / doesn't scroll immediately"): the screen
  // used to only call _scrollToBottom() once, after `await
  // provider.sendMessage(value)` fully returned - and sendMessage()
  // itself awaits the entire word-by-word typing-reveal animation before
  // returning. So the student's own message (added to the list
  // immediately by the provider) sat off-screen, unscrolled-to, for the
  // ENTIRE round trip + typing animation - looking exactly like the chat
  // had hung, even though it was working correctly underneath. Holding a
  // reference to the provider lets this screen listen for every state
  // change (message added, each word revealed, reply finished) and
  // scroll to follow along live, instead of waiting for one big
  // await to finish. Stored directly (not looked up via context in
  // dispose(), which can be unsafe) so it can be safely removed.
  AiProvider? _providerRef;

  static const _followUps = [
    'Explain in simple language',
    'Give examples',
    'Create quiz',
    'Create notes',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {
      _subjects = [];
    }
    // QA fix ("Missing mounted checks after async operations" / "Safe
    // BuildContext usage"): context.read<AiProvider>() below used to run
    // unconditionally right after an await - if the user had already
    // navigated away while fetchAllSubjects() was in flight, this threw
    // "Looking up a deactivated widget's ancestor is unsafe."
    if (!mounted) return;
    setState(() => _loadingSubjects = false);

    final provider = context.read<AiProvider>();
    _providerRef = provider;
    // Scroll to follow every provider change (new message, each word of
    // the typing-reveal animation, error state) - see the field comment
    // above for why this replaces waiting on one big await.
    provider.addListener(_scrollToBottom);
    provider.loadSessions();
    provider.loadRecommendations();
    if (provider.messages.isEmpty && provider.currentSessionId == null) {
      provider.startNewChat();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? text]) async {
    final value = text ?? _controller.text;
    if (value.trim().isEmpty) return;
    _controller.clear();
    final provider = context.read<AiProvider>();
    await provider.sendMessage(value);
    _scrollToBottom();
  }

  void _startNewChat(AiProvider provider) {
    provider.startNewChat();
    Navigator.of(context).maybePop();
  }

  /// Lets the student attach a photo (camera or gallery) of a homework
  /// question, textbook page, etc. Runs on-device OCR (ML Kit, no network
  /// call) and inserts the extracted text into the message box so they
  /// can edit it before sending - same pattern as the mic button.
  Future<void> _attachImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(source: source, imageQuality: 85);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access camera/gallery. Check app permissions.')),
        );
      }
      return;
    }
    if (file == null) return;
    if (!mounted) return;

    setState(() => _extractingImage = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final extracted = result.text.trim();

      if (extracted.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No readable text found in that image.')),
          );
        }
      } else {
        _controller.text = _controller.text.isEmpty ? extracted : '${_controller.text}\n$extracted';
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read text from that image. Please try again.')),
        );
      }
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _extractingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();
    if (provider.messages.isNotEmpty) _scrollToBottom();

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('AI Tutor'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate_rounded),
            tooltip: 'Language',
            onSelected: (lang) => provider.setLanguage(lang),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'hi', child: Text('हिंदी (Hindi)')),
              PopupMenuItem(value: 'mr', child: Text('मराठी (Marathi)')),
            ],
          ),
        ],
      ),
      drawer: _buildDrawer(provider),
      body: Column(
        children: [
          Expanded(
            child: provider.messages.isEmpty && !provider.isSending
                ? _buildHomeContent(provider)
                : _buildMessageList(provider),
          ),
          if (provider.chatError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(provider.chatError!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
                  TextButton(onPressed: () => provider.retryLast(), child: const Text('Retry')),
                ],
              ),
            ),
          _buildInputBar(provider),
        ],
      ),
    );
  }

  Widget _buildDrawer(AiProvider provider) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => _startNewChat(provider),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Recent chats', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildSessionsList(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsList(AiProvider provider) {
    if (provider.isLoadingSessions) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: SkeletonBox(height: 44, borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
      );
    }
    if (provider.sessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No chats yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: provider.sessions.length,
      itemBuilder: (context, index) {
        final session = provider.sessions[index];
        final isActive = session.id == provider.currentSessionId;
        return ListTile(
          leading: Icon(Icons.chat_bubble_outline_rounded, color: isActive ? AppColors.purple : AppColors.textSecondary, size: 20),
          title: Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, fontSize: 13),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textSecondary),
            onPressed: () => _confirmDelete(context, provider, session.id),
          ),
          onTap: () async {
            Navigator.of(context).pop();
            await provider.loadSessionIntoChat(session.id);
            if (mounted) _scrollToBottom();
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, AiProvider provider, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteSession(id);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(AiProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How can I help you learn today?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (!_loadingSubjects && _subjects.isNotEmpty) _buildSubjectChips(provider),
          const SizedBox(height: 20),
          if (provider.isLoadingRecommendations)
            const SkeletonBox(height: 76, borderRadius: BorderRadius.all(Radius.circular(18)))
          else if (provider.recommendations.isNotEmpty) ...[
            const Text('Recommended', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...provider.recommendations.take(3).map(
                  (rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RecommendationCard(
                      recommendation: rec,
                      onTap: () => context.push('/lesson-player', extra: {'lessonId': rec.recommendedLessonId}),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectChips(AiProvider provider) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _subjectChip(provider, null, 'General'),
          ..._subjects.map((s) => _subjectChip(provider, s.id, s.name)),
        ],
      ),
    );
  }

  Widget _subjectChip(AiProvider provider, int? id, String label) {
    final selected = provider.currentSubjectId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => provider.setSubject(id),
        selectedColor: AppColors.purpleLight,
        labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary),
      ),
    );
  }

  Widget _buildMessageList(AiProvider provider) {
    final showTypingDots = provider.isSending &&
        provider.messages.isNotEmpty &&
        !provider.messages.last.isUser &&
        provider.messages.last.message.isEmpty;

    final displayMessages = showTypingDots ? provider.messages.sublist(0, provider.messages.length - 1) : provider.messages;

    final lastAssistantDone = provider.messages.isNotEmpty &&
        !provider.messages.last.isUser &&
        !provider.messages.last.isStreaming &&
        !provider.isSending;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: displayMessages.length + (showTypingDots ? 1 : 0) + (lastAssistantDone ? 1 : 0),
      itemBuilder: (context, index) {
        if (showTypingDots && index == displayMessages.length) {
          return const Padding(padding: EdgeInsets.only(bottom: 8), child: TypingIndicator());
        }
        final followUpIndex = displayMessages.length + (showTypingDots ? 1 : 0);
        if (lastAssistantDone && index == followUpIndex) {
          return _buildFollowUps();
        }
        final message = displayMessages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ChatBubble(
            message: message,
            onRetry: message.isUser ? () => provider.retryLast() : null,
            onRegenerate: !message.isUser ? () => provider.regenerate(message.id) : null,
            onDelete: () => provider.deleteMessageLocally(message.id),
          ),
        );
      },
    );
  }

  Widget _buildFollowUps() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _followUps
            .map(
              (q) => ActionChip(
                label: Text(q, style: const TextStyle(fontSize: 12)),
                backgroundColor: AppColors.purpleLight,
                labelStyle: const TextStyle(color: AppColors.purple),
                onPressed: () => _send(q),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildInputBar(AiProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Attach an image',
              icon: _extractingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.purple),
                    )
                  : const Icon(Icons.attach_file_rounded, color: AppColors.textSecondary),
              onPressed: _extractingImage ? null : _attachImage,
            ),
            VoiceInputButton(onResult: (text) => _controller.text = text),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Ask anything...',
                  filled: true,
                  fillColor: AppColors.pageBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle),
              child: IconButton(
                onPressed: provider.isSending ? null : () => _send(),
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _providerRef?.removeListener(_scrollToBottom);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

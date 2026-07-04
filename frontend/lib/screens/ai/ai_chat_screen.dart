import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/subject_model.dart';
import '../../providers/ai_provider.dart';
import '../../services/subject_service.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/voice_button.dart';

/// AI Tutor chat: pick a subject (optional, for subject-specific answers),
/// then chat. Supports English/Hindi/Marathi replies and basic
/// speech-to-text voice input.
class AiChatScreen extends StatefulWidget {
  /// If opened from AiHistoryScreen to resume a saved conversation.
  final int? conversationId;

  const AiChatScreen({super.key, this.conversationId});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final SubjectService _subjectService = SubjectService();

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  bool _loadingSubjects = true;

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
    if (mounted) setState(() => _loadingSubjects = false);

    if (widget.conversationId != null) {
      await context.read<AiProvider>().loadConversationIntoChat(widget.conversationId!);
      if (mounted) setState(() => _selectedSubjectId = context.read<AiProvider>().currentSubjectId);
    } else {
      context.read<AiProvider>().startNewChat();
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

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    final provider = context.read<AiProvider>();
    provider.currentSubjectId = _selectedSubjectId;
    await provider.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Tutor Chat'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate_rounded),
            tooltip: 'Language',
            onSelected: (lang) => context.read<AiProvider>().setLanguage(lang),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'hi', child: Text('à¤¹à¤¿à¤‚à¤¦à¥€ (Hindi)')),
              PopupMenuItem(value: 'mr', child: Text('à¤®à¤°à¤¾à¤ à¥€ (Marathi)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_loadingSubjects && _subjects.isNotEmpty) _buildSubjectSelector(),
          Expanded(child: _buildMessageList(provider)),
          if (provider.chatError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(provider.chatError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          _buildInputBar(provider),
        ],
      ),
    );
  }

  Widget _buildSubjectSelector() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _subjectChip(null, 'General'),
          ..._subjects.map((s) => _subjectChip(s.id, s.name)),
        ],
      ),
    );
  }

  Widget _subjectChip(int? id, String label) {
    final selected = _selectedSubjectId == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedSubjectId = id),
        selectedColor: AppColors.purpleLight,
        labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _buildMessageList(AiProvider provider) {
    if (provider.messages.isEmpty && !provider.isSending) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.smart_toy_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('Ask me anything about your subjects!', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: provider.messages.length + (provider.isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == provider.messages.length) {
          return const Padding(padding: EdgeInsets.only(bottom: 8), child: TypingIndicator());
        }
        final message = provider.messages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ChatBubble(
            message: message,
            onRetry: message.isUser ? () => provider.retryLast() : null,
            onDelete: () => provider.deleteMessageLocally(message.id),
          ),
        );
      },
    );
  }

  Widget _buildInputBar(AiProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            VoiceButton(onResult: (text) => _controller.text = text),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Ask a question...',
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
                onPressed: provider.isSending ? null : _send,
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
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

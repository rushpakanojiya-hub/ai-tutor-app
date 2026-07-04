import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/ai_provider.dart';
import '../../widgets/skeleton_box.dart';

/// Lists the student's saved AI Tutor conversations. Tapping one resumes
/// it in AiChatScreen; swiping/long-pressing deletes it.
class AiHistoryScreen extends StatefulWidget {
  const AiHistoryScreen({super.key});

  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AiProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Chat History')),
      body: RefreshIndicator(
        onRefresh: () => provider.loadConversations(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(AiProvider provider) {
    if (provider.isLoadingConversations) {
      return ListView.separated(
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => SkeletonBox(height: 64, borderRadius: BorderRadius.circular(16)),
      );
    }

    if (provider.conversationsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(provider.conversationsError!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => provider.loadConversations(), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (provider.conversations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No chat history yet.', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 4),
            Text('Start a conversation with the AI Tutor!', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: provider.conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final conv = provider.conversations[index];
        return Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/ai-chat', extra: {'conversationId': conv.id}),
            onLongPress: () => _confirmDelete(context, provider, conv.id),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.purple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                    onPressed: () => _confirmDelete(context, provider, conv.id),
                  ),
                ],
              ),
            ),
          ),
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
              provider.deleteConversation(id);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

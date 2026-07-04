import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/snackbar_utils.dart';
import '../models/ai_message.dart';

/// One chat message bubble: user messages align right (purple), AI
/// messages align left (white card). Long-press reveals Copy/Retry/Delete
/// actions. Shows a small timestamp under each bubble.
class ChatBubble extends StatelessWidget {
  final AiMessageModel message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  const ChatBubble({super.key, required this.message, this.onRetry, this.onDelete});

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.message));
                Navigator.pop(context);
                SnackbarUtils.showSuccess(context, 'Copied to clipboard');
              },
            ),
            if (message.isUser && onRetry != null)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Retry'),
                onTap: () {
                  Navigator.pop(context);
                  onRetry!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: const Text('Delete', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isUser ? AppColors.purple : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Text(
                message.message,
                style: TextStyle(color: isUser ? Colors.white : AppColors.textPrimary, height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_formatTime(message.createdAt), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

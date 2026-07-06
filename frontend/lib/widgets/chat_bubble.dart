import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/snackbar_utils.dart';
import '../models/ai_message.dart';

/// One chat message bubble: user messages align right (purple), AI
/// messages align left (white card) with lightweight markdown rendering
/// (**bold**, numbered/bulleted lists). Long-press reveals Copy/Retry/
/// Delete actions (disabled while the message is still streaming in).
class ChatBubble extends StatelessWidget {
  final AiMessageModel message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  const ChatBubble({super.key, required this.message, this.onRetry, this.onDelete});

  void _showActions(BuildContext context) {
    if (message.isStreaming) return;
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

  /// Renders a small, dependency-free subset of markdown: **bold** spans,
  /// and lines starting with "- " or "1. " get a bullet/number prefix.
  /// This isn't a full markdown parser â€” just enough to make Groq's
  /// naturally-formatted replies (which often use **bold** and lists)
  /// readable without adding a new native package dependency.
  Widget _renderContent(bool isUser) {
    final color = isUser ? Colors.white : AppColors.textPrimary;
    final lines = message.message.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        final spans = _parseBold(line, color);
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RichText(text: TextSpan(style: TextStyle(color: color, height: 1.4, fontSize: 14), children: spans)),
        );
      }).toList(),
    );
  }

  List<TextSpan> _parseBold(String line, Color color) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(text: line.substring(last, match.start)));
      }
      spans.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = match.end;
    }
    if (last < line.length) {
      spans.add(TextSpan(text: line.substring(last)));
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ''));
    return spans;
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
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
              child: message.message.isEmpty && message.isStreaming
                  ? const SizedBox(width: 20, height: 14)
                  : _renderContent(isUser),
            ),
            if (!(message.message.isEmpty && message.isStreaming))
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/api_constants.dart';
import '../core/theme/app_colors.dart';
import '../models/note_model.dart';
import 'skeleton_box.dart';

/// Renders the "PDF Notes" section under a lesson: a list of notes with
/// "Open" (in-app viewer) and "Download" (external browser/app) actions.
class NotesWidget extends StatelessWidget {
  final List<NoteModel> notes;
  final bool isLoading;
  final String? errorMessage;

  const NotesWidget({
    super.key,
    required this.notes,
    required this.isLoading,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            SkeletonBox(height: 48, borderRadius: BorderRadius.circular(12)),
            const SizedBox(height: 8),
            SkeletonBox(height: 48, borderRadius: BorderRadius.circular(12)),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(errorMessage!, style: const TextStyle(color: AppColors.error)),
      );
    }

    if (notes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No PDF notes for this lesson yet.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PDF Notes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 10),
        ...notes.map((note) => _NoteTile(note: note)),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  final NoteModel note;
  const _NoteTile({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E5EC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: () => context.push(
              '/pdf-viewer',
              extra: {'url': ApiConstants.resolveMediaUrl(note.pdfUrl), 'title': note.title},
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

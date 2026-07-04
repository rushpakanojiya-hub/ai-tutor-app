import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/custom_button.dart';

/// AI-generated notes screen for a lesson's PDF: opens in the device's
/// browser/PDF app, with Download (same action) and Share (copies the
/// link) actions.
class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerScreen({super.key, required this.url, required this.title});

  Future<void> _open(BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        SnackbarUtils.showError(context, 'Could not open this file.');
      }
    } catch (_) {
      if (context.mounted) {
        SnackbarUtils.showError(context, 'Could not open this file.');
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Link copied to clipboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.picture_as_pdf_rounded, size: 72, color: AppColors.error),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI-generated notes for this lesson â€” opens in your browser or PDF app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            if (url.isEmpty)
              const Text('No PDF URL provided for this note.', style: TextStyle(color: AppColors.textSecondary))
            else ...[
              CustomButton(label: 'Open PDF', onPressed: () => _open(context)),
              const SizedBox(height: 12),
              CustomButton(label: 'Download PDF', outlined: true, onPressed: () => _open(context)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

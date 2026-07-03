import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/custom_button.dart';

/// Feature 5: PDF notes screen. Opens the PDF in the device's default
/// browser/PDF app instead of rendering it natively in-app — this avoids
/// pulling in a native PDF-render plugin (e.g. syncfusion_flutter_pdfviewer),
/// which conflicts with newer Android Gradle Plugin versions (jcenter()
/// removal) on freshly created Flutter projects. url_launcher has no such
/// native Gradle footprint, so it "just works" regardless of AGP version.
class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerScreen({super.key, required this.url, required this.title});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) {
      if (context.mounted) {
        SnackbarUtils.showError(context, 'Could not open this file.');
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
              'This PDF opens in your browser or PDF app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            if (url.isEmpty)
              const Text('No PDF URL provided for this note.', style: TextStyle(color: AppColors.textSecondary))
            else
              CustomButton(label: 'Open PDF', onPressed: () => _open(context)),
          ],
        ),
      ),
    );
  }
}
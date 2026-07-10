import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/theme/app_colors.dart';

/// In-app PDF viewer for Class Resources - opens Cloudinary/GCS-hosted
/// PDFs directly by URL, with zoom, page navigation, and a download
/// fallback if rendering fails (e.g. no network).
class ResourcePdfViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;

  const ResourcePdfViewerScreen({super.key, required this.url, required this.fileName});

  @override
  State<ResourcePdfViewerScreen> createState() => _ResourcePdfViewerScreenState();
}

class _ResourcePdfViewerScreenState extends State<ResourcePdfViewerScreen> {
  final PdfViewerController _controller = PdfViewerController();
  bool _hasError = false;
  int _currentPage = 1;
  int _totalPages = 0;

  // QA fix ("PdfViewerController disposal"): this controller was created
  // but never disposed - every time this screen was opened and closed,
  // its underlying resources (rendered page cache, native PDF handles)
  // leaked for the lifetime of the app process.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        actions: [
          if (_totalPages > 0)
            Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('$_currentPage / $_totalPages', style: const TextStyle(fontSize: 12)))),
        ],
      ),
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    const Text('Could not load this PDF.', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 20),
                    ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
                  ],
                ),
              ),
            )
          : SfPdfViewer.network(
              widget.url,
              controller: _controller,
              onDocumentLoadFailed: (details) => setState(() => _hasError = true),
              onDocumentLoaded: (details) => setState(() => _totalPages = details.document.pages.count),
              onPageChanged: (details) => setState(() => _currentPage = details.newPageNumber),
            ),
    );
  }
}

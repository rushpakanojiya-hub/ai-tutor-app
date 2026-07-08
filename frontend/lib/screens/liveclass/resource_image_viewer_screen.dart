import 'package:flutter/material.dart';

/// Full-screen pinch-to-zoom image viewer for Class Resources.
class ResourceImageViewerScreen extends StatelessWidget {
  final String url;
  final String fileName;

  const ResourceImageViewerScreen({super.key, required this.url, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const CircularProgressIndicator(color: Colors.white54);
            },
            errorBuilder: (context, error, stackTrace) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                SizedBox(height: 12),
                Text('Could not load this image.', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

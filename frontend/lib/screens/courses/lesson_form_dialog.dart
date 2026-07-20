import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';
import '../lessons/pdf_viewer_screen.dart';
import '../liveclass/resource_video_viewer_screen.dart';

/// Lesson Resource Management: the single Create/Edit Lesson surface for
/// admins and teachers. Everything - lesson details, video (uploaded or
/// YouTube), PDF notes, and publish/unpublish - lives inside this one
/// dialog, per spec. No separate Video/PDF pages are created; existing
/// viewer screens are reused for "Preview".
///
/// Returns `true` via Navigator.pop when the caller's lesson list should
/// be refreshed, `false`/`null` otherwise.
Future<bool?> showLessonFormDialog(
  BuildContext context, {
  required int subjectId,
  AdminLessonModel? existing,
  required int nextOrderNumber,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LessonFormDialog(subjectId: subjectId, existing: existing, nextOrderNumber: nextOrderNumber),
  );
}

class LessonFormDialog extends StatefulWidget {
  final int subjectId;
  final AdminLessonModel? existing;
  final int nextOrderNumber;

  const LessonFormDialog({super.key, required this.subjectId, this.existing, required this.nextOrderNumber});

  @override
  State<LessonFormDialog> createState() => _LessonFormDialogState();
}

class _LessonFormDialogState extends State<LessonFormDialog> {
  final CourseService _service = CourseService();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _youtubeCtrl;
  late final TextEditingController _pdfTitleCtrl;
  late final TextEditingController _pdfDescCtrl;

  AdminLessonModel? _lesson;
  String _videoInputMode = 'upload'; // 'upload' | 'youtube' - which control the user is using right now
  bool _changed = false;

  bool _saving = false;
  bool _uploadingVideo = false;
  bool _uploadingPdf = false;
  String? _error;

  bool get _isNew => _lesson == null;

  @override
  void initState() {
    super.initState();
    _lesson = widget.existing;
    _titleCtrl = TextEditingController(text: _lesson?.title ?? '');
    _descCtrl = TextEditingController(text: _lesson?.description ?? '');
    _durationCtrl = TextEditingController(text: _lesson != null && _lesson!.duration > 0 ? _lesson!.duration.toString() : '');
    _youtubeCtrl = TextEditingController(text: _lesson?.youtubeUrl ?? '');
    _pdfTitleCtrl = TextEditingController(text: _lesson?.pdfTitle ?? '');
    _pdfDescCtrl = TextEditingController(text: _lesson?.pdfDescription ?? '');
    if (_lesson != null && _lesson!.videoSource == 'youtube') _videoInputMode = 'youtube';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _youtubeCtrl.dispose();
    _pdfTitleCtrl.dispose();
    _pdfDescCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : null));
  }

  /// Creates the lesson if it doesn't exist yet (so video/PDF uploads have
  /// a lesson_id to attach to), or updates the editable text fields on an
  /// existing one. Returns false (and shows an error) if the title is
  /// missing.
  Future<bool> _ensureSaved() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Lesson title is required.');
      return false;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final duration = int.tryParse(_durationCtrl.text.trim()) ?? 0;
      if (_lesson == null) {
        final id = await _service.createLesson(
          subjectId: widget.subjectId,
          title: title,
          description: _descCtrl.text.trim(),
          duration: duration,
          orderNumber: widget.nextOrderNumber,
        );
        _lesson = await _service.getLesson(id);
      } else {
        await _service.updateLesson(
          _lesson!.id,
          title: title,
          description: _descCtrl.text.trim(),
          duration: duration,
          pdfTitle: _pdfTitleCtrl.text.trim(),
          pdfDescription: _pdfDescCtrl.text.trim(),
        );
        _lesson = await _service.getLesson(_lesson!.id);
      }
      _changed = true;
      return true;
    } catch (e) {
      setState(() => _error = 'Failed to save lesson. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshLesson() async {
    if (_lesson == null) return;
    try {
      _lesson = await _service.getLesson(_lesson!.id);
      if (mounted) setState(() {});
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _saveDraft() async {
    final ok = await _ensureSaved();
    if (!ok) return;
    try {
      if (_lesson!.isPublished) {
        await _service.unpublishLesson(_lesson!.id);
      }
      _changed = true;
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _showMessage('Failed to save draft.', isError: true);
    }
  }

  Future<void> _publish() async {
    final ok = await _ensureSaved();
    if (!ok) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await _service.publishLesson(_lesson!.id);
      _changed = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Add at least one video or PDF before publishing.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unpublish() async {
    if (_lesson == null) return;
    setState(() => _saving = true);
    try {
      await _service.unpublishLesson(_lesson!.id);
      _changed = true;
      await _refreshLesson();
    } catch (_) {
      _showMessage('Failed to unpublish lesson.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadVideo() async {
    final saved = await _ensureSaved();
    if (!saved) return;
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp4', 'mov']);
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    final file = File(result.files.single.path!);
    setState(() => _uploadingVideo = true);
    try {
      await _service.uploadLessonVideo(_lesson!.id, file);
      await _refreshLesson();
      _showMessage('Video uploaded.');
    } catch (_) {
      _showMessage('Video upload failed. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _saveYoutubeUrl() async {
    final url = _youtubeCtrl.text.trim();
    if (url.isEmpty) {
      _showMessage('Enter a YouTube URL first.', isError: true);
      return;
    }
    final saved = await _ensureSaved();
    if (!saved) return;
    if (!mounted) return;
    setState(() => _uploadingVideo = true);
    try {
      await _service.setLessonYoutubeVideo(_lesson!.id, url);
      await _refreshLesson();
      _showMessage('YouTube video set.');
    } catch (_) {
      _showMessage('Could not set YouTube video. Check the link and try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _removeVideo() async {
    if (_lesson == null) return;
    final confirmed = await _confirm('Remove video?', 'This removes the video from the lesson.');
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _uploadingVideo = true);
    try {
      await _service.removeLessonVideo(_lesson!.id);
      _youtubeCtrl.clear();
      await _refreshLesson();
      _showMessage('Video removed.');
    } catch (_) {
      _showMessage('Failed to remove video.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _pickAndUploadPdf() async {
    final saved = await _ensureSaved();
    if (!saved) return;
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    final file = File(result.files.single.path!);
    setState(() => _uploadingPdf = true);
    try {
      await _service.uploadLessonPdf(_lesson!.id, file);
      await _refreshLesson();
      _showMessage('PDF uploaded.');
    } catch (_) {
      _showMessage('PDF upload failed. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingPdf = false);
    }
  }

  Future<void> _removePdf() async {
    if (_lesson == null) return;
    final confirmed = await _confirm('Remove PDF?', 'This removes the PDF notes from the lesson.');
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _uploadingPdf = true);
    try {
      await _service.removeLessonPdf(_lesson!.id);
      _pdfTitleCtrl.clear();
      _pdfDescCtrl.clear();
      await _refreshLesson();
      _showMessage('PDF removed.');
    } catch (_) {
      _showMessage('Failed to remove PDF.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingPdf = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return result == true;
  }

  void _previewVideo() {
    final lesson = _lesson;
    if (lesson == null) return;
    if (lesson.videoSource == 'youtube' && lesson.youtubeUrl.isNotEmpty) {
      launchUrl(Uri.parse(lesson.youtubeUrl), mode: LaunchMode.externalApplication);
    } else if (lesson.videoUrl.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceVideoViewerScreen(url: lesson.videoUrl, fileName: lesson.title)));
    }
  }

  void _previewPdf() {
    final lesson = _lesson;
    if (lesson == null || lesson.pdfUrl.isEmpty) return;
    final title = _pdfTitleCtrl.text.trim().isNotEmpty ? _pdfTitleCtrl.text.trim() : lesson.title;
    Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(url: lesson.pdfUrl, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: AlertDialog(
        title: Text(_isNew ? 'New Lesson' : 'Edit Lesson'),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_lesson != null) _statusBadge(),
                if (_lesson != null) const SizedBox(height: 12),
                TextField(controller: _titleCtrl, autofocus: _isNew, decoration: const InputDecoration(labelText: 'Title *')),
                const SizedBox(height: 12),
                TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                const SizedBox(height: 12),
                TextField(controller: _durationCtrl, decoration: const InputDecoration(labelText: 'Duration (minutes)'), keyboardType: TextInputType.number),
                const Divider(height: 28),
                _videoSection(),
                const Divider(height: 28),
                _pdfSection(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context, _changed), child: const Text('Cancel')),
          Wrap(
            spacing: 4,
            children: [
              if (_lesson?.isPublished == true)
                TextButton(onPressed: _saving ? null : _unpublish, child: const Text('Unpublish'))
              else
                TextButton(onPressed: _saving ? null : _saveDraft, child: const Text('Save Draft')),
              FilledButton(
                onPressed: _saving ? null : _publish,
                style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Publish'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final published = _lesson!.isPublished;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: published ? AppColors.greenLight : AppColors.orangeLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          published ? 'Published' : 'Draft',
          style: TextStyle(color: published ? AppColors.green : AppColors.orange, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary));

  Widget _videoSection() {
    final lesson = _lesson;
    final hasVideo = lesson?.hasVideo ?? false;
    final isYoutube = hasVideo && lesson!.videoSource == 'youtube';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Video'),
        const SizedBox(height: 8),
        if (hasVideo) ...[
          Row(
            children: [
              Icon(isYoutube ? Icons.smart_display_outlined : Icons.videocam, size: 18, color: AppColors.purple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isYoutube ? 'YouTube video linked' : 'Video uploaded',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isYoutube) ...[
            Row(
              children: [
                Expanded(child: TextField(controller: _youtubeCtrl, decoration: const InputDecoration(labelText: 'YouTube URL', isDense: true))),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Replace',
                  onPressed: _uploadingVideo ? null : _saveYoutubeUrl,
                  icon: _uploadingVideo
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.autorenew, color: AppColors.purple),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: _previewVideo, icon: const Icon(Icons.play_circle_outline, size: 16), label: const Text('Preview')),
                OutlinedButton.icon(
                  onPressed: _uploadingVideo ? null : _removeVideo,
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: _previewVideo, icon: const Icon(Icons.play_circle_outline, size: 16), label: const Text('Preview')),
                OutlinedButton.icon(
                  onPressed: _uploadingVideo ? null : _pickAndUploadVideo,
                  icon: _uploadingVideo
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.autorenew, size: 16),
                  label: Text(_uploadingVideo ? 'Uploading...' : 'Replace'),
                ),
                OutlinedButton.icon(
                  onPressed: _uploadingVideo ? null : _removeVideo,
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                ),
              ],
            ),
        ] else ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'upload', label: Text('Upload Video'), icon: Icon(Icons.upload_file, size: 16)),
              ButtonSegment(value: 'youtube', label: Text('YouTube URL'), icon: Icon(Icons.link, size: 16)),
            ],
            selected: {_videoInputMode},
            onSelectionChanged: (s) => setState(() => _videoInputMode = s.first),
          ),
          const SizedBox(height: 10),
          if (_videoInputMode == 'upload')
            OutlinedButton.icon(
              onPressed: _uploadingVideo ? null : _pickAndUploadVideo,
              icon: _uploadingVideo
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file, size: 16),
              label: Text(_uploadingVideo ? 'Uploading...' : 'Choose video file (mp4/mov)'),
            )
          else
            Row(
              children: [
                Expanded(child: TextField(controller: _youtubeCtrl, decoration: const InputDecoration(labelText: 'YouTube URL', isDense: true))),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _uploadingVideo ? null : _saveYoutubeUrl,
                  icon: _uploadingVideo
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline, color: AppColors.purple),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _pdfSection() {
    final lesson = _lesson;
    final hasPdf = lesson?.hasPdf ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('PDF Notes'),
        const SizedBox(height: 8),
        TextField(controller: _pdfTitleCtrl, decoration: const InputDecoration(labelText: 'PDF Title', isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: _pdfDescCtrl, decoration: const InputDecoration(labelText: 'PDF Description', isDense: true), maxLines: 2),
        const SizedBox(height: 10),
        if (hasPdf) ...[
          Row(
            children: const [
              Icon(Icons.picture_as_pdf_outlined, size: 18, color: AppColors.purple),
              SizedBox(width: 8),
              Text('PDF uploaded', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: _previewPdf, icon: const Icon(Icons.visibility_outlined, size: 16), label: const Text('Preview')),
              OutlinedButton.icon(
                onPressed: _uploadingPdf ? null : _pickAndUploadPdf,
                icon: const Icon(Icons.autorenew, size: 16),
                label: const Text('Replace'),
              ),
              OutlinedButton.icon(
                onPressed: _uploadingPdf ? null : _removePdf,
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                label: const Text('Remove', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
              ),
            ],
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _uploadingPdf ? null : _pickAndUploadPdf,
            icon: _uploadingPdf
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file, size: 16),
            label: Text(_uploadingPdf ? 'Uploading...' : 'Choose PDF file'),
          ),
      ],
    );
  }
}

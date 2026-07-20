import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';

/// Admin-only: manage a course's lessons - create, edit, delete, drag-
/// and-drop reorder, and upload video/PDF/assignment files (via
/// Cloudinary, same pattern as Class Resources uploads elsewhere).
class LessonManagementScreen extends StatefulWidget {
  final int courseId;
  final String courseName;
  const LessonManagementScreen({super.key, required this.courseId, required this.courseName});

  @override
  State<LessonManagementScreen> createState() => _LessonManagementScreenState();
}

class _LessonManagementScreenState extends State<LessonManagementScreen> {
  final CourseService _service = CourseService();
  List<AdminLessonModel> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _lessons = await _service.listLessons(widget.courseId);
    } catch (_) {
      // best-effort
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _lessons.removeAt(oldIndex);
      _lessons.insert(newIndex, item);
    });
    final items = [
      for (var i = 0; i < _lessons.length; i++) {'id': _lessons[i].id, 'order_number': i}
    ];
      try {
      await _service.reorderLessons(widget.courseId, items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));
      _load();
    }
  }

  Future<void> _showLessonDialog({AdminLessonModel? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LessonEditorDialog(
        subjectId: widget.courseId,
        existing: existing,
        service: _service,
        nextOrderNumber: _lessons.length,
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _confirmDeleteLesson(AdminLessonModel lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lesson?'),
        content: Text('Delete "${lesson.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteLesson(lesson.id);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete lesson.')));
    }
  }

  Future<void> _uploadFile(AdminLessonModel lesson, String kind) async {
    final extensions = kind == 'video' ? ['mp4', 'mov'] : ['pdf'];
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading $kind...'), duration: const Duration(seconds: 30)));

    try {
      if (kind == 'video') {
        await _service.uploadLessonVideo(lesson.id, file);
      } else if (kind == 'pdf') {
        await _service.uploadLessonPdf(lesson.id, file);
      } else {
        await _service.uploadLessonAssignment(lesson.id, file);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lessons - ${widget.courseName}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLessonDialog(),
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lessons.isEmpty
              ? const Center(child: Text('No lessons yet. Tap + to add one.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _lessons.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final lesson = _lessons[index];
                    return Card(
                      key: ValueKey(lesson.id),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: CircleAvatar(backgroundColor: AppColors.purpleLight, child: Text('${index + 1}', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700))),
                        title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Row(
                          children: [
                            Text(lesson.duration > 0 ? '${lesson.duration} min' : 'No duration set', style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: lesson.status == 'published' ? AppColors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                lesson.status == 'published' ? 'Published' : 'Draft',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: lesson.status == 'published' ? AppColors.green : AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary)),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _actionChip(Icons.videocam_outlined, lesson.videoUrl.isNotEmpty ? 'Video ✓' : 'Upload Video', () => _uploadFile(lesson, 'video')),
                                    _actionChip(Icons.picture_as_pdf_outlined, lesson.pdfUrl.isNotEmpty ? 'PDF ✓' : 'Upload PDF', () => _uploadFile(lesson, 'pdf')),
                                    _actionChip(Icons.assignment_outlined, lesson.assignmentUrl.isNotEmpty ? 'Assignment ✓' : 'Upload Assignment', () => _uploadFile(lesson, 'assignment')),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _showLessonDialog(existing: lesson),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _confirmDeleteLesson(lesson),
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.purple),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}

// --- Lesson Resource Management (additive) ---
//
// Everything needed to manage a lesson's resources lives in this one
// dialog - title/description, video (upload OR YouTube URL, with
// preview/replace/remove), PDF notes (upload + title/description, with
// preview/replace/remove), and Save Draft / Publish / Unpublish. No
// separate Video/PDF pages are created, per spec.
class _LessonEditorDialog extends StatefulWidget {
  final int subjectId;
  final AdminLessonModel? existing;
  final CourseService service;
  final int nextOrderNumber;

  const _LessonEditorDialog({
    required this.subjectId,
    required this.existing,
    required this.service,
    required this.nextOrderNumber,
  });

  @override
  State<_LessonEditorDialog> createState() => _LessonEditorDialogState();
}

class _LessonEditorDialogState extends State<_LessonEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _durationController;
  late final TextEditingController _pdfTitleController;
  late final TextEditingController _pdfDescController;
  late final TextEditingController _youtubeController;

  int? _lessonId;
  String _videoUrl = '';
  String _videoSource = 'upload'; // 'upload' | 'youtube'
  String _pdfUrl = '';
  String _status = 'draft'; // 'draft' | 'published'

  bool _savingBasic = false;
  bool _uploadingVideo = false;
  bool _uploadingPdf = false;
  bool _publishing = false;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _showVideoPreview = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descController = TextEditingController(text: existing?.description ?? '');
    _durationController = TextEditingController(text: existing != null ? existing.duration.toString() : '');
    _pdfTitleController = TextEditingController(text: existing?.pdfTitle ?? '');
    _pdfDescController = TextEditingController(text: existing?.pdfDescription ?? '');
    _youtubeController = TextEditingController(text: existing?.videoSource == 'youtube' ? existing?.videoUrl ?? '' : '');

    _lessonId = existing?.id;
    _videoUrl = existing?.videoUrl ?? '';
    _videoSource = existing?.videoSource ?? 'upload';
    _pdfUrl = existing?.pdfUrl ?? '';
    _status = existing?.status ?? 'draft';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _durationController.dispose();
    _pdfTitleController.dispose();
    _pdfDescController.dispose();
    _youtubeController.dispose();
    _disposeVideoPreview();
    super.dispose();
  }

  void _disposeVideoPreview() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Creates the lesson (if it doesn't exist yet) or persists the basic
  /// text fields. Returns true on success.
  Future<bool> _saveBasicFields() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _toast('Lesson title is required.');
      return false;
    }
    setState(() => _savingBasic = true);
    try {
      final duration = int.tryParse(_durationController.text.trim()) ?? 0;
      if (_lessonId == null) {
        final id = await widget.service.createLesson(
          subjectId: widget.subjectId,
          title: title,
          description: _descController.text.trim(),
          duration: duration,
          orderNumber: widget.nextOrderNumber,
        );
        if (mounted) setState(() => _lessonId = id);
      } else {
        await widget.service.updateLesson(
          _lessonId!,
          title: title,
          description: _descController.text.trim(),
          duration: duration,
          pdfTitle: _pdfTitleController.text.trim(),
          pdfDescription: _pdfDescController.text.trim(),
        );
      }
      return true;
    } catch (e) {
      _toast('Failed to save lesson.');
      return false;
    } finally {
      if (mounted) setState(() => _savingBasic = false);
    }
  }

  Future<void> _onSaveDraft() async {
    final ok = await _saveBasicFields();
    if (ok) _toast('Saved as draft.');
  }

  Future<void> _onPublish() async {
    if (_videoUrl.isEmpty && _pdfUrl.isEmpty) {
      _toast('Add at least one video or PDF before publishing.');
      return;
    }
    final ok = await _saveBasicFields();
    if (!ok || _lessonId == null) return;
    if (!mounted) return;
    setState(() => _publishing = true);
    try {
      await widget.service.publishLesson(_lessonId!);
      if (mounted) setState(() => _status = 'published');
      _toast('Lesson published.');
    } catch (e) {
      _toast('Failed to publish lesson.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _onUnpublish() async {
    if (_lessonId == null) return;
    final ok = await _saveBasicFields();
    if (!ok) return;
    if (!mounted) return;
    setState(() => _publishing = true);
    try {
      await widget.service.unpublishLesson(_lessonId!);
      if (mounted) setState(() => _status = 'draft');
      _toast('Lesson moved back to draft.');
    } catch (e) {
      _toast('Failed to unpublish lesson.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _pickAndUploadVideo() async {
    if (_lessonId == null) {
      final ok = await _saveBasicFields();
      if (!ok) return;
    }
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp4', 'mov']);
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    final file = File(result.files.single.path!);
    setState(() => _uploadingVideo = true);
    try {
      final url = await widget.service.uploadLessonVideo(_lessonId!, file);
      _disposeVideoPreview();
      if (mounted) {
        setState(() {
          _videoUrl = url;
          _videoSource = 'upload';
          _showVideoPreview = false;
        });
      }
      _toast('Video uploaded.');
    } catch (e) {
      _toast('Video upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _saveYoutubeUrl() async {
    final url = _youtubeController.text.trim();
    if (url.isEmpty) {
      _toast('Paste a YouTube URL first.');
      return;
    }
    if (_lessonId == null) {
      final ok = await _saveBasicFields();
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _uploadingVideo = true);
    try {
      await widget.service.updateLesson(_lessonId!, videoUrl: url, videoSource: 'youtube');
      _disposeVideoPreview();
      if (mounted) {
        setState(() {
          _videoUrl = url;
          _videoSource = 'youtube';
          _showVideoPreview = false;
        });
      }
      _toast('YouTube video saved.');
    } catch (e) {
      _toast('Failed to save YouTube URL.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _removeVideo() async {
    if (_lessonId == null) {
      setState(() {
        _videoUrl = '';
        _youtubeController.clear();
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove video?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.updateLesson(_lessonId!, videoUrl: '', videoSource: 'upload');
      _disposeVideoPreview();
      if (mounted) {
        setState(() {
          _videoUrl = '';
          _videoSource = 'upload';
          _youtubeController.clear();
          _showVideoPreview = false;
        });
      }
      _toast('Video removed.');
    } catch (e) {
      _toast('Failed to remove video.');
    }
  }

  Future<void> _pickAndUploadPdf() async {
    if (_lessonId == null) {
      final ok = await _saveBasicFields();
      if (!ok) return;
    }
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    final file = File(result.files.single.path!);
    setState(() => _uploadingPdf = true);
    try {
      final url = await widget.service.uploadLessonPdf(_lessonId!, file);
      if (mounted) setState(() => _pdfUrl = url);
      _toast('PDF uploaded.');
    } catch (e) {
      _toast('PDF upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingPdf = false);
    }
  }

  Future<void> _removePdf() async {
    if (_lessonId == null) {
      setState(() {
        _pdfUrl = '';
        _pdfTitleController.clear();
        _pdfDescController.clear();
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove PDF?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.updateLesson(_lessonId!, pdfUrl: '', pdfTitle: '', pdfDescription: '');
      if (mounted) {
        setState(() {
          _pdfUrl = '';
          _pdfTitleController.clear();
          _pdfDescController.clear();
        });
      }
      _toast('PDF removed.');
    } catch (e) {
      _toast('Failed to remove PDF.');
    }
  }

  Future<void> _previewVideo() async {
    if (_videoUrl.isEmpty) return;
    if (_videoSource == 'youtube') {
      final uri = Uri.tryParse(_videoUrl);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (_showVideoPreview) {
      setState(() => _showVideoPreview = false);
      return;
    }
    setState(() => _showVideoPreview = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(ApiConstants.resolveMediaUrl(_videoUrl)));
      await controller.initialize();
      if (!mounted) {
        // BUG FIX (controller leak): dispose() has already run and won't
        // run again - if we stored this controller in the fields now, it
        // would never be released. Dispose it directly instead of
        // leaking it.
        await controller.dispose();
        return;
      }
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
      );
      _videoController = controller;
      setState(() {});
    } catch (e) {
      _toast('Could not preview this video.');
      if (mounted) setState(() => _showVideoPreview = false);
    }
  }

  void _previewPdf() {
    if (_pdfUrl.isEmpty) return;
    final title = _pdfTitleController.text.trim().isNotEmpty ? _pdfTitleController.text.trim() : _titleController.text.trim();
    context.push('/pdf-viewer', extra: {'url': ApiConstants.resolveMediaUrl(_pdfUrl), 'title': title});
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null && _lessonId == null;
    final resourcesUnlocked = _lessonId != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isNew ? 'New Lesson' : 'Edit Lesson',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, _lessonId != null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: _titleController, autofocus: isNew, decoration: const InputDecoration(labelText: 'Title *')),
                    const SizedBox(height: 12),
                    TextField(controller: _descController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                    const SizedBox(height: 12),
                    TextField(controller: _durationController, decoration: const InputDecoration(labelText: 'Duration (minutes)'), keyboardType: TextInputType.number),

                    if (!resourcesUnlocked) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                          'Tap "Save Draft" below to unlock video and PDF options for this lesson.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],

                    if (resourcesUnlocked) ...[
                      const SizedBox(height: 20),
                      const Text('Video', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'upload', label: Text('Upload Video'), icon: Icon(Icons.upload_file_rounded, size: 16)),
                          ButtonSegment(value: 'youtube', label: Text('YouTube URL'), icon: Icon(Icons.smart_display_outlined, size: 16)),
                        ],
                        selected: {_videoSource},
                        onSelectionChanged: (s) => setState(() => _videoSource = s.first),
                      ),
                      const SizedBox(height: 10),
                      if (_videoSource == 'upload') ...[
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _uploadingVideo ? null : _pickAndUploadVideo,
                              icon: _uploadingVideo
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(_videoUrl.isNotEmpty && _videoSource == 'upload' ? Icons.refresh_rounded : Icons.upload_file_rounded, size: 16),
                              label: Text(_videoUrl.isNotEmpty && _videoSource == 'upload' ? 'Replace Video' : 'Upload Video'),
                            ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: _youtubeController,
                          decoration: const InputDecoration(labelText: 'YouTube URL', hintText: 'https://www.youtube.com/watch?v=...'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _uploadingVideo ? null : _saveYoutubeUrl,
                              icon: _uploadingVideo
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.link_rounded, size: 16),
                              label: Text(_videoUrl.isNotEmpty && _videoSource == 'youtube' ? 'Replace URL' : 'Save URL'),
                            ),
                          ],
                        ),
                      ],
                      if (_videoUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(onPressed: _previewVideo, icon: const Icon(Icons.play_circle_outline_rounded, size: 18), label: Text(_videoSource == 'youtube' ? 'Open on YouTube' : (_showVideoPreview ? 'Hide Preview' : 'Preview'))),
                            TextButton.icon(onPressed: _removeVideo, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), label: const Text('Remove', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ],
                      if (_showVideoPreview && _videoSource == 'upload') ...[
                        const SizedBox(height: 8),
                        _chewieController == null
                            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                            : AspectRatio(aspectRatio: _chewieController!.aspectRatio ?? 16 / 9, child: Chewie(controller: _chewieController!)),
                      ],

                      const SizedBox(height: 20),
                      const Text('PDF Notes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(controller: _pdfTitleController, decoration: const InputDecoration(labelText: 'PDF Title')),
                      const SizedBox(height: 8),
                      TextField(controller: _pdfDescController, decoration: const InputDecoration(labelText: 'PDF Description'), maxLines: 2),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _uploadingPdf ? null : _pickAndUploadPdf,
                            icon: _uploadingPdf
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(_pdfUrl.isNotEmpty ? Icons.refresh_rounded : Icons.upload_file_rounded, size: 16),
                            label: Text(_pdfUrl.isNotEmpty ? 'Replace PDF' : 'Upload PDF'),
                          ),
                        ],
                      ),
                      if (_pdfUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(onPressed: _previewPdf, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Preview')),
                            TextButton.icon(onPressed: _removePdf, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), label: const Text('Remove', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, _lessonId != null), child: const Text('Close')),
                  const SizedBox(width: 4),
                  if (_status != 'published')
                    FilledButton.tonal(
                      onPressed: _savingBasic ? null : _onSaveDraft,
                      child: _savingBasic ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Draft'),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: _savingBasic ? null : () => _saveBasicFields(),
                      child: _savingBasic ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Changes'),
                    ),
                  const SizedBox(width: 8),
                  if (resourcesUnlocked && _status == 'draft')
                    FilledButton(
                      onPressed: _publishing ? null : _onPublish,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
                      child: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Publish'),
                    ),
                  if (resourcesUnlocked && _status == 'published')
                    FilledButton(
                      onPressed: _publishing ? null : _onUnpublish,
                      style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade700),
                      child: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Unpublish'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

# apply_frontend_highrisk_fixes.ps1
# Run from your FRONTEND project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\frontend)
# Writes: lesson_management_screen.dart + lesson_form_dialog.dart (missing mounted
# checks after async gaps, video/Chewie controller leak) and
# student_live_classes_screen.dart (unguarded substring/split crash risks).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying frontend high-risk file fixes in $root" -ForegroundColor Cyan

# --- lib/screens/courses/lesson_management_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/courses") | Out-Null
$content_lib_screens_courses_lesson_management_screen_dart = @'
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

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/courses/lesson_management_screen.dart"), $content_lib_screens_courses_lesson_management_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/courses/lesson_management_screen.dart" -ForegroundColor Green

# --- lib/screens/courses/lesson_form_dialog.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/courses") | Out-Null
$content_lib_screens_courses_lesson_form_dialog_dart = @'
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

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/courses/lesson_form_dialog.dart"), $content_lib_screens_courses_lesson_form_dialog_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/courses/lesson_form_dialog.dart" -ForegroundColor Green

# --- lib/screens/liveclass/student_live_classes_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_student_live_classes_screen_dart = @'
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/live_class_model.dart';
import '../../services/live_class_service.dart';
import '../../widgets/skeleton_box.dart';
import 'live_class_room_screen.dart';
import 'waiting_room_screen.dart';

/// Student's class schedule - grouped into Upcoming / Past. Each upcoming
/// class shows a live countdown and a check-in button (self-attendance,
/// enabled only during the scheduled window). "Join" is an honest
/// placeholder - there's no video backend yet, so it explains that
/// instead of pretending to connect to a call.
class StudentLiveClassesScreen extends StatefulWidget {
  const StudentLiveClassesScreen({super.key});

  @override
  State<StudentLiveClassesScreen> createState() => _StudentLiveClassesScreenState();
}

class _StudentLiveClassesScreenState extends State<StudentLiveClassesScreen> {
  final LiveClassService _service = LiveClassService();
  List<LiveClassModel> _classes = [];
  AttendanceSummary? _summary;
  bool _isLoading = true;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _classes = await _service.fetchForStudent();
    } catch (e) {
      _error = 'Could not load classes.';
    }
    try {
      _summary = await _service.fetchAttendanceSummary();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.green;
      case 'cancelled':
        return AppColors.error;
      case 'missed':
        return AppColors.textSecondary;
      default:
        return AppColors.blue;
    }
  }

  String _countdownText(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'Starting now';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// BUG FIX: was doing its own unguarded
  /// `c.endTime.split(':').map(int.parse)` - if endTime is empty (the
  /// model defaults it to '' when the backend omits the field) or
  /// malformed, split(':') returns [''] and int.parse('') throws a
  /// FormatException, crashing this screen. LiveClassModel.dateTime/
  /// endDateTime already do this exact parsing safely (wrapped in
  /// try/catch, returning null on failure) - reuse those instead of
  /// re-implementing the unsafe version here.
  bool _isWithinWindow(LiveClassModel c) {
    final start = c.dateTime;
    final end = c.endDateTime;
    if (start == null || end == null) return false;
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  /// BUG FIX: HH:MM:SS time strings from the backend can be empty ('')
  /// when a field is missing - the previous direct `.substring(0, 5)`
  /// calls would throw a RangeError on anything shorter than 5
  /// characters. Falls back to the raw (possibly empty) string instead
  /// of crashing.
  String _shortTime(String time) => time.length >= 5 ? time.substring(0, 5) : time;

  Future<void> _join(LiveClassModel c) async {
    if (c.meetingStatus != 'live') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WaitingRoomScreen(liveClass: c)));
      _load();
      return;
    }
    try {
      final session = await _service.joinClass(c.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClassRoomScreen(
            classId: c.id,
            url: session.url,
            token: session.token,
            classTitle: c.title,
            subjectName: c.subjectName,
            lessonTitle: c.lessonTitle,
            description: c.description,
            subjectId: c.subjectId,
            scheduledStart: c.dateTime,
            scheduledEnd: c.endDateTime,
            isTeacher: false,
          ),
        ),
      );
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join the class. Please try again.')));
    }
  }

  Future<void> _checkIn(LiveClassModel c) async {
    try {
      final status = await _service.checkIn(c.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'late' ? "Checked in - marked as late." : "Checked in - you're present!")),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in is only available during class time.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _classes.where((c) => c.status == 'scheduled').toList();
    final others = _classes.where((c) => c.status != 'scheduled').toList();

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Live Classes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(18))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!))])
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_summary != null) _buildAttendanceSummary(_summary!),
                      const SizedBox(height: 20),
                      if (upcoming.isNotEmpty) ...[
                        const Text('Upcoming', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 10),
                        ...upcoming.map(_buildUpcomingCard),
                        const SizedBox(height: 20),
                      ],
                      if (others.isNotEmpty) ...[
                        const Text('Past Classes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 10),
                        ...others.map(_buildPastCard),
                      ],
                      if (_classes.isEmpty) const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No classes scheduled yet.', style: TextStyle(color: AppColors.textSecondary)))),
                    ],
                  ),
      ),
    );
  }

  Widget _buildAttendanceSummary(AttendanceSummary s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.fact_check_rounded, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.percentage.toStringAsFixed(0)}% Attendance', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${s.attendedCount}/${s.totalCompletedClasses} classes attended', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingCard(LiveClassModel c) {
    final dt = c.dateTime;
    final withinWindow = _isWithinWindow(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text('${c.subjectName} \u2022 ${c.teacherName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text('${c.classDate} \u2022 ${_shortTime(c.startTime)}-${_shortTime(c.endTime)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          if (dt != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
              child: Text(
                c.meetingStatus == 'live'
                    ? 'Live now'
                    : (withinWindow ? 'In progress' : 'Starts in ${_countdownText(dt)}'),
                style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: withinWindow ? () => _checkIn(c) : null,
                  child: const Text("I'm Present"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: c.meetingStatus == 'live' ? AppColors.green : AppColors.purple),
                  onPressed: () => _join(c),
                  child: Text(c.meetingStatus == 'live' ? 'Join Now' : 'Join Class'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPastCard(LiveClassModel c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _statusColor(c.status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  c.status == 'completed' ? 'Class Ended' : c.status[0].toUpperCase() + c.status.substring(1),
                  style: TextStyle(color: _statusColor(c.status), fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${c.subjectName} \u2022 ${c.teacherName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text('${c.classDate} \u2022 ${_shortTime(c.startTime)}-${_shortTime(c.endTime)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/student_live_classes_screen.dart"), $content_lib_screens_liveclass_student_live_classes_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/student_live_classes_screen.dart" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Run: flutter analyze" -ForegroundColor Yellow
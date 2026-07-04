import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/ai_provider.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/voice_button.dart';

/// Homework Help: student enters a question (+ optional subject and
/// difficulty), and gets back an explanation, step-by-step solution,
/// examples, and tips â€” from the same rule-based engine as chat, plus a
/// simple linear-equation solver for math problems shaped like "2x + 6 = 10".
class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({super.key});

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  final _questionController = TextEditingController();
  String _subject = 'Mathematics';
  String _difficulty = 'Medium';

  static const _subjects = ['Mathematics', 'Science', 'History', 'Programming', 'English'];
  static const _difficulties = ['Easy', 'Medium', 'Hard'];

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_questionController.text.trim().isEmpty) return;
    await context.read<AiProvider>().submitHomework(
          question: _questionController.text.trim(),
          subject: _subject,
          difficulty: _difficulty,
        );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Homework Help')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Question', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _questionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Solve: 2x + 6 = 10',
                    filled: true,
                    fillColor: AppColors.pageBackground,
                    suffixIcon: VoiceButton(onResult: (text) => setState(() => _questionController.text = text)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _dropdown('Subject', _subject, _subjects, (v) => setState(() => _subject = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _dropdown('Difficulty', _difficulty, _difficulties, (v) => setState(() => _difficulty = v!))),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _submit, child: const Text('Get Help')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildResult(provider),
        ],
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: value,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.pageBackground,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(AiProvider provider) {
    if (provider.isLoadingHomework) {
      return Column(
        children: [
          SkeletonBox(height: 100, borderRadius: BorderRadius.circular(18)),
          const SizedBox(height: 12),
          SkeletonBox(height: 100, borderRadius: BorderRadius.circular(18)),
        ],
      );
    }

    if (provider.homeworkError != null) {
      return Text(provider.homeworkError!, style: const TextStyle(color: AppColors.error));
    }

    final result = provider.homeworkResult;
    if (result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Explanation', Icons.lightbulb_outline_rounded, Text(result.explanation, style: const TextStyle(height: 1.5))),
        const SizedBox(height: 14),
        if (result.stepByStep.isNotEmpty)
          _section(
            'Step-by-Step Solution',
            Icons.list_alt_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.stepByStep.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${e.key + 1}. ${e.value}'),
                  )).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (result.examples.isNotEmpty)
          _section(
            'Examples',
            Icons.school_outlined,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.examples.map((e) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('- $e'))).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (result.tips.isNotEmpty)
          _section(
            'Tips',
            Icons.tips_and_updates_outlined,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.tips.map((t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('- $t'))).toList(),
            ),
          ),
      ],
    );
  }

  Widget _section(String title, IconData icon, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 18, color: AppColors.purple), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

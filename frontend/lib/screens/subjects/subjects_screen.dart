import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/subject_provider.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/subject_card.dart';

/// Feature 2: list of subjects within one category (e.g. Academic -> Mathematics).
class SubjectsScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;

  const SubjectsScreen({super.key, required this.categoryId, required this.categoryName});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubjectProvider>().loadSubjects(widget.categoryId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubjectProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: RefreshIndicator(
        onRefresh: () => provider.loadSubjects(widget.categoryId),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(SubjectProvider provider) {
    if (provider.isLoading) {
      return ListView.separated(
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => const SkeletonBox(height: 92),
      );
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(provider.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => provider.loadSubjects(widget.categoryId), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (provider.subjects.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No subjects in this category yet.', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: provider.subjects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final subject = provider.subjects[index];
        return SubjectCard(
          subject: subject,
          onTap: () => context.push('/lessons', extra: {'subjectId': subject.id, 'subjectName': subject.name}),
        );
      },
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/search_provider.dart';

/// Feature 6: live search across categories, subjects, and lessons, with a
/// simple recent-searches history.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<SearchProvider>().search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search courses, subjects, lessons...',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildBody(provider),
      ),
    );
  }

  Widget _buildBody(SearchProvider provider) {
    if (_controller.text.isEmpty && provider.results == null) {
      return _buildHistory(provider);
    }

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Text(provider.errorMessage!, style: const TextStyle(color: AppColors.textSecondary)),
      );
    }

    final results = provider.results;
    if (results == null || results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No results found.', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (results.categories.isNotEmpty) ...[
          _SectionHeader('Categories'),
          ...results.categories.map((c) => ListTile(
                leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
                title: Text(c.name),
                onTap: () => context.push('/subjects', extra: {'categoryId': c.id, 'categoryName': c.name}),
              )),
        ],
        if (results.subjects.isNotEmpty) ...[
          _SectionHeader('Subjects'),
          ...results.subjects.map((s) => ListTile(
                leading: const Icon(Icons.menu_book_outlined, color: AppColors.primary),
                title: Text(s.name),
                subtitle: Text('${s.lessonCount} lessons'),
                onTap: () => context.push('/lessons', extra: {'subjectId': s.id, 'subjectName': s.name}),
              )),
        ],
        if (results.lessons.isNotEmpty) ...[
          _SectionHeader('Lessons'),
          ...results.lessons.map((l) => ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded, color: AppColors.primary),
                title: Text(l.title),
                subtitle: Text('${l.duration} min'),
                onTap: () => context.push('/lesson-player', extra: {'lessonId': l.id}),
              )),
        ],
      ],
    );
  }

  Widget _buildHistory(SearchProvider provider) {
    if (provider.history.isEmpty) {
      return const Center(
        child: Text('Start typing to search for courses.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w600)),
            TextButton(onPressed: provider.clearHistory, child: const Text('Clear')),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: provider.history
              .map((term) => ActionChip(
                    label: Text(term),
                    onPressed: () {
                      _controller.text = term;
                      provider.search(term);
                    },
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

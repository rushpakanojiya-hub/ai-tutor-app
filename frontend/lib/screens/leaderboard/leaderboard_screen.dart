import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/leaderboard_entry_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/leaderboard_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  final LeaderboardService _service = LeaderboardService();
  late TabController _tabController;

  List<LeaderboardEntry> _entries = [];
  bool _loading = true;
  String? _error;

  final _classController = TextEditingController();
  final _sectionController = TextEditingController();

  final _periods = const ['weekly', 'monthly', 'overall'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 2);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _classController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  bool get _canFilter => context.read<AuthProvider>().currentUser?.role != 'student';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _entries = await _service.fetch(
        period: _periods[_tabController.index],
        classFilter: _canFilter ? _classController.text.trim() : null,
        section: _canFilter ? _sectionController.text.trim() : null,
      );
    } catch (e) {
      _error = 'Could not load the leaderboard.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Weekly'), Tab(text: 'Monthly'), Tab(text: 'Overall')],
        ),
      ),
      body: Column(
        children: [
          if (_canFilter) _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _entries.isEmpty
                        ? const Center(child: Text('No entries yet for this period.', style: TextStyle(color: Colors.grey)))
                        : RefreshIndicator(onRefresh: _load, child: _buildList()),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _classController,
              decoration: const InputDecoration(labelText: 'Class', isDense: true, border: OutlineInputBorder()),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _sectionController,
              decoration: const InputDecoration(labelText: 'Section', isDense: true, border: OutlineInputBorder()),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(icon: const Icon(Icons.filter_alt_rounded, color: AppColors.purple), onPressed: _load),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _entries.length,
      itemBuilder: (context, index) => _entryTile(_entries[index]),
    );
  }

  Widget _entryTile(LeaderboardEntry e) {
    final medal = e.rank == 1 ? '\u{1F947}' : (e.rank == 2 ? '\u{1F948}' : (e.rank == 3 ? '\u{1F949}' : null));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: e.isCurrentUser ? AppColors.purple.withOpacity(0.12) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: e.isCurrentUser ? AppColors.purple : Colors.grey.shade200, width: e.isCurrentUser ? 1.5 : 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 22))
                : Text('#${e.rank}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.purple,
            child: Text(e.studentName.isNotEmpty ? e.studentName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.isCurrentUser ? '${e.studentName} (You)' : e.studentName,
                  style: TextStyle(fontWeight: e.isCurrentUser ? FontWeight.w800 : FontWeight.w600, fontSize: 14),
                ),
                if (e.classValue.isNotEmpty || e.section.isNotEmpty)
                  Text('${e.classValue}${e.section.isNotEmpty ? ' - ${e.section}' : ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${e.totalXP} XP', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.purple, fontSize: 13)),
              Text('${e.totalPoints} pts', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

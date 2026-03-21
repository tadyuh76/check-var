import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/check_result.dart';
import '../models/call_result.dart';
import '../models/history_entry.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<HistoryEntry> _newsEntries = [];
  List<HistoryEntry> _callEntries = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEntries();
    HistoryService.instance.listenable?.addListener(_loadEntries);
  }

  @override
  void dispose() {
    HistoryService.instance.listenable?.removeListener(_loadEntries);
    _tabController.dispose();
    super.dispose();
  }

  void _loadEntries() {
    final all = HistoryService.instance.getAll();
    setState(() {
      _newsEntries = all.where((e) => e.type == HistoryType.news).toList();
      _callEntries = all.where((e) => e.type == HistoryType.call).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('history.title'.tr()),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'history.news'.tr()),
            Tab(text: 'history.calls'.tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewsList(),
          _buildCallsList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'history.no_history'.tr(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsList() {
    if (_newsEntries.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _newsEntries.length,
      itemBuilder: (context, index) => _buildNewsCard(_newsEntries[index]),
    );
  }

  Widget _buildCallsList() {
    if (_callEntries.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _callEntries.length,
      itemBuilder: (context, index) => _buildCallCard(_callEntries[index]),
    );
  }

  Widget _buildNewsCard(HistoryEntry entry) {
    final (color, label) = switch (entry.verdict) {
      Verdict.real => (AppTheme.success, 'verdict.real'.tr()),
      Verdict.fake => (AppTheme.danger, 'verdict.fake'.tr()),
      Verdict.uncertain => (AppTheme.warning, 'verdict.uncertain'.tr()),
    };
    final time = _formatTime(entry.timestamp);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HistoryDetailScreen(entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallCard(HistoryEntry entry) {
    final (color, label) = switch (entry.threatLevel) {
      ThreatLevel.safe => (AppTheme.success, 'threat.safe'.tr()),
      ThreatLevel.suspicious => (AppTheme.warning, 'threat.suspicious'.tr()),
      ThreatLevel.scam => (AppTheme.danger, 'threat.scam'.tr()),
    };
    final time = _formatTime(entry.timestamp);
    final patternsText = entry.patterns.isNotEmpty
        ? 'call_history.detected'.tr(args: [entry.patterns.join(', ')])
        : 'call_history.no_abnormal'.tr();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HistoryDetailScreen(entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                patternsText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'history.just_now'.tr();
    if (diff.inMinutes < 60) {
      return 'history.minutes_ago'.tr(args: [diff.inMinutes.toString()]);
    }
    if (diff.inHours < 24) {
      return 'history.hours_ago'.tr(args: [diff.inHours.toString()]);
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month.toString().padLeft(2, '0')}';
  }
}

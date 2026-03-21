import 'package:flutter/material.dart';
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
  }

  @override
  void dispose() {
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
        title: const Text('Lịch sử'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tin tức'),
            Tab(text: 'Cuộc gọi'),
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
            'Chưa có lịch sử kiểm tra',
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
      Verdict.real => (AppTheme.success, 'Tin thật'),
      Verdict.fake => (AppTheme.danger, 'Tin giả'),
      Verdict.uncertain => (AppTheme.warning, 'Chưa rõ'),
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
    final bool analyzed = entry.wasAnalyzed;

    final (color, label) = analyzed
        ? switch (entry.threatLevel) {
            ThreatLevel.safe => (AppTheme.success, 'An toàn'),
            ThreatLevel.suspicious => (AppTheme.warning, 'Đáng ngờ'),
            ThreatLevel.scam => (AppTheme.danger, 'Lừa đảo'),
          }
        : (Colors.grey, 'Không phân tích');

    final time = _formatTime(entry.timestamp);

    final subtitleText = analyzed
        ? (entry.patterns.isNotEmpty
            ? 'Phát hiện: ${entry.patterns.join(', ')}'
            : 'Không phát hiện dấu hiệu bất thường')
        : entry.callerNumber ?? 'Số không xác định';

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
                subtitleText,
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
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month.toString().padLeft(2, '0')}';
  }
}

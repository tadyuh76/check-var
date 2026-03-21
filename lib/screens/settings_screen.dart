import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/theme_provider.dart';
import '../services/history_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentLocale = context.locale;
    final isVietnamese = currentLocale.languageCode == 'vi';

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSectionHeader(context, 'settings.interface'.tr()),
          ListTile(
            title: Text('settings.dark_mode'.tr()),
            trailing: Switch(
              value: themeProvider.isDarkMode,
              onChanged: (_) => themeProvider.toggleTheme(),
            ),
          ),
          ListTile(
            title: Text('settings.language'.tr()),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'vi', label: Text('VI')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {isVietnamese ? 'vi' : 'en'},
              onSelectionChanged: (selected) {
                final lang = selected.first;
                context.setLocale(Locale(lang));
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const Divider(),
          _buildSectionHeader(context, 'settings.data'.tr()),
          ListTile(
            title: Text('settings.clear_history'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showClearHistoryDialog(context),
          ),
          const Divider(),
          _buildSectionHeader(context, 'settings.info'.tr()),
          ListTile(
            title: Text('settings.version'.tr()),
            trailing: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  void _showClearHistoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('settings.clear_history'.tr()),
        content: Text('settings.clear_history_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('settings.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () async {
              await HistoryService.instance.clear();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('settings.history_cleared'.tr())),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('settings.delete'.tr()),
          ),
        ],
      ),
    );
  }
}

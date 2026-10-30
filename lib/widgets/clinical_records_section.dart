import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/oneup_config.dart';
import '../providers/auth_provider.dart';
import '../providers/query_provider.dart';
import '../services/clinical_source_store.dart';
import '../services/database_service.dart';
import '../services/oneup_sync_service.dart';
import '../theme/app_palette.dart';

/// Profile control for MCP vs 1up, and the list of connected plans.
class ClinicalRecordsSection extends StatefulWidget {
  const ClinicalRecordsSection({super.key});

  @override
  State<ClinicalRecordsSection> createState() => _ClinicalRecordsSectionState();
}

class _ClinicalRecordsSectionState extends State<ClinicalRecordsSection> {
  final _sync = OneUpSyncService();
  final _database = DatabaseService();
  List<Map<String, Object?>> _connections = [];
  String? _busyId;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final rows = await _database.listOneUpConnections(user.id);
    if (!mounted) return;
    setState(() => _connections = rows);
  }

  Future<void> _setSource(String source) async {
    await context.read<ClinicalSourceStore>().setSource(source);
    if (source == 'mcp' && mounted) {
      await context.read<QueryProvider>().mcpClient.initialize();
    }
  }

  Future<void> _addProvider() async {
    final choice = await showModalBottomSheet<OneUpProviderChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _AddProviderSheet(),
    );
    if (choice == null || !mounted) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _adding = true);
    final result = await _sync.connect(userId: user.id, choice: choice);
    if (!mounted) return;
    setState(() => _adding = false);
    _showResult(result, choice.displayName);
    await _load();
  }

  Future<void> _refresh(Map<String, Object?> row) async {
    final id = row['id'] as String;
    final status = row['status'] as String? ?? '';
    setState(() => _busyId = id);
    final OneUpSyncResult result;
    if (status == 'needs_reconnect') {
      final user = context.read<AuthProvider>().currentUser;
      if (user == null) return;
      result = await _sync.connect(
        userId: user.id,
        existingConnectionId: id,
        syncIntervalHours: row['sync_interval_hours'] as int? ?? 24,
        choice: OneUpProviderChoice(
          displayName: row['display_name'] as String? ?? 'Provider',
          kind: row['kind'] as String? ?? 'health-plan',
          authorizeUrl: row['authorize_url'] as String? ?? '',
        ),
      );
    } else {
      result = await _sync.refreshConnection(id);
    }
    if (!mounted) return;
    setState(() => _busyId = null);
    _showResult(result, row['display_name'] as String? ?? 'Provider');
    await _load();
  }

  void _showResult(OneUpSyncResult result, String name) {
    if (result.cancelled) return;
    final text = result.message ??
        (result.status == 'incomplete'
            ? '$name signed in, but the chart download was incomplete. Use Refresh.'
            : '$name is connected.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final source = context.watch<ClinicalSourceStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Clinical records',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppPalette.ink,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          source.showsToggle
              ? 'Apple Health stays on. Choose where clinic records come from.'
              : 'Clinic records come from 1up. Apple Health stays on.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
        ),
        const SizedBox(height: 12),
        if (source.showsToggle)
          Container(
            decoration: BoxDecoration(
              color: AppPalette.card,
              borderRadius: BorderRadius.circular(AppPalette.radius),
              border: Border.all(color: AppPalette.border),
            ),
            child: RadioGroup<String>(
              groupValue: source.value,
              onChanged: (value) {
                if (value != null) _setSource(value);
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'mcp',
                    activeColor: AppPalette.gold,
                    title: Text('FHIR MCP server'),
                    subtitle: Text('Fetch Data downloads the chart'),
                  ),
                  Divider(height: 1, color: AppPalette.border),
                  RadioListTile<String>(
                    value: 'oneup',
                    activeColor: AppPalette.gold,
                    title: Text('1up Health'),
                    subtitle: Text('Each plan is its own sign-in'),
                  ),
                ],
              ),
            ),
          ),
        if (source.usesOneUp) ...[
          const SizedBox(height: 16),
          if (!OneUpConfig.hasCredentials)
            Text(
              'Sandbox client id is not in this build. Add config/oneup_local.json and rebuild before connecting.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
            ),
          const SizedBox(height: 8),
          for (final row in _connections) _connectionCard(row),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _adding ? null : _addProvider,
            child: _adding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add a provider'),
          ),
        ],
      ],
    );
  }

  Widget _connectionCard(Map<String, Object?> row) {
    final id = row['id'] as String;
    final busy = _busyId == id;
    final status = row['status'] as String? ?? 'incomplete';
    final last = row['last_synced_at'] as String?;
    final hours = row['sync_interval_hours'] as int? ?? 24;
    final statusLabel = switch (status) {
      'connected' => 'Connected',
      'needs_reconnect' => 'Reconnect',
      _ => 'Sync incomplete',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['display_name'] as String? ?? 'Provider',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink),
            ),
            const SizedBox(height: 4),
            Text(
              last == null ? statusLabel : '$statusLabel · last sync $last',
              style: const TextStyle(color: AppPalette.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: hours,
              items: const [
                DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                DropdownMenuItem(value: 24, child: Text('Every 24 hours')),
                DropdownMenuItem(value: 168, child: Text('Every week')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                await _database.updateOneUpInterval(id, value);
                await _load();
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => _refresh(row),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(status == 'needs_reconnect' ? 'Reconnect' : 'Refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddProviderSheet extends StatefulWidget {
  const _AddProviderSheet();

  @override
  State<_AddProviderSheet> createState() => _AddProviderSheetState();
}

class _AddProviderSheetState extends State<_AddProviderSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = OneUpProviderChoice.sandboxChoices
        .where((choice) => choice.displayName.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a provider',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick the plan here. The next screen is 1up’s sign-in. MyWellWallet does not see that password.',
            style: TextStyle(color: AppPalette.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(hintText: 'Search plans'),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No matching plan in this sandbox build.'),
            )
          else
            for (final choice in matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(choice.displayName),
                subtitle: const Text('Health plan'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(choice),
              ),
        ],
      ),
    );
  }
}

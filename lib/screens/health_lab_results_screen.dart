import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_bar_logo.dart';
import 'health_lab_detail_screen.dart';

/// Blood tests from Clinical Health Records (FHIR labs, e.g. Sonora Quest) + persisted rows.
/// Grouped **one row per analyte** (latest value); drill down for clinician-style history table.
class HealthLabResultsScreen extends StatefulWidget {
  const HealthLabResultsScreen({super.key});

  @override
  State<HealthLabResultsScreen> createState() => _HealthLabResultsScreenState();
}

class _HealthLabResultsScreenState extends State<HealthLabResultsScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _latest = [];
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _loading = true);

    final latest = await _db.getHealthLabLatestPerTest(user.id);
    final counts = await _db.getHealthLabCountsByGroup(user.id);

    if (mounted) {
      setState(() {
        _latest = latest;
        _counts = counts;
        _loading = false;
      });
    }
  }

  String _formatValue(Map<String, dynamic> r) {
    final numVal = r['value_numeric'];
    final strVal = r['value_string'] as String?;
    final unit = r['unit'] as String?;
    if (numVal != null) {
      final n = numVal as num;
      final s = n.roundToDouble() == n ? n.toInt().toString() : n.toStringAsFixed(n.abs() >= 100 ? 1 : 2);
      return unit != null && unit.isNotEmpty ? '$s $unit' : s;
    }
    if (strVal != null && strVal.isNotEmpty) return strVal;
    return '—';
  }

  String? _formatReferenceRange(Map<String, dynamic> r) {
    final low = r['reference_range_low'];
    final high = r['reference_range_high'];
    final text = r['reference_range_text'] as String?;
    if (text != null && text.isNotEmpty) return text;
    if (low != null && high != null) {
      return '${(low as num).toStringAsFixed(low == low.roundToDouble() ? 0 : 1)} – '
          '${(high as num).toStringAsFixed(high == high.roundToDouble() ? 0 : 1)}';
    }
    if (low != null) return '≥ ${(low as num).toStringAsFixed(1)}';
    if (high != null) return '≤ ${(high as num).toStringAsFixed(1)}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _buildUnsupported();
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading: AppBarLogo(
          showBackButton: true,
          onBack: () => context.go('/health'),
        ),
        title: const Text('Lab results'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _latest.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        'Latest value per test',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF64748B),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap a test below to open up to twelve recent draws in a '
                        'compact table—with reference-range flags and comparison to '
                        'the prior reading.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF94A3B8),
                            ),
                      ),
                      const SizedBox(height: 16),
                      ..._latest.map((r) => _labCard(context, r)),
                    ],
                  ),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _labCard(BuildContext context, Map<String, dynamic> r) {
    final key = DatabaseService.labGroupingKey(r);
    final nReads = _counts[key] ?? 1;
    final recorded = r['recorded_at'] as DateTime;
    final lc = r['loinc_code'] as String?;
    final name = r['name'] as String;
    final refRange = _formatReferenceRange(r);
    final src = r['source_name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8E0F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.push(
            '/health/lab-results/detail',
            extra: HealthLabDetailArgs(
              displayName: name,
              loincCode: lc,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  FontAwesomeIcons.vial,
                  color: Color(0xFF2E7D32),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatValue(r),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                        fontSize: 17,
                      ),
                    ),
                    if (refRange != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Ref: $refRange',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    if (lc != null && lc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'LOINC $lc',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (src != null && src.isNotEmpty)
                          Text(
                            src,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          labelStyle: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF475569),
                          ),
                          avatar: Icon(
                            nReads > 1
                                ? Icons.timeline
                                : Icons.fiber_manual_record,
                            size: 14,
                            color: Color(0xFF7B1FA2),
                          ),
                          label: Text(
                            '$nReads reading${nReads == 1 ? '' : 's'} on device',
                          ),
                          backgroundColor: const Color(0xFFF8FAFC),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Latest: ${DateFormat.yMMMEd().add_jm().format(recorded)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap for history table',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupported() {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading:
            AppBarLogo(showBackButton: true, onBack: () => context.go('/health')),
        title: const Text('Lab results'),
      ),
      body: const Center(
        child: Text('Apple Health is only available on iPhone.'),
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FontAwesomeIcons.vial, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No lab results synced yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Connect Apple Health under Profile, use Sync now, and allow Clinical '
              'Health Records—lab results. Blood tests added by labs such as Sonora '
              'Quest appear after Apple imports them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

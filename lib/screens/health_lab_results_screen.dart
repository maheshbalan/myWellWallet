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

/// Blood test / lab results (e.g. from Apple Health, Quest, Sonora Quest).
/// Shown in decreasing chronological order.
class HealthLabResultsScreen extends StatefulWidget {
  const HealthLabResultsScreen({super.key});

  @override
  State<HealthLabResultsScreen> createState() => _HealthLabResultsScreenState();
}

class _HealthLabResultsScreenState extends State<HealthLabResultsScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _results = [];
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
    // getHealthLabResults already returns in recorded_at DESC order
    final list = await _db.getHealthLabResults(user.id, limit: 200);
    if (mounted) {
      setState(() {
        _results = list;
        _loading = false;
      });
    }
  }

  String _formatValue(Map<String, dynamic> r) {
    final numVal = r['value_numeric'];
    final strVal = r['value_string'] as String?;
    final unit = r['unit'] as String?;
    if (numVal != null) {
      final s = (numVal as num).toStringAsFixed(2);
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
    if (low != null && high != null) return '${(low as num).toStringAsFixed(1)} – ${(high as num).toStringAsFixed(1)}';
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
        title: const Text('Blood test results'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      final name = r['name'] as String;
                      final source = r['source_name'] as String?;
                      final recorded = r['recorded_at'] as DateTime;
                      final refRange = _formatReferenceRange(r);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: const Color(0xFFE8F5E9),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFC8E6C9)),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFC8E6C9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(FontAwesomeIcons.vial, color: Color(0xFF2E7D32), size: 22),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                _formatValue(r),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                  fontSize: 16,
                                ),
                              ),
                              if (refRange != null)
                                Text(
                                  'Ref: $refRange',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              if (source != null && source.isNotEmpty)
                                Text(
                                  source,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              Text(
                                DateFormat.yMMMd().add_jm().format(recorded),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _buildUnsupported() {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading: AppBarLogo(showBackButton: true, onBack: () => context.go('/health')),
        title: const Text('Blood test results'),
      ),
      body: const Center(
        child: Text('Apple Health is only available on iPhone.'),
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FontAwesomeIcons.vial, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No blood test results yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Results from Apple Health (e.g. Quest, Sonora Quest) or from your health records will appear here, newest first.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

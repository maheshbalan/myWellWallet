import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../widgets/app_bar_logo.dart';
import '../widgets/app_bottom_nav.dart';

/// Passed via [GoRouteState.extra] for lab drill-down.
class HealthLabDetailArgs {
  HealthLabDetailArgs({
    required this.displayName,
    this.loincCode,
  });

  final String displayName;
  final String? loincCode;
}

/// Tabular trend view (last readings) suitable for clinician review at a glance.
class HealthLabDetailScreen extends StatefulWidget {
  const HealthLabDetailScreen({super.key, required this.args});

  final HealthLabDetailArgs args;

  @override
  State<HealthLabDetailScreen> createState() => _HealthLabDetailScreenState();
}

class _HealthLabDetailScreenState extends State<HealthLabDetailScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _rows = [];
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
    final list = await _db.getHealthLabHistoryForTest(
      user.id,
      testName: widget.args.displayName,
      loincCode: widget.args.loincCode,
      limit: 12,
    );
    if (mounted) {
      setState(() {
        _rows = list;
        _loading = false;
      });
    }
  }

  String _formatCellValue(Map<String, dynamic> r) {
    final n = r['value_numeric'];
    final s = r['value_string'] as String?;
    final u = r['unit'] as String?;
    if (n != null) {
      final num v = n as num;
      final t = _formatSmartNumber(v);
      return u != null && u.isNotEmpty ? '$t $u' : t;
    }
    if (s != null && s.isNotEmpty) return s;
    return '—';
  }

  String _formatSmartNumber(num n) {
    if (n.roundToDouble() == n) return n.toInt().toString();
    return n.abs() >= 100 ? n.toStringAsFixed(1) : n.toStringAsFixed(2);
  }

  String _refBrief(Map<String, dynamic> r) {
    final t = r['reference_range_text'] as String?;
    if (t != null && t.isNotEmpty) return t;
    final lo = r['reference_range_low'];
    final hi = r['reference_range_high'];
    if (lo != null && hi != null) {
      return '${(lo as num).toStringAsFixed(lo is int ? 0 : 1)} – '
          '${(hi as num).toStringAsFixed(hi is int ? 0 : 1)}';
    }
    if (lo != null) return '≥ ${(lo as num).toStringAsFixed(1)}';
    if (hi != null) return '≤ ${(hi as num).toStringAsFixed(1)}';
    return '—';
  }

  String? _vsPrior(Map<String, dynamic> row, Map<String, dynamic>? older) {
    if (older == null) return null;
    final cur = row['value_numeric'];
    final prev = older['value_numeric'];
    if (cur == null || prev == null) return null;
    final c = cur as num;
    final p = prev as num;
    final d = c - p;
    if (d == 0) return 'Stable';
    final decimals = c.roundToDouble() == c && p.roundToDouble() == p ? 0 : 2;
    if (d > 0) return '↑ ${d.abs().toStringAsFixed(decimals)} vs prior';
    return '↓ ${d.abs().toStringAsFixed(decimals)} vs prior';
  }

  String _flagInterpretation(Map<String, dynamic> r) {
    final v = r['value_numeric'] as num?;
    if (v == null) return '—';
    final lo = r['reference_range_low'] as num?;
    final hi = r['reference_range_high'] as num?;
    if (lo != null && v < lo) return 'Below ref';
    if (hi != null && v > hi) return 'Above ref';
    return 'In range';
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _unsupported();
    final lc = widget.args.loincCode;
    final dateFmt = DateFormat.yMMMEd().add_jm();

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading: AppBarLogo(showBackButton: true, onBack: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.args.displayName,
              style: const TextStyle(fontSize: 17),
            ),
            if (lc != null && lc.isNotEmpty)
              Text(
                'LOINC $lc',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('No history rows for this label yet.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (_, constraints) {
                    final wide = constraints.maxWidth;
                    final tableWidth =
                        wide < 720 ? 720.0 : wide;
                    return Scrollbar(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: tableWidth),
                            child: SelectionArea(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  border: Border.all(
                                      color:
                                          const Color(0xFFE2E8F0)),
                                ),
                                child: DataTableTheme(
                                  data: DataTableThemeData(
                                    headingTextStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                      fontSize: 12,
                                    ),
                                    dividerThickness: 0.5,
                                    dataTextStyle: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  child: DataTable(
                                    columnSpacing: 16,
                                    horizontalMargin: 12,
                                    headingRowHeight: 40,
                                    dataRowMinHeight: 42,
                                    dataRowMaxHeight: 68,
                                    columns: const [
                                      DataColumn(
                                          label:
                                              Text('Collected')),
                                      DataColumn(label: Text('Result')),
                                      DataColumn(
                                          label: Text(
                                              'Ref range')),
                                      DataColumn(
                                          label: Text(
                                              'Interpret')),
                                      DataColumn(
                                          label: Text(
                                              'Δ vs prior')),
                                      DataColumn(
                                          label: Text('Source')),
                                    ],
                                    rows: List.generate(_rows.length, (i) {
                                      final row = _rows[i];
                                      final older = i + 1 < _rows.length
                                          ? _rows[i + 1]
                                          : null;
                                      final flag =
                                          _flagInterpretation(row);
                                      final interpColor =
                                          flag == 'In range'
                                              ? const Color(0xFF2E7D32)
                                              : const Color(
                                                  0xFFC62828);
                                      final dateStr = row[
                                                  'recorded_at'] !=
                                              null
                                          ? dateFmt.format(row[
                                                  'recorded_at']
                                              as DateTime)
                                          : '—';

                                      final src = row[
                                          'source_name'] as String?;
                                      final delta =
                                          _vsPrior(row, older);
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(
                                              dateStr,
                                              maxLines: 2)),
                                          DataCell(Text(
                                              _formatCellValue(
                                                  row))),
                                          DataCell(Text(
                                              _refBrief(row))),
                                          DataCell(Text(
                                            flag,
                                            style: TextStyle(
                                                color:
                                                    interpColor),
                                          )),
                                          DataCell(Text(
                                            delta ?? '—',
                                            style:
                                                TextStyle(
                                              fontSize: 12,
                                              color:
                                                  delta == null
                                                      ? const Color(
                                                          0xFF94A3B8)
                                                      : const Color(
                                                          0xFF475569),
                                            ),
                                          )),
                                          DataCell(Text(
                                            src ?? '—',
                                            maxLines: 2,
                                            overflow:
                                                TextOverflow
                                                    .ellipsis,
                                          )),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _unsupported() {
    return Scaffold(
      appBar: AppBar(
        leading: AppBarLogo(showBackButton: true, onBack: () => context.pop()),
        title: const Text('Lab trend'),
      ),
      body: const Center(
        child: Text('Apple Health is only available on iPhone.'),
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }
}

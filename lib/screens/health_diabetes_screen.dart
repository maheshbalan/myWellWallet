import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../theme/app_palette.dart';
import '../widgets/app_bar_logo.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/health_search_bar.dart';
import 'health_lab_detail_screen.dart';

/// Latest readings for the labs and vitals used to follow diabetes.
class HealthDiabetesScreen extends StatefulWidget {
  const HealthDiabetesScreen({super.key});

  @override
  State<HealthDiabetesScreen> createState() => _HealthDiabetesScreenState();
}

class _Indicator {
  const _Indicator({
    required this.group,
    required this.title,
    required this.blurb,
    this.loincs = const [],
    this.names = const [],
    this.kind = _Source.lab,
  });

  final String group;
  final String title;
  final String blurb;
  final List<String> loincs;
  final List<String> names;
  final _Source kind;
}

enum _Source { lab, glucose, bloodPressure }

class _HealthDiabetesScreenState extends State<HealthDiabetesScreen> {
  static const _indicators = <_Indicator>[
    _Indicator(
      group: 'Glycemic control',
      title: 'Hemoglobin A1C',
      blurb: 'Average blood sugar over about three months.',
      loincs: ['4548-4', '17856-6', '4549-2'],
      names: ['a1c', 'hba1c', 'hemoglobin a1c', 'glycated', 'glycohemoglobin'],
    ),
    _Indicator(
      group: 'Glycemic control',
      title: 'Blood glucose',
      blurb: 'A lab glucose result from a clinic or a lab company.',
      loincs: ['2339-0', '2345-7', '1558-6', '14749-6', '41653-7', '14771-0'],
      names: ['glucose', 'blood sugar'],
    ),
    _Indicator(
      group: 'Glycemic control',
      title: 'Apple Health glucose',
      blurb: 'Meter or sensor readings synced from Apple Health.',
      kind: _Source.glucose,
    ),
    _Indicator(
      group: 'Kidney',
      title: 'eGFR',
      blurb: 'How well the kidneys filter blood.',
      loincs: ['33914-3', '48642-3', '48643-1', '62238-1', '88294-4'],
      names: ['egfr', 'gfr', 'glomerular'],
    ),
    _Indicator(
      group: 'Kidney',
      title: 'Creatinine',
      blurb: 'A waste product used to judge kidney function.',
      loincs: ['2160-0', '38483-4'],
      names: ['creatinine'],
    ),
    _Indicator(
      group: 'Kidney',
      title: 'Urine albumin',
      blurb: 'Albumin in urine, including the albumin-to-creatinine ratio.',
      loincs: ['14959-1', '30000-4', '32294-1', '9318-7', '14957-5'],
      names: ['albumin', 'microalbumin', 'acr'],
    ),
    _Indicator(
      group: 'Cholesterol and lipids',
      title: 'LDL cholesterol',
      blurb: 'The cholesterol most often tracked for heart risk.',
      loincs: ['13457-7', '18262-6', '2089-1'],
      names: ['ldl'],
    ),
    _Indicator(
      group: 'Cholesterol and lipids',
      title: 'HDL cholesterol',
      blurb: 'The cholesterol that is usually higher when heart risk is lower.',
      loincs: ['2085-9'],
      names: ['hdl'],
    ),
    _Indicator(
      group: 'Cholesterol and lipids',
      title: 'Triglycerides',
      blurb: 'A blood fat that often rises with high sugars.',
      loincs: ['2571-8'],
      names: ['triglyceride'],
    ),
    _Indicator(
      group: 'Cholesterol and lipids',
      title: 'Total cholesterol',
      blurb: 'LDL, HDL, and other cholesterol together.',
      loincs: ['2093-3'],
      names: ['cholesterol'],
    ),
    _Indicator(
      group: 'Blood pressure',
      title: 'Blood pressure',
      blurb: 'The latest systolic and diastolic reading on this phone.',
      kind: _Source.bloodPressure,
    ),
  ];

  final _db = DatabaseService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _labs = [];
  Map<String, dynamic>? _glucose;
  Map<String, dynamic>? _bp;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final labs = await _db.getHealthLabLatestPerTest(user.id);
    final glucose = await _db.getHealthGlucose(user.id, limit: 1);
    final bp = await _db.getHealthBloodPressure(user.id, limit: 1);
    if (!mounted) return;
    setState(() {
      _labs = labs;
      _glucose = glucose.isEmpty ? null : glucose.first;
      _bp = bp.isEmpty ? null : bp.first;
      _loading = false;
    });
  }

  bool _visible(_Indicator indicator, Map<String, dynamic>? lab) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final value = _valueText(indicator, lab).toLowerCase();
    final name = (lab?['name'] as String? ?? '').toLowerCase();
    final hay = '${indicator.group} ${indicator.title} ${indicator.blurb} $name $value'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  Map<String, dynamic>? _matchLab(_Indicator indicator) {
    if (indicator.kind != _Source.lab) return null;
    Map<String, dynamic>? best;
    for (final row in _labs) {
      final loinc = (row['loinc_code'] as String?)?.trim() ?? '';
      final name = (row['name'] as String? ?? '').toLowerCase();
      final loincHit = loinc.isNotEmpty && indicator.loincs.contains(loinc);
      final nameHit = indicator.names.any(name.contains);
      if (indicator.title == 'Total cholesterol' && name.contains('ldl')) continue;
      if (indicator.title == 'Total cholesterol' && name.contains('hdl')) continue;
      if (indicator.title == 'Blood glucose' && (name.contains('a1c') || name.contains('hemoglobin a1c'))) {
        continue;
      }
      if (indicator.title == 'Urine albumin' &&
          !loincHit &&
          !name.contains('urine') &&
          !name.contains('microalbumin') &&
          !name.contains('acr')) {
        continue;
      }
      if (!loincHit && !nameHit) continue;
      final at = row['recorded_at'] as DateTime;
      if (best == null || at.isAfter(best['recorded_at'] as DateTime)) best = row;
    }
    return best;
  }

  String _valueText(_Indicator indicator, Map<String, dynamic>? lab) {
    if (indicator.kind == _Source.glucose) {
      if (_glucose == null) return '';
      final n = _glucose!['value'] as num;
      final unit = _glucose!['unit'] as String? ?? 'mg/dL';
      return '${_num(n)} $unit';
    }
    if (indicator.kind == _Source.bloodPressure) {
      if (_bp == null) return '';
      final s = _bp!['systolic'] as num;
      final d = _bp!['diastolic'] as num;
      return '${s.toStringAsFixed(0)} / ${d.toStringAsFixed(0)} mmHg';
    }
    if (lab == null) return '';
    final n = lab['value_numeric'];
    final s = lab['value_string'] as String?;
    final u = lab['unit'] as String?;
    if (n != null) {
      final text = _num(n as num);
      return u != null && u.isNotEmpty ? '$text $u' : text;
    }
    return s ?? '';
  }

  String _num(num n) {
    if (n.roundToDouble() == n) return n.toInt().toString();
    return n.abs() >= 100 ? n.toStringAsFixed(1) : n.toStringAsFixed(2);
  }

  DateTime? _when(_Indicator indicator, Map<String, dynamic>? lab) {
    if (indicator.kind == _Source.glucose) return _glucose?['recorded_at'] as DateTime?;
    if (indicator.kind == _Source.bloodPressure) return _bp?['recorded_at'] as DateTime?;
    return lab?['recorded_at'] as DateTime?;
  }

  void _open(_Indicator indicator, Map<String, dynamic>? lab) {
    if (indicator.kind == _Source.glucose) {
      context.push('/health/glucose');
      return;
    }
    if (indicator.kind == _Source.bloodPressure) {
      context.push('/health/blood-pressure');
      return;
    }
    if (lab == null) return;
    context.push(
      '/health/lab-results/detail',
      extra: HealthLabDetailArgs(
        displayName: lab['name'] as String,
        loincCode: lab['loinc_code'] as String?,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diabetic health')),
        body: const Center(child: Text('Apple Health is only available on iPhone.')),
      );
    }
    final dateFmt = DateFormat.yMMMd();
    final visible = <_Indicator, Map<String, dynamic>?>{};
    for (final indicator in _indicators) {
      final lab = _matchLab(indicator);
      if (_visible(indicator, lab)) visible[indicator] = lab;
    }

    return Scaffold(
      backgroundColor: AppPalette.cream,
      appBar: AppBar(
        leading: AppBarLogo(showBackButton: true, onBack: () => context.pop()),
        title: const Text('Diabetic health'),
        backgroundColor: AppPalette.cream,
        elevation: 0,
      ),
      body: Column(
        children: [
          HealthSearchBar(
            controller: _search,
            hint: 'Search A1C, kidney, cholesterol…',
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        Text(
                          'Key indicators from the labs and vitals on this phone.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppPalette.muted,
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (visible.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: Text(
                              'No indicators match that search.',
                              style: TextStyle(color: AppPalette.muted),
                            ),
                          )
                        else
                          for (final group in _groupsOf(visible.keys)) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Text(
                                group,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.ink,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            for (final indicator in visible.keys.where((i) => i.group == group))
                              _card(indicator, visible[indicator], dateFmt),
                          ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  List<String> _groupsOf(Iterable<_Indicator> indicators) {
    final seen = <String>[];
    for (final indicator in indicators) {
      if (!seen.contains(indicator.group)) seen.add(indicator.group);
    }
    return seen;
  }

  Widget _card(_Indicator indicator, Map<String, dynamic>? lab, DateFormat dateFmt) {
    final value = _valueText(indicator, lab);
    final when = _when(indicator, lab);
    final missing = value.isEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: missing && indicator.kind == _Source.lab ? null : () => _open(indicator, lab),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                indicator.title,
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink),
              ),
              const SizedBox(height: 4),
              Text(indicator.blurb, style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Text(
                missing ? 'Not in your records yet' : value,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: missing ? AppPalette.hint : AppPalette.ink,
                ),
              ),
              if (when != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    dateFmt.format(when),
                    style: const TextStyle(color: AppPalette.muted, fontSize: 12),
                  ),
                ),
              if (!missing || indicator.kind != _Source.lab)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Tap for the full history',
                    style: TextStyle(color: AppPalette.goldDeep, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../theme/app_palette.dart';
import '../widgets/app_bar_logo.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/vital_trend_chart.dart';

class HealthBloodPressureScreen extends StatefulWidget {
  const HealthBloodPressureScreen({super.key});

  @override
  State<HealthBloodPressureScreen> createState() => _HealthBloodPressureScreenState();
}

class _HealthBloodPressureScreenState extends State<HealthBloodPressureScreen> {
  final _db = DatabaseService();
  List<VitalPoint> _systolic = [];
  List<VitalPoint> _diastolic = [];
  bool _loading = true;
  VitalWindow _window = VitalWindow.day;

  static const double _lowBound = 80;
  static const double _highBound = 120;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final list = await _db.getHealthBloodPressure(user.id, limit: 5000);
    list.sort((a, b) => (a['recorded_at'] as DateTime).compareTo(b['recorded_at'] as DateTime));
    if (mounted) {
      setState(() {
        _systolic = [
          for (final row in list)
            VitalPoint(row['recorded_at'] as DateTime, (row['systolic'] as num).toDouble()),
        ];
        _diastolic = [
          for (final row in list)
            VitalPoint(row['recorded_at'] as DateTime, (row['diastolic'] as num).toDouble()),
        ];
        _loading = false;
      });
    }
  }

  VitalStats _stats(List<VitalPoint> points, VitalWindow window) =>
      VitalStats.from(pointsInWindow(points, window).map((point) => point.value));

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _unsupported();
    final systolic = _stats(_systolic, _window);
    final buckets = bucketPoints(pointsInWindow(_systolic, _window), _window);
    final diastolicBuckets = bucketPoints(pointsInWindow(_diastolic, _window), _window);
    return Scaffold(
      backgroundColor: AppPalette.cream,
      appBar: AppBar(
        leading: AppBarLogo(showBackButton: true, onBack: () => context.go('/health')),
        title: const Text('Blood pressure'),
        backgroundColor: AppPalette.cream,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _systolic.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Guide 80–120 mmHg',
                              style: TextStyle(color: AppPalette.muted, fontWeight: FontWeight.w600),
                            ),
                          ),
                          VitalWindowMenu(
                            value: _window,
                            onChanged: (value) => setState(() => _window = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      VitalTrendChart(
                        points: buckets,
                        secondPoints: diastolicBuckets,
                        average: systolic.average,
                        lowBound: _lowBound,
                        highBound: _highBound,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Dark line is systolic. Gold line is diastolic. The dashed line is the systolic average.',
                          style: TextStyle(color: AppPalette.muted, fontSize: 13),
                        ),
                      ),
                      if (systolic.average != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Average systolic on this graph: ${systolic.average!.toStringAsFixed(0)} mmHg',
                            style: const TextStyle(color: AppPalette.ink, fontWeight: FontWeight.w700),
                          ),
                        ),
                      const SizedBox(height: 16),
                      for (final window in VitalWindow.values) _periodCard(window),
                    ],
                  ),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _periodCard(VitalWindow window) {
    final systolic = _stats(_systolic, window);
    final diastolic = _stats(_diastolic, window);
    String n(double? value) => value == null ? '—' : value.toStringAsFixed(0);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_label(window), style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink)),
            const SizedBox(height: 8),
            _line('Systolic', n(systolic.average), n(systolic.high), n(systolic.low)),
            const SizedBox(height: 6),
            _line('Diastolic', n(diastolic.average), n(diastolic.high), n(diastolic.low)),
          ],
        ),
      ),
    );
  }

  Widget _line(String name, String average, String high, String low) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(name, style: const TextStyle(color: AppPalette.muted))),
        Expanded(child: Text('Avg $average', style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text('High $high', style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text('Low $low', style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    );
  }

  String _label(VitalWindow window) {
    switch (window) {
      case VitalWindow.day:
        return 'Last Day';
      case VitalWindow.week:
        return 'Last Week';
      case VitalWindow.month:
        return 'Last Month';
    }
  }

  Widget _unsupported() => Scaffold(
        appBar: AppBar(
          leading: AppBarLogo(showBackButton: true, onBack: () => context.go('/health')),
          title: const Text('Blood pressure'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.gaugeHigh, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No blood pressure data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Connect Apple Health in Profile to sync.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

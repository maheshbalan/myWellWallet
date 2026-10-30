import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../theme/app_palette.dart';
import '../widgets/app_bar_logo.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/vital_trend_chart.dart';

enum _GlucoseRange { day, week, month }

class HealthGlucoseScreen extends StatefulWidget {
  const HealthGlucoseScreen({super.key});

  @override
  State<HealthGlucoseScreen> createState() => _HealthGlucoseScreenState();
}

class _HealthGlucoseScreenState extends State<HealthGlucoseScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _readings = [];
  bool _loading = true;
  _GlucoseRange _range = _GlucoseRange.day;

  static const double _lowBound = 80;
  static const double _highBound = 180;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final list = await _db.getHealthGlucose(user.id, limit: 20000);
    list.sort((a, b) => (a['recorded_at'] as DateTime).compareTo(b['recorded_at'] as DateTime));
    if (mounted) {
      setState(() {
        _readings = list;
        _loading = false;
      });
    }
  }

  VitalWindow _window(_GlucoseRange range) {
    switch (range) {
      case _GlucoseRange.day:
        return VitalWindow.day;
      case _GlucoseRange.week:
        return VitalWindow.week;
      case _GlucoseRange.month:
        return VitalWindow.month;
    }
  }

  List<VitalPoint> _points(_GlucoseRange range) {
    final window = _window(range);
    final cutoff = vitalWindowCutoff(window);
    return [
      for (final row in _readings)
        if (!(row['recorded_at'] as DateTime).isBefore(cutoff))
          VitalPoint(row['recorded_at'] as DateTime, (row['value'] as num).toDouble()),
    ];
  }

  VitalStats _stats(_GlucoseRange range) => VitalStats.from(_points(range).map((point) => point.value));

  List<VitalPoint> _buckets(_GlucoseRange range) => bucketPoints(_points(range), _window(range));

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _unsupported();
    final selected = _stats(_range);
    final buckets = _buckets(_range);
    return Scaffold(
      backgroundColor: AppPalette.cream,
      appBar: AppBar(
        leading: const AppBarLogo(showBackButton: true),
        title: const Text('Blood glucose'),
        backgroundColor: AppPalette.cream,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _readings.isEmpty
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
                              'Target range 80–180 mg/dL',
                              style: TextStyle(color: AppPalette.muted, fontWeight: FontWeight.w600),
                            ),
                          ),
                          DropdownButton<_GlucoseRange>(
                            value: _range,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(value: _GlucoseRange.day, child: Text('Last Day')),
                              DropdownMenuItem(value: _GlucoseRange.week, child: Text('Last Week')),
                              DropdownMenuItem(value: _GlucoseRange.month, child: Text('Last Month')),
                            ],
                            onChanged: (value) {
                              if (value != null) setState(() => _range = value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      VitalTrendChart(
                        points: buckets,
                        average: selected.average,
                        lowBound: _lowBound,
                        highBound: _highBound,
                      ),
                      if (selected.average != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Average on this graph: ${selected.average!.toStringAsFixed(0)} mg/dL',
                            style: const TextStyle(color: AppPalette.ink, fontWeight: FontWeight.w700),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _statCard('Last Day', _stats(_GlucoseRange.day)),
                      _statCard('Last Week', _stats(_GlucoseRange.week)),
                      _statCard('Last Month', _stats(_GlucoseRange.month)),
                    ],
                  ),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _statCard(String label, VitalStats stats) {
    String n(double? value) => value == null ? '—' : value.toStringAsFixed(0);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink)),
            ),
            Expanded(child: _metric('Average', n(stats.average))),
            Expanded(child: _metric('High', n(stats.high))),
            Expanded(child: _metric('Low', n(stats.low))),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppPalette.muted, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.ink, fontSize: 16)),
      ],
    );
  }

  Widget _unsupported() => Scaffold(
        appBar: AppBar(
          leading: const AppBarLogo(showBackButton: true),
          title: const Text('Blood glucose'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.droplet, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No glucose data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Connect Apple Health in Profile to sync CGM or meter readings.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

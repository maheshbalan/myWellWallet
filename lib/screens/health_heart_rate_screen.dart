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

class HealthHeartRateScreen extends StatefulWidget {
  const HealthHeartRateScreen({super.key});

  @override
  State<HealthHeartRateScreen> createState() => _HealthHeartRateScreenState();
}

class _HealthHeartRateScreenState extends State<HealthHeartRateScreen> {
  final _db = DatabaseService();
  List<VitalPoint> _readings = [];
  bool _loading = true;
  VitalWindow _window = VitalWindow.day;

  static const double _lowBound = 60;
  static const double _highBound = 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final list = await _db.getHealthHeartRate(user.id, limit: 20000);
    list.sort((a, b) => (a['recorded_at'] as DateTime).compareTo(b['recorded_at'] as DateTime));
    if (mounted) {
      setState(() {
        _readings = [
          for (final row in list)
            VitalPoint(row['recorded_at'] as DateTime, (row['value'] as num).toDouble()),
        ];
        _loading = false;
      });
    }
  }

  VitalStats _stats(VitalWindow window) =>
      VitalStats.from(pointsInWindow(_readings, window).map((point) => point.value));

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _unsupported();
    final selected = _stats(_window);
    final buckets = bucketPoints(pointsInWindow(_readings, _window), _window);
    return Scaffold(
      backgroundColor: AppPalette.cream,
      appBar: AppBar(
        leading: const AppBarLogo(showBackButton: true),
        title: const Text('Heart rate'),
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
                              'Guide 60–100 bpm',
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
                        average: selected.average,
                        lowBound: _lowBound,
                        highBound: _highBound,
                      ),
                      if (selected.average != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Average on this graph: ${selected.average!.toStringAsFixed(0)} bpm',
                            style: const TextStyle(color: AppPalette.ink, fontWeight: FontWeight.w700),
                          ),
                        ),
                      const SizedBox(height: 16),
                      for (final window in VitalWindow.values)
                        VitalStatCard(
                          label: _label(window),
                          stats: _stats(window),
                          format: (value) => value.toStringAsFixed(0),
                        ),
                    ],
                  ),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
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
          leading: const AppBarLogo(showBackButton: true),
          title: const Text('Heart rate'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.heartPulse, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No heart rate data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Connect Apple Health in Profile to sync.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
            ),
          ],
        ),
      );
}

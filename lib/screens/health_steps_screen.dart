import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../theme/app_palette.dart';
import '../widgets/app_bar_logo.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/vital_trend_chart.dart';

class HealthStepsScreen extends StatefulWidget {
  const HealthStepsScreen({super.key});

  @override
  State<HealthStepsScreen> createState() => _HealthStepsScreenState();
}

class _HealthStepsScreenState extends State<HealthStepsScreen> {
  final _db = DatabaseService();
  List<VitalPoint> _steps = [];
  List<VitalPoint> _distance = [];
  bool _loading = true;
  VitalWindow _window = VitalWindow.day;
  final _stepsFormat = NumberFormat.decimalPattern();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    final list = await _db.getHealthSteps(user.id, limit: 20000);
    list.sort((a, b) => (a['start_at'] as DateTime).compareTo(b['start_at'] as DateTime));
    if (mounted) {
      setState(() {
        _steps = [
          for (final row in list) VitalPoint(row['start_at'] as DateTime, (row['count'] as num).toDouble()),
        ];
        _distance = [
          for (final row in list)
            if (row['distance_meters'] is num)
              VitalPoint(row['start_at'] as DateTime, (row['distance_meters'] as num).toDouble()),
        ];
        _loading = false;
      });
    }
  }

  List<VitalPoint> _buckets(VitalWindow window) =>
      bucketPoints(pointsInWindow(_steps, window), window, sum: true);

  VitalStats _stats(VitalWindow window) => VitalStats.from(_buckets(window).map((point) => point.value));

  double _km(VitalWindow window) {
    final meters = pointsInWindow(_distance, window).fold<double>(0, (sum, point) => sum + point.value);
    return meters / 1000;
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _unsupported();
    final selected = _stats(_window);
    final buckets = _buckets(_window);
    final km = _km(_window);
    return Scaffold(
      backgroundColor: AppPalette.cream,
      appBar: AppBar(
        leading: const AppBarLogo(showBackButton: true),
        title: const Text('Steps & walking'),
        backgroundColor: AppPalette.cream,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _steps.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _window == VitalWindow.day ? 'Hourly step totals' : 'Daily step totals',
                              style: const TextStyle(color: AppPalette.muted, fontWeight: FontWeight.w600),
                            ),
                          ),
                          VitalWindowMenu(
                            value: _window,
                            onChanged: (value) => setState(() => _window = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      VitalTrendChart(points: buckets, average: selected.average),
                      if (selected.average != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Average on this graph: ${_stepsFormat.format(selected.average!.round())} steps'
                            '${km > 0 ? ' · ${km.toStringAsFixed(1)} km walked' : ''}',
                            style: const TextStyle(color: AppPalette.ink, fontWeight: FontWeight.w700),
                          ),
                        ),
                      const SizedBox(height: 16),
                      for (final window in VitalWindow.values)
                        VitalStatCard(
                          label: _label(window),
                          stats: _stats(window),
                          format: (value) => _stepsFormat.format(value.round()),
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
          title: const Text('Steps & walking'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.shoePrints, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No steps data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Connect Apple Health in Profile to sync.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
            ),
          ],
        ),
      );
}

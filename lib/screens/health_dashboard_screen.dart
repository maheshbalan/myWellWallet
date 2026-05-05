import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_bar_logo.dart';

/// Dashboard for diabetes & heart health: glucose, heart rate, steps, blood pressure.
class HealthDashboardScreen extends StatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _glucose = [];
  List<Map<String, dynamic>> _heartRate = [];
  List<Map<String, dynamic>> _steps = [];
  List<Map<String, dynamic>> _bloodPressure = [];
  List<Map<String, dynamic>> _labLatest = [];
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
    try {
      final g = await _db.getHealthGlucose(user.id, limit: 1);
      final h = await _db.getHealthHeartRate(user.id, limit: 1);
      final s = await _db.getHealthSteps(user.id, limit: 7);
      final b = await _db.getHealthBloodPressure(user.id, limit: 1);
      final labs = await _db.getHealthLabLatestPerTest(user.id);
      if (mounted) {
        setState(() {
          _glucose = g;
          _heartRate = h;
          _steps = s;
          _bloodPressure = b;
          _labLatest = labs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        appBar: AppBar(
          leading: const AppBarLogo(showBackButton: false),
          title: const Text('Health'),
        ),
        body: const Center(
          child: Text('Apple Health is only available on iPhone. Connect in Profile on an iOS device.'),
        ),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading: const AppBarLogo(showBackButton: true),
        title: const Text('Health'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diabetes & heart health',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                    const SizedBox(height: 16),
                    _SummaryCard(
                      title: 'Blood glucose',
                      subtitle: 'CGM / meter',
                      value: _glucose.isNotEmpty
                          ? '${(_glucose.first['value'] as num).toStringAsFixed(0)} mg/dL'
                          : '—',
                      trend: _glucose.isNotEmpty ? _glucoseTrend(_glucose.first['value'] as num) : null,
                      icon: FontAwesomeIcons.droplet,
                      iconBg: const Color(0xFFE3F2FD),
                      iconColor: const Color(0xFF1976D2),
                      onTap: () => context.push('/health/glucose'),
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Heart rate',
                      subtitle: 'Last reading',
                      value: _heartRate.isNotEmpty
                          ? '${(_heartRate.first['value'] as num).toStringAsFixed(0)} bpm'
                          : '—',
                      icon: FontAwesomeIcons.heartPulse,
                      iconBg: const Color(0xFFFFEBEE),
                      iconColor: const Color(0xFFC62828),
                      onTap: () => context.push('/health/heart-rate'),
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Steps & walking',
                      subtitle: _steps.isNotEmpty ? 'Recent days' : 'No data',
                      value: _steps.isNotEmpty
                          ? '${_steps.take(7).fold<int>(0, (s, e) => s + (e['count'] as int))} total'
                          : '—',
                      icon: FontAwesomeIcons.shoePrints,
                      iconBg: const Color(0xFFE8F5E9),
                      iconColor: const Color(0xFF2E7D32),
                      onTap: () => context.push('/health/steps'),
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Blood pressure',
                      subtitle: 'Systolic / diastolic',
                      value: _bloodPressure.isNotEmpty
                          ? '${(_bloodPressure.first['systolic'] as num).toStringAsFixed(0)} / ${(_bloodPressure.first['diastolic'] as num).toStringAsFixed(0)} mmHg'
                          : '—',
                      trend: _bloodPressure.isNotEmpty
                          ? _bpTrend(
                              _bloodPressure.first['systolic'] as num,
                              _bloodPressure.first['diastolic'] as num,
                            )
                          : null,
                      icon: FontAwesomeIcons.gaugeHigh,
                      iconBg: const Color(0xFFF3E5F5),
                      iconColor: const Color(0xFF7B1FA2),
                      onTap: () => context.push('/health/blood-pressure'),
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      title: 'Blood test results',
                      subtitle: 'Sonora Quest, Quest Diagnostics, FHIR labs',
                      value: _labLatest.isEmpty
                          ? 'Connect & sync — Profile'
                          : '${_labLatest.length} tests · ${_labLatest.first['name']}: ${_labPreviewValue(_labLatest.first)}',
                      icon: FontAwesomeIcons.vial,
                      iconBg: const Color(0xFFE8F5E9),
                      iconColor: const Color(0xFF2E7D32),
                      onTap: () => context.push('/health/lab-results'),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  String? _glucoseTrend(num value) {
    if (value < 70) return 'Low';
    if (value > 180) return 'High';
    return 'In range';
  }

  String? _bpTrend(num sys, num dias) {
    if (sys >= 140 || dias >= 90) return 'Elevated';
    if (sys <= 90 && dias <= 60) return 'Low';
    return 'Normal';
  }

  String _labPreviewValue(Map<String, dynamic> r) {
    final numVal = r['value_numeric'];
    final strVal = r['value_string'] as String?;
    final unit = r['unit'] as String?;
    if (numVal != null) {
      final n = numVal as num;
      final s = n.roundToDouble() == n ? '${n.toInt()}' : n.toStringAsFixed(1);
      return unit != null && unit.isNotEmpty ? '$s $unit' : s;
    }
    if (strVal != null && strVal.isNotEmpty) return strVal;
    return '—';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.subtitle,
    required this.value,
    this.trend,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final String? trend;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8E0F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF7B1FA2),
                          ),
                    ),
                    if (trend != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          trend!,
                          style: TextStyle(
                            fontSize: 12,
                            color: trend == 'In range' || trend == 'Normal'
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                            fontWeight: FontWeight.w500,
                          ),
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
}

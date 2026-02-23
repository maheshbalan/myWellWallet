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

class HealthBloodPressureScreen extends StatefulWidget {
  const HealthBloodPressureScreen({super.key});

  @override
  State<HealthBloodPressureScreen> createState() => _HealthBloodPressureScreenState();
}

class _HealthBloodPressureScreenState extends State<HealthBloodPressureScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _readings = [];
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
    final list = await _db.getHealthBloodPressure(user.id, limit: 100);
    list.sort((a, b) => (b['recorded_at'] as DateTime).compareTo(a['recorded_at'] as DateTime));
    if (mounted) {
      setState(() {
        _readings = list;
        _loading = false;
      });
    }
  }

  String _bpCategory(num sys, num dias) {
    if (sys >= 140 || dias >= 90) return 'Elevated';
    if (sys >= 130 || dias >= 80) return 'High normal';
    if (sys <= 90 && dias <= 60) return 'Low';
    return 'Normal';
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
        title: const Text('Blood pressure'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _readings.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _readings.length,
                    itemBuilder: (_, i) {
                      final r = _readings[i];
                      final sys = r['systolic'] as num;
                      final dias = r['diastolic'] as num;
                      final recorded = r['recorded_at'] as DateTime;
                      final category = _bpCategory(sys, dias);
                      final isElevated = category == 'Elevated' || category == 'High normal';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: const Color(0xFFF3E5F5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE1BEE7)),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE1BEE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(FontAwesomeIcons.gaugeHigh, color: Color(0xFF7B1FA2), size: 22),
                          ),
                          title: Text(
                            '${sys.toStringAsFixed(0)} / ${dias.toStringAsFixed(0)} mmHg',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
                          ),
                          subtitle: Text(
                            '${DateFormat.yMMMd().add_Hm().format(recorded)} · $category',
                            style: TextStyle(
                              color: isElevated ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
    );
  }

  Widget _buildUnsupported() => Scaffold(
        appBar: AppBar(
          leading: AppBarLogo(
            showBackButton: true,
            onBack: () => context.go('/health'),
          ),
          title: const Text('Blood pressure'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.gaugeHigh, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No blood pressure data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Connect Apple Health in Profile to sync.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B))),
          ],
        ),
      );
}

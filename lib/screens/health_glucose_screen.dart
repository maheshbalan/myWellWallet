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

class HealthGlucoseScreen extends StatefulWidget {
  const HealthGlucoseScreen({super.key});

  @override
  State<HealthGlucoseScreen> createState() => _HealthGlucoseScreenState();
}

class _HealthGlucoseScreenState extends State<HealthGlucoseScreen> {
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
    final list = await _db.getHealthGlucose(user.id, limit: 100);
    list.sort((a, b) => (b['recorded_at'] as DateTime).compareTo(a['recorded_at'] as DateTime));
    if (mounted) {
      setState(() {
        _readings = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _buildUnsupported();
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        leading: const AppBarLogo(showBackButton: true),
        title: const Text('Blood glucose'),
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
                      final value = r['value'] as num;
                      final recorded = r['recorded_at'] as DateTime;
                      final trend = value < 70 ? 'Low' : value > 180 ? 'High' : 'In range';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: const Color(0xFFF5F3FF),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE8E0F0)),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(FontAwesomeIcons.droplet, color: Color(0xFF1976D2), size: 22),
                          ),
                          title: Text(
                            '${value.toStringAsFixed(0)} mg/dL',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: Text(
                            '${DateFormat.yMMMd().format(recorded)} · $trend',
                            style: TextStyle(
                              color: trend == 'In range' ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
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
          leading: const AppBarLogo(showBackButton: true),
          title: const Text('Blood glucose'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.droplet, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No glucose data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Connect Apple Health in Profile to sync CGM/meter readings.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B))),
          ],
        ),
      );
}

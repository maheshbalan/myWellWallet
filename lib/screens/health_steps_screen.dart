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

class HealthStepsScreen extends StatefulWidget {
  const HealthStepsScreen({super.key});

  @override
  State<HealthStepsScreen> createState() => _HealthStepsScreenState();
}

class _HealthStepsScreenState extends State<HealthStepsScreen> {
  final _db = DatabaseService();
  List<Map<String, dynamic>> _entries = [];
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
    final list = await _db.getHealthSteps(user.id, limit: 60);
    list.sort((a, b) => (b['start_at'] as DateTime).compareTo(a['start_at'] as DateTime));
    if (mounted) {
      setState(() {
        _entries = list;
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
        title: const Text('Steps & walking'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final count = e['count'] as int;
                      final start = e['start_at'] as DateTime;
                      final dist = e['distance_meters'] as double?;
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
                            child: const Icon(FontAwesomeIcons.shoePrints, color: Color(0xFF2E7D32), size: 22),
                          ),
                          title: Text(
                            '$count steps',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
                          ),
                          subtitle: Text(
                            '${DateFormat.yMMMd().format(start)}${dist != null ? ' · ${(dist / 1000).toStringAsFixed(2)} km' : ''}',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
          title: const Text('Steps'),
        ),
        body: const Center(child: Text('Apple Health is only on iPhone.')),
        bottomNavigationBar: const AppBottomNav(currentPath: '/health'),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.shoePrints, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No steps data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Connect Apple Health in Profile to sync.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B))),
          ],
        ),
      );
}

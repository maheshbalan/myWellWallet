import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/clinical_source_store.dart';
import '../theme/app_palette.dart';

/// Bottom navigation bar with medical-themed iconography (design-reference style).
/// Use on Home, Fetch Data, and Profile screens for consistent navigation.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentPath,
  });

  final String currentPath;

  int _selectedIndex(bool showFetchData) {
    if (currentPath == '/profile') return showFetchData ? 3 : 2;
    if (currentPath.startsWith('/health')) return showFetchData ? 2 : 1;
    if (showFetchData && currentPath == '/fetch-data') return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final showFetchData = context.watch<ClinicalSourceStore>().showsFetchData;
    final selected = _selectedIndex(showFetchData);
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.cream,
        border: Border(top: BorderSide(color: AppPalette.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.medical_services_outlined,
                label: 'Home',
                selected: selected == 0,
                onTap: () {
                  if (selected != 0) context.go('/');
                },
              ),
              if (showFetchData)
                _NavItem(
                  icon: Icons.download_for_offline_outlined,
                  label: 'Fetch Data',
                  selected: selected == 1,
                  onTap: () {
                    if (selected != 1) context.go('/fetch-data');
                  },
                ),
              _NavItem(
                icon: Icons.favorite_border,
                label: 'Health',
                selected: selected == (showFetchData ? 2 : 1),
                onTap: () {
                  if (selected != (showFetchData ? 2 : 1)) context.go('/health');
                },
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                selected: selected == (showFetchData ? 3 : 2),
                onTap: () {
                  if (selected != (showFetchData ? 3 : 2)) context.go('/profile');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const selectedBg = AppPalette.goldSoft;
    const selectedIcon = AppPalette.ink;
    const unselectedIcon = AppPalette.muted;
    final color = selected ? selectedIcon : unselectedIcon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

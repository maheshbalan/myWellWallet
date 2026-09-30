import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_palette.dart';

/// Bottom navigation bar with medical-themed iconography (design-reference style).
/// Use on Home, Fetch Data, and Profile screens for consistent navigation.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentPath,
  });

  final String currentPath;

  int get _selectedIndex {
    if (currentPath == '/profile') return 3;
    if (currentPath.startsWith('/health')) return 2;
    if (currentPath == '/fetch-data') return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
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
                selected: _selectedIndex == 0,
                onTap: () {
                  if (_selectedIndex != 0) context.go('/');
                },
              ),
              _NavItem(
                icon: Icons.download_for_offline_outlined,
                label: 'Fetch Data',
                selected: _selectedIndex == 1,
                onTap: () {
                  if (_selectedIndex != 1) context.go('/fetch-data');
                },
              ),
              _NavItem(
                icon: Icons.favorite_border,
                label: 'Health',
                selected: _selectedIndex == 2,
                onTap: () {
                  if (_selectedIndex != 2) context.go('/health');
                },
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                selected: _selectedIndex == 3,
                onTap: () {
                  if (_selectedIndex != 3) context.go('/profile');
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

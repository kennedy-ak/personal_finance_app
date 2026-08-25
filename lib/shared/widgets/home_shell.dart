import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

class HomeShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const HomeShell({super.key, required this.shell});

  void _go(int i) {
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final idx = shell.currentIndex;
    final showFab = idx != 3; // hide on Insights (Ask AI has its own input)
    return Scaffold(
      // Wrapped here rather than at the app root so the sweep only runs behind
      // the signed-in shell — the splash and auth screens have no user to write
      // rows for.
      body: shell,
      floatingActionButton: showFab
          ? FloatingActionButton(
              heroTag: 'home-shell-fab',
              onPressed: () => context.push('/add'),
              backgroundColor: AppColors.seed,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, size: 30),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 68,
        padding: EdgeInsets.zero,
        notchMargin: 8,
        shape: const CircularNotchedRectangle(),
        color: Theme.of(context).cardColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(icon: Icons.dashboard_outlined, sel: Icons.dashboard, label: 'Home', selected: idx == 0, onTap: () => _go(0)),
            _NavItem(icon: Icons.list_alt_outlined, sel: Icons.list_alt, label: 'History', selected: idx == 1, onTap: () => _go(1)),
            const SizedBox(width: 56),
            _NavItem(icon: Icons.bar_chart_outlined, sel: Icons.bar_chart, label: 'Reports', selected: idx == 2, onTap: () => _go(2)),
            _NavItem(icon: Icons.lightbulb_outline, sel: Icons.lightbulb, label: 'Insights', selected: idx == 3, onTap: () => _go(3)),
            _NavItem(icon: Icons.account_balance_outlined, sel: Icons.account_balance, label: 'Accounts', selected: idx == 4, onTap: () => _go(4)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData sel;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.sel, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.seed : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? sel : icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// The bar from the components row: five slots, the middle one carrying both
/// the add button and the Reports destination.
///
/// Add is the action people take most, so it gets the thumb-sized target in
/// the centre. Reports keeps the slot underneath it — a label rather than an
/// icon, because the button is already occupying that space.
class HomeShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const HomeShell({super.key, required this.shell});

  static const _destinations = <_Destination>[
    _Destination(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Home'),
    _Destination(Icons.receipt_long_outlined, Icons.receipt_long, 'History'),
    _Destination(Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
    _Destination(Icons.auto_awesome_outlined, Icons.auto_awesome, 'Insights'),
    _Destination(
        Icons.account_balance_outlined, Icons.account_balance, 'Accounts'),
  ];

  void _go(int i) {
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final idx = shell.currentIndex;
    // Ask AI has its own composer at the bottom of the screen; a floating
    // button would land on top of it.
    final showFab = idx != 3;

    return Scaffold(
      backgroundColor: t.canvas,
      body: shell,
      floatingActionButton: showFab
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: t.canvas, width: 5),
              ),
              child: FloatingActionButton(
                heroTag: 'home-shell-fab',
                onPressed: () => context.push('/add'),
                backgroundColor: t.brand,
                foregroundColor: t.onBrand,
                elevation: 0,
                highlightElevation: 0,
                shape: const CircleBorder(),
                child: const Icon(Icons.add, size: 28),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        height: 66 + MediaQuery.paddingOf(context).bottom,
        padding:
            EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          color: t.navBar,
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              _NavSlot(
                destination: _destinations[i],
                selected: idx == i,
                // The centre slot sits under the add button, so its icon is
                // suppressed and the label alone carries the destination.
                labelOnly: i == 2,
                width: i == 2 ? 76 : null,
                onTap: () => _go(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Destination(this.icon, this.selectedIcon, this.label);
}

class _NavSlot extends StatelessWidget {
  final _Destination destination;
  final bool selected;
  final bool labelOnly;
  final double? width;
  final VoidCallback onTap;

  const _NavSlot({
    required this.destination,
    required this.selected,
    required this.labelOnly,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final color = selected ? t.brandInk : t.inkMuted;

    // The centre label hangs at the foot of the bar, clear of the button
    // sitting over it.
    final Widget content = labelOnly
        ? Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Text(destination.label,
                  style: AppType.navLabel.copyWith(color: color)),
            ),
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? destination.selectedIcon : destination.icon,
                    size: 20, color: color),
                const SizedBox(height: 5),
                Text(destination.label,
                    style: AppType.navLabel.copyWith(color: color)),
              ],
            ),
          );

    final slot = InkWell(
      onTap: onTap,
      child: SizedBox(height: double.infinity, child: content),
    );

    return width == null ? Expanded(child: slot) : SizedBox(width: width, child: slot);
  }
}

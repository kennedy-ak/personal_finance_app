import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/notifications.dart';
import '../../../core/theme.dart';
import '../../../core/theme_mode.dart';
import '../../auth/data/auth_repository.dart';
import '../../categories/data/category_repository.dart';
import '../../insights/data/api_key_store.dart';
import '../../insights/data/daily_tip_service.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';

/// Everything that changes how the app behaves, in four groups.
///
/// Each row says the setting's current value on the right, so the screen can
/// be read without opening anything.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final reminderAsync = ref.watch(reminderProvider);
    final tipNotifAsync = ref.watch(tipNotifProvider);
    final keyAsync = ref.watch(apiKeyProvider);
    final repo = ref.watch(authRepositoryProvider);
    final user = repo.currentUser;

    final bills = (ref.watch(obligationsProvider).value ?? [])
        .where((o) => o.isActive)
        .length;
    final goals =
        (ref.watch(goalsProvider).value ?? []).where((g) => g.isActive).length;
    final activeCategories = (ref.watch(allCategoriesProvider).value ?? [])
        .where((c) => !c.isHidden)
        .length;

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                alignment: Alignment.centerLeft,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
                icon: Icon(Icons.arrow_back, size: 22, color: t.inkMuted),
              ),
            ),
            const SizedBox(height: 12),
            Text('Settings', style: AppType.title.copyWith(color: t.ink)),
            if (user != null) ...[
              const SizedBox(height: 18),
              CediCard(
                child: Row(
                  children: [
                    CategoryGlyph(
                      name: repo.displayName ?? user.email ?? '?',
                      hue: 0,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(repo.displayName ?? 'Signed in',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.rowTitle
                                  .copyWith(fontSize: 15, color: t.ink)),
                          const SizedBox(height: 4),
                          Text(user.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.rowSub
                                  .copyWith(color: t.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),
            _Group(
              label: 'Your money',
              children: [
                _SettingRow(
                  label: 'Commitments & goals',
                  value: bills == 0 && goals == 0
                      ? 'None yet'
                      : '$bills bill${bills == 1 ? '' : 's'} · '
                          '$goals goal${goals == 1 ? '' : 's'}',
                  onTap: () => context.push('/plan'),
                ),
                _SettingRow(
                  label: 'Categories',
                  value: '$activeCategories active',
                  onTap: () => context.push('/categories'),
                ),
              ],
            ),

            const SizedBox(height: 18),
            _Group(
              label: 'Appearance',
              children: const [_ThemeRow()],
            ),

            const SizedBox(height: 18),
            _Group(
              label: 'Reminders',
              children: [
                reminderAsync.when(
                  loading: () => const _LoadingRow(label: 'Daily reminder'),
                  error: (e, _) => const _SettingRow(
                      label: 'Daily reminder', value: 'Unavailable'),
                  data: (r) => _ReminderRow(prefs: r),
                ),
                tipNotifAsync.when(
                  loading: () =>
                      const _LoadingRow(label: 'AI tip notification'),
                  error: (e, _) => const _SettingRow(
                      label: 'AI tip notification', value: 'Unavailable'),
                  data: (r) => _TipNotifRow(prefs: r),
                ),
              ],
            ),

            const SizedBox(height: 18),
            _Group(
              label: 'AI coach',
              children: [
                _SettingRow(
                  label: 'Fallback API key',
                  value: keyAsync.value?.isNotEmpty == true ? 'Set' : 'Not set',
                  detail: keyAsync.value?.isNotEmpty == true
                      ? 'Used only if the server coach is unavailable'
                      : 'The coach runs on the server',
                  onTap: () => _showApiKeySheet(context, ref),
                ),
                _SettingRow(
                  label: 'Older conversations',
                  value: 'Open',
                  detail: 'Everything you have asked the coach',
                  onTap: () => context.push('/ai-history'),
                ),
              ],
            ),

            const SizedBox(height: 22),
            DangerButton(
              label: 'Sign out',
              onPressed: () async {
                final ok = await showDeleteConfirmation(
                  context: context,
                  title: 'Sign out?',
                  message: 'Your data stays on the server. You will need your '
                      'password to get back in.',
                  confirmLabel: 'Sign out',
                  cancelLabel: 'Stay',
                );
                if (ok == true) await repo.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showApiKeySheet(BuildContext context, WidgetRef ref) async {
    final store = ref.read(apiKeyStoreProvider);
    final existing = await store.getKey() ?? '';
    final model = await store.getModel();
    if (!context.mounted) return;

    final keyCtrl = TextEditingController(text: existing);
    final modelCtrl = TextEditingController(text: model);

    final saved = await showEditorSheet<bool>(
      context: context,
      builder: (ctx) {
        final t = CediTokens.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'Fallback API key'),
            const SizedBox(height: 10),
            Text(
              'Only used if the server coach cannot be reached. The key is '
              'stored on this device.',
              style: AppType.bodySmall.copyWith(height: 1.5, color: t.inkMuted),
            ),
            const SizedBox(height: 16),
            SheetField(
              label: 'API key',
              controller: keyCtrl,
              hint: 'sk-…',
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 13),
            SheetField(
              label: 'Model',
              controller: modelCtrl,
              hint: 'gpt-4o-mini',
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Save',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      await store.setKey(keyCtrl.text.trim());
      await store.setModel(modelCtrl.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : modelCtrl.text.trim());
      bumpApiKey(ref);
    }
  }
}

class _Group extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _Group({required this.label, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Eyebrow(label,
                size: 11, color: CediTokens.of(context).inkFaint),
          ),
          RowGroup(children: children),
        ],
      );
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.label,
    required this.value,
    this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppType.rowTitle.copyWith(color: t.ink)),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(detail!,
                        style: AppType.rowSub
                            .copyWith(height: 1.4, color: t.inkMuted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(value,
                style: AppType.label.copyWith(fontSize: 13, color: t.inkMuted)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: t.inkMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Light / Dark / System, remembered across launches.
///
/// Three explicit choices rather than one switch: "System" is a real setting,
/// not the absence of one, and people who want the app pinned to one look
/// should not have to fight their phone for it.
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  static const _modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  static const _labels = ['System', 'Light', 'Dark'];
  static const _icons = [
    Icons.brightness_auto_outlined,
    Icons.light_mode_outlined,
    Icons.dark_mode_outlined,
  ];
  static const _details = [
    'Follows your phone’s appearance setting',
    'Always light, whatever the phone does',
    'Always dark, whatever the phone does',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final mode = ref.watch(themeModeProvider);
    final index = _modes.indexOf(mode);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Theme', style: AppType.rowTitle.copyWith(color: t.ink)),
          const SizedBox(height: 4),
          Text(_details[index],
              style: AppType.rowSub.copyWith(height: 1.4, color: t.inkMuted)),
          const SizedBox(height: 12),
          // Not SegmentedTabs: its track is `card`, the same fill as the
          // RowGroup it would sit in, so the control would have no edges.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: t.recessed,
              borderRadius: Radii.sm,
              border: Border.all(color: t.hairline),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _modes.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          ref.read(themeModeProvider.notifier).set(_modes[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: i == index ? t.brand : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_icons[i],
                                size: 15,
                                color: i == index ? t.onBrand : t.inkMuted),
                            const SizedBox(width: 6),
                            Text(
                              _labels[i],
                              style: AppType.label.copyWith(
                                fontSize: 13,
                                fontWeight: i == index
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: i == index ? t.onBrand : t.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final String label;
  const _LoadingRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: AppType.rowTitle.copyWith(color: t.ink))),
          SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: t.brandInk),
          ),
        ],
      ),
    );
  }
}

/// A row whose value is a switch, with the times it fires underneath when it
/// is on.
class _SwitchRow extends StatelessWidget {
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final List<Widget> expanded;

  const _SwitchRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.expanded = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: AppType.rowTitle.copyWith(color: t.ink)),
                    const SizedBox(height: 4),
                    Text(detail,
                        style: AppType.rowSub
                            .copyWith(height: 1.4, color: t.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: t.onBrand,
                activeTrackColor: t.brand,
                inactiveThumbColor: t.inkMuted,
                inactiveTrackColor: t.track,
              ),
            ],
          ),
        ),
        if (value)
          for (final child in expanded) child,
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeRow(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppType.bodySmall
                      .copyWith(height: 1.0, color: t.inkMuted)),
            ),
            Text(value,
                style: AppType.figureRow.copyWith(fontSize: 13, color: t.ink)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: t.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _TipNotifRow extends ConsumerWidget {
  final TipNotifPrefs prefs;
  const _TipNotifRow({required this.prefs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SwitchRow(
      label: 'AI tip notification',
      detail: prefs.enabled
          ? 'One a day at ${prefs.formatted}'
          : 'Your daily tip on the lock screen',
      value: prefs.enabled,
      onChanged: (v) async {
        final batch = await ref.read(dailyTipServiceProvider).cachedBatch();
        await applyTipNotif(
          ref,
          TipNotifPrefs(enabled: v, hour: prefs.hour, minute: prefs.minute),
          tips: batch?.tips,
        );
      },
      expanded: [
        _TimeRow(
          label: 'Delivery time',
          value: prefs.formatted,
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: prefs.hour, minute: prefs.minute),
            );
            if (picked == null) return;
            final batch = await ref.read(dailyTipServiceProvider).cachedBatch();
            await applyTipNotif(
              ref,
              TipNotifPrefs(
                  enabled: true, hour: picked.hour, minute: picked.minute),
              tips: batch?.tips,
            );
          },
        ),
      ],
    );
  }
}

class _ReminderRow extends ConsumerWidget {
  final ReminderPrefs prefs;
  const _ReminderRow({required this.prefs});

  static const _slotLabels = ['Morning', 'Midday', 'Evening'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SwitchRow(
      label: 'Daily reminder',
      detail: prefs.enabled
          ? '3× a day · ${prefs.summary}'
          : 'Three nudges a day to log what you spent',
      value: prefs.enabled,
      onChanged: (v) => applyReminder(
        ref,
        ReminderPrefs(enabled: v, slots: prefs.slots),
      ),
      expanded: [
        for (var i = 0; i < prefs.slots.length; i++)
          _TimeRow(
            label: _slotLabels[i],
            value: prefs.slots[i].formatted,
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                    hour: prefs.slots[i].hour, minute: prefs.slots[i].minute),
              );
              if (picked == null) return;
              final updated = [...prefs.slots];
              updated[i] = ReminderSlot(picked.hour, picked.minute);
              await applyReminder(
                ref,
                ReminderPrefs(enabled: true, slots: updated),
              );
            },
          ),
        _TimeRow(
          label: 'Send a test notification',
          value: 'Test',
          onTap: () => ref.read(notificationServiceProvider).showTest(),
        ),
      ],
    );
  }
}

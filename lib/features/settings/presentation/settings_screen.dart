import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../../auth/data/auth_repository.dart';
import '../../insights/data/api_key_store.dart';
import '../../insights/data/daily_tip_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminderAsync = ref.watch(reminderProvider);
    final tipNotifAsync = ref.watch(tipNotifProvider);
    final keyAsync = ref.watch(apiKeyProvider);
    final user = ref.watch(authRepositoryProvider).currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.seed,
                  child: Text(
                    (user.email ?? '?').characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(user.email ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Signed in'),
              ),
            ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Your money'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('Commitments & goals'),
              subtitle: const Text('Bills, expected income, money to protect'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/plan'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categories'),
              subtitle: const Text('Add your own, hide the ones you never use'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/categories'),
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Daily reminder'),
          reminderAsync.when(
            loading: () => const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())),
            error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$e'))),
            data: (r) => _ReminderCard(prefs: r),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'AI tip notification'),
          tipNotifAsync.when(
            loading: () => const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())),
            error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$e'))),
            data: (r) => _TipNotifCard(prefs: r),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'AI coach'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Fallback API key'),
                  subtitle: Text(
                    keyAsync.value?.isNotEmpty == true
                        ? 'Set — used only if the server coach is unavailable'
                        : 'Not set — the coach runs on the server',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showApiKeyDialog(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Older conversations'),
                  subtitle: const Text(
                      'Q&A saved before the coach could remember',
                      style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ai-history'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Account'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.expense),
              title: const Text('Sign out',
                  style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.w600)),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApiKeyDialog(BuildContext context, WidgetRef ref) async {
    final store = ref.read(apiKeyStoreProvider);
    final existing = await store.getKey() ?? '';
    final model = await store.getModel();
    if (!context.mounted) return;
    final keyCtrl = TextEditingController(text: existing);
    final modelCtrl = TextEditingController(text: model);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenAI settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key', hintText: 'sk-…', prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model', prefixIcon: Icon(Icons.psychology),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await store.setKey(keyCtrl.text.trim());
      await store.setModel(modelCtrl.text.trim().isEmpty ? 'gpt-4o-mini' : modelCtrl.text.trim());
      bumpApiKey(ref);
    }
  }
}

class _TipNotifCard extends ConsumerWidget {
  final TipNotifPrefs prefs;
  const _TipNotifCard({required this.prefs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('Tip of the day notification',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(prefs.enabled
                ? 'Delivers your AI tip at ${prefs.formatted}'
                : 'Get your daily AI tip on your lock screen'),
            value: prefs.enabled,
            onChanged: (v) async {
              final batch = await ref.read(dailyTipServiceProvider).cachedBatch();
              await applyTipNotif(
                ref,
                TipNotifPrefs(enabled: v, hour: prefs.hour, minute: prefs.minute),
                tips: batch?.tips,
              );
              if (v && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('AI tip will ping at ${prefs.formatted}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          if (prefs.enabled) ...[
            const Divider(height: 1, indent: 64),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Delivery time'),
              trailing: Text(prefs.formatted,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: prefs.hour, minute: prefs.minute),
                );
                if (picked != null) {
                  final batch = await ref.read(dailyTipServiceProvider).cachedBatch();
                  await applyTipNotif(
                    ref,
                    TipNotifPrefs(enabled: true, hour: picked.hour, minute: picked.minute),
                    tips: batch?.tips,
                  );
                }
              },
            ),
            const Divider(height: 1, indent: 64),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text(
                'Pursely generates 5 tips per OpenAI call and queues them — one per day '
                'for 5 days at the time above. Open the app at least once a week so a '
                'fresh batch can be generated.',
                style: TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  final ReminderPrefs prefs;
  const _ReminderCard({required this.prefs});

  static const _slotLabels = ['Morning', 'Midday', 'Evening'];
  static const _slotIcons = [Icons.wb_sunny_outlined, Icons.wb_cloudy_outlined, Icons.nightlight_outlined];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: const Text('Daily reminders',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(prefs.enabled
                ? '3× a day · ${prefs.summary}'
                : 'Get 3 friendly nudges a day to log transactions'),
            value: prefs.enabled,
            onChanged: (v) async {
              await applyReminder(
                ref,
                ReminderPrefs(enabled: v, slots: prefs.slots),
              );
              if (v && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Reminders set: ${prefs.summary}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          if (prefs.enabled) ...[
            const Divider(height: 1, indent: 64),
            for (var i = 0; i < prefs.slots.length; i++) ...[
              ListTile(
                leading: Icon(_slotIcons[i]),
                title: Text(_slotLabels[i]),
                trailing: Text(prefs.slots[i].formatted,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                        hour: prefs.slots[i].hour, minute: prefs.slots[i].minute),
                  );
                  if (picked != null) {
                    final updated = [...prefs.slots];
                    updated[i] = ReminderSlot(picked.hour, picked.minute);
                    await applyReminder(
                      ref,
                      ReminderPrefs(enabled: true, slots: updated),
                    );
                  }
                },
              ),
              if (i < prefs.slots.length - 1) const Divider(height: 1, indent: 64),
            ],
            const Divider(height: 1, indent: 64),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Send a test notification'),
              trailing: const Icon(Icons.send),
              onTap: () async {
                await ref.read(notificationServiceProvider).showTest();
              },
            ),
          ],
        ],
      ),
    );
  }
}

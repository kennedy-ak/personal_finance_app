import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _kEnabled = 'reminder_enabled';
const _kHour = 'reminder_hour';
const _kMinute = 'reminder_minute';
const _kSlotsHours = 'reminder_slot_hours';
const _kSlotsMinutes = 'reminder_slot_minutes';

const _kTipEnabled = 'tip_notif_enabled';
const _kTipHour = 'tip_notif_hour';
const _kTipMinute = 'tip_notif_minute';

const _channelId = 'pursely_reminders';
const _channelName = 'Daily reminders';
const _channelDesc = 'Nudges to log your transactions';
const _reminderIdBase = 2001;
const reminderSlotCount = 3;

const _tipChannelId = 'pursely_tips';
const _tipChannelName = 'AI tip of the day';
const _tipChannelDesc = 'Personalised finance tips powered by AI';
const _tipNotifIdBase = 1002;
const _tipNotifMaxBatch = 7;

const _messages = <Map<String, String>>[
  {
    'title': '💸 30 seconds for your money',
    'body': 'Quick check — log today\'s spending before you forget.',
  },
  {
    'title': '📊 How did today look?',
    'body': 'Tap to record any income or expense from today.',
  },
  {
    'title': '🪙 Tiny habit, big payoff',
    'body': 'Logging today keeps your insights honest. Open Pursely.',
  },
  {
    'title': '👀 What did you spend today?',
    'body': 'Open Pursely and capture it before the day slips away.',
  },
  {
    'title': '🎯 Stay on track',
    'body': 'A 10-second log keeps your savings rate accurate.',
  },
];

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _plugin.initialize(init);
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId, _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _tipChannelId, _tipChannelName,
        description: _tipChannelDesc,
        importance: Importance.high,
      ),
    );
    _initialised = true;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> get permissionGranted async =>
      Permission.notification.isGranted;

  Future<void> cancelDaily() async {
    for (var i = 0; i < reminderSlotCount; i++) {
      await _plugin.cancel(_reminderIdBase + i);
    }
  }

  /// Schedules one daily-repeating notification per slot (different message).
  Future<void> scheduleDailySlots(List<({int hour, int minute})> slots) async {
    await init();
    await cancelDaily();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId, _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final rand = Random();
    final usedIdx = <int>{};
    for (var i = 0; i < slots.length && i < reminderSlotCount; i++) {
      // pick a message that's distinct within this batch
      int mIdx;
      do {
        mIdx = rand.nextInt(_messages.length);
      } while (usedIdx.contains(mIdx) && usedIdx.length < _messages.length);
      usedIdx.add(mIdx);
      final pick = _messages[mIdx];
      final next = _nextInstance(slots[i].hour, slots[i].minute);
      try {
        await _plugin.zonedSchedule(
          _reminderIdBase + i,
          pick['title'],
          pick['body'],
          next,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Reminder $i fell back to inexact: $e');
        await _plugin.zonedSchedule(
          _reminderIdBase + i,
          pick['title'],
          pick['body'],
          next,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    }
  }

  Future<void> cancelTip() async {
    for (var i = 0; i < _tipNotifMaxBatch; i++) {
      await _plugin.cancel(_tipNotifIdBase + i);
    }
  }

  /// Schedules each tip as a one-shot notification, one per day starting today
  /// (or tomorrow if today's [hour:minute] has already passed) at [hour:minute].
  Future<void> scheduleTipBatch({
    required int hour,
    required int minute,
    required List<String> tips,
  }) async {
    await init();
    await cancelTip();
    if (tips.isEmpty) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _tipChannelId, _tipChannelName,
        channelDescription: _tipChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
    );
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    final n = tips.length > _tipNotifMaxBatch ? _tipNotifMaxBatch : tips.length;
    for (var i = 0; i < n; i++) {
      final tip = tips[i];
      final body = tip.length > 220 ? '${tip.substring(0, 217)}…' : tip;
      final when = first.add(Duration(days: i));
      try {
        await _plugin.zonedSchedule(
          _tipNotifIdBase + i,
          '✨ Today\'s money tip',
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Tip $i fell back to inexact: $e');
        await _plugin.zonedSchedule(
          _tipNotifIdBase + i,
          '✨ Today\'s money tip',
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> showTest() async {
    await init();
    await _plugin.show(
      9999,
      '🔔 Reminder test',
      'Notifications work! You\'ll get one daily at your chosen time.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }
}

class ReminderSlot {
  final int hour;
  final int minute;
  const ReminderSlot(this.hour, this.minute);
  String get formatted {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ap = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

class ReminderPrefs {
  final bool enabled;
  final List<ReminderSlot> slots;
  const ReminderPrefs({required this.enabled, required this.slots});

  String get summary => slots.map((s) => s.formatted).join(' · ');
}

class ReminderStore {
  static const _defaults = [
    ReminderSlot(9, 0),
    ReminderSlot(13, 0),
    ReminderSlot(20, 0),
  ];

  Future<ReminderPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    final hours = p.getStringList(_kSlotsHours);
    final mins = p.getStringList(_kSlotsMinutes);
    List<ReminderSlot> slots;
    if (hours != null && mins != null && hours.length == mins.length && hours.length == reminderSlotCount) {
      slots = [
        for (var i = 0; i < hours.length; i++)
          ReminderSlot(int.tryParse(hours[i]) ?? 9, int.tryParse(mins[i]) ?? 0),
      ];
    } else if (p.containsKey(_kHour)) {
      // migrate single-time pref into slot 2 (evening) and pad with defaults
      final h = p.getInt(_kHour) ?? 20;
      final m = p.getInt(_kMinute) ?? 0;
      slots = [
        const ReminderSlot(9, 0),
        const ReminderSlot(13, 0),
        ReminderSlot(h, m),
      ];
    } else {
      slots = _defaults;
    }
    return ReminderPrefs(
      enabled: p.getBool(_kEnabled) ?? false,
      slots: slots,
    );
  }

  Future<void> save(ReminderPrefs r) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, r.enabled);
    await p.setStringList(_kSlotsHours, r.slots.map((s) => s.hour.toString()).toList());
    await p.setStringList(_kSlotsMinutes, r.slots.map((s) => s.minute.toString()).toList());
  }
}

class TipNotifPrefs {
  final bool enabled;
  final int hour;
  final int minute;
  const TipNotifPrefs({required this.enabled, required this.hour, required this.minute});
  String get formatted {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ap = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

class TipNotifStore {
  Future<TipNotifPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return TipNotifPrefs(
      enabled: p.getBool(_kTipEnabled) ?? false,
      hour: p.getInt(_kTipHour) ?? 9,
      minute: p.getInt(_kTipMinute) ?? 0,
    );
  }

  Future<void> save(TipNotifPrefs r) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTipEnabled, r.enabled);
    await p.setInt(_kTipHour, r.hour);
    await p.setInt(_kTipMinute, r.minute);
  }
}

final notificationServiceProvider = Provider((_) => NotificationService());
final reminderStoreProvider = Provider((_) => ReminderStore());
final tipNotifStoreProvider = Provider((_) => TipNotifStore());

final reminderRefreshProvider = StateProvider<int>((_) => 0);
final tipNotifRefreshProvider = StateProvider<int>((_) => 0);

final reminderProvider = FutureProvider<ReminderPrefs>((ref) async {
  ref.watch(reminderRefreshProvider);
  return ref.read(reminderStoreProvider).load();
});

final tipNotifProvider = FutureProvider<TipNotifPrefs>((ref) async {
  ref.watch(tipNotifRefreshProvider);
  return ref.read(tipNotifStoreProvider).load();
});

void bumpReminder(WidgetRef ref) =>
    ref.read(reminderRefreshProvider.notifier).state++;
void bumpTipNotif(WidgetRef ref) =>
    ref.read(tipNotifRefreshProvider.notifier).state++;

Future<void> applyReminder(WidgetRef ref, ReminderPrefs r) async {
  await ref.read(reminderStoreProvider).save(r);
  final svc = ref.read(notificationServiceProvider);
  if (r.enabled) {
    final ok = await svc.permissionGranted || await svc.requestPermission();
    if (ok) {
      await svc.scheduleDailySlots(
        r.slots.map((s) => (hour: s.hour, minute: s.minute)).toList(),
      );
    }
  } else {
    await svc.cancelDaily();
  }
  bumpReminder(ref);
}

Future<void> applyTipNotif(WidgetRef ref, TipNotifPrefs r, {List<String>? tips}) async {
  await ref.read(tipNotifStoreProvider).save(r);
  final svc = ref.read(notificationServiceProvider);
  if (r.enabled) {
    final ok = await svc.permissionGranted || await svc.requestPermission();
    if (ok) {
      final list = (tips != null && tips.isNotEmpty)
          ? tips
          : ['Open Pursely to receive your personalised tips.'];
      await svc.scheduleTipBatch(hour: r.hour, minute: r.minute, tips: list);
    }
  } else {
    await svc.cancelTip();
  }
  bumpTipNotif(ref);
}

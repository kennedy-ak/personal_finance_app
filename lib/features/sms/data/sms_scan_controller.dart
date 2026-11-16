import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications.dart';
import '../../accounts/data/account_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import 'sms_import_repository.dart';

enum SmsScanPhase { idle, running, done, failed }

/// The state of the one scan that may be in flight, kept here rather than in
/// the screen so the scan outlives the page: leave, come back, or close the
/// app's SMS screen entirely — the sweep keeps going and its result is still
/// on the page when you return.
class SmsScanState {
  final SmsScanPhase phase;
  final ScanResult? result;
  final String? error;
  final DateTime? finishedAt;

  const SmsScanState({required this.phase, this.result, this.error, this.finishedAt});

  bool get isRunning => phase == SmsScanPhase.running;
}

class SmsScanController extends Notifier<SmsScanState> {
  @override
  SmsScanState build() {
    // The scan must keep running when no screen is watching this provider.
    ref.keepAlive();
    return const SmsScanState(phase: SmsScanPhase.idle);
  }

  Future<void> start() async {
    if (state.isRunning) return;
    state = const SmsScanState(phase: SmsScanPhase.running);

    // Ask for notification consent up front so the completion notice can
    // reach the user after they've walked away from the screen.
    final notif = ref.read(notificationServiceProvider);
    var canNotify = false;
    try {
      canNotify = await notif.permissionGranted || await notif.requestPermission();
    } catch (_) {
      canNotify = false;
    }

    try {
      final result = await ref.read(smsImportRepositoryProvider).scan();

      // The scan wrote behind the providers' backs; turn their cranks.
      ref.read(smsRefreshProvider.notifier).state++;
      if (result.imported > 0 || result.fees > 0) {
        ref.read(transactionsRefreshProvider.notifier).state++;
        ref.read(accountsRefreshProvider.notifier).state++;
      }

      state = SmsScanState(
        phase: SmsScanPhase.done,
        result: result,
        finishedAt: DateTime.now(),
      );
      if (canNotify) {
        await notif.showScanResult('Scan complete', result.summaryLine);
      }
    } catch (e) {
      state = SmsScanState(
        phase: SmsScanPhase.failed,
        error: '$e',
        finishedAt: DateTime.now(),
      );
      if (canNotify) {
        await notif.showScanResult('Scan failed', 'Open Pursely to see what stopped it.');
      }
    }
  }
}

final smsScanControllerProvider =
    NotifierProvider<SmsScanController, SmsScanState>(SmsScanController.new);

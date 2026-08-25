import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/coach_action_executor.dart';
import '../domain/coach_action.dart';

/// A thing the coach is offering to do, with the button that does it.
///
/// The card is the whole point of the rewrite: the old coach could only ever
/// describe an action in a paragraph and leave the user to go and perform it.
class CoachActionCard extends ConsumerStatefulWidget {
  final CoachAction action;

  const CoachActionCard({super.key, required this.action});

  @override
  ConsumerState<CoachActionCard> createState() => _CoachActionCardState();
}

class _CoachActionCardState extends ConsumerState<CoachActionCard> {
  bool _applying = false;
  bool _applied = false;
  String? _error;

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await ref.read(coachActionExecutorProvider).apply(widget.action);

      // Everything downstream of this action needs to notice.
      bumpTransactions(ref);
      bumpAccounts(ref);
      bumpObligations(ref);

      if (!mounted) return;
      setState(() {
        _applied = true;
        _applying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _applying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final action = widget.action;
    final (icon, title, detail) = _describe(action);
    final color = _applied ? AppColors.income : AppColors.accent;

    return Card(
      color: color.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_applied ? Icons.check_circle : icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.expense),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: _applied
                  ? const Padding(
                      padding: EdgeInsets.only(right: 8, top: 4, bottom: 4),
                      child: Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.income,
                        ),
                      ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        minimumSize: const Size(110, 38),
                      ),
                      onPressed: _applying ? null : _apply,
                      child: _applying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_actionLabel(action)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, String, String) _describe(CoachAction action) => switch (action) {
        final TransferAction a => (
            Icons.swap_horiz,
            'Move ${formatMoney(a.amount)} from ${a.fromAccountName} to ${a.toAccountName}',
            a.reason,
          ),
        final CommitmentAction a => (
            a.direction == ObligationDirection.out
                ? Icons.receipt_long
                : Icons.payments,
            '${a.direction == ObligationDirection.out ? 'Record bill' : 'Record income'}: '
                '${a.name} — ${formatMoney(a.amount)}',
            '${a.cadence.label}, next ${dateLongFmt.format(a.nextDue)}'
                '${a.accountName == null ? '' : ' · ${a.accountName}'}',
          ),
      };

  String _actionLabel(CoachAction action) => switch (action) {
        TransferAction() => 'Move it',
        CommitmentAction() => 'Save it',
      };
}

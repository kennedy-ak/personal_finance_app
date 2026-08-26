import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components.dart';
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
///
/// It must never read as something that already happened. Hence the eyebrow —
/// PROPOSED · NOT YET DONE — and the pairing of Approve with an equally
/// available Dismiss.
class CoachActionCard extends ConsumerStatefulWidget {
  final CoachAction action;

  const CoachActionCard({super.key, required this.action});

  @override
  ConsumerState<CoachActionCard> createState() => _CoachActionCardState();
}

class _CoachActionCardState extends ConsumerState<CoachActionCard> {
  bool _applying = false;
  bool _applied = false;
  bool _dismissed = false;
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
    final t = CediTokens.of(context);
    final action = widget.action;
    final (title, detail) = _describe(action);

    if (_dismissed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('Suggestion dismissed.',
            style: AppType.bodySmall.copyWith(color: t.inkFaint)),
      );
    }

    final tint = _applied ? t.income : t.accent;

    return TintCard(
      tint: tint,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: tint.ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Eyebrow(_applied ? 'Done' : 'Proposed · not yet done',
                  color: tint.ink),
            ],
          ),
          const SizedBox(height: 10),
          Text(title,
              style: AppType.label
                  .copyWith(fontSize: 15, height: 1.35, color: tint.body)),
          const SizedBox(height: 6),
          Text(detail,
              style: AppType.bodySmall
                  .copyWith(height: 1.5, color: tint.muted)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              'That did not go through, and nothing was changed. Try again.',
              style: AppType.bodySmall.copyWith(color: t.expense.ink),
            ),
          ],
          if (!_applied) ...[
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: t.protected,
                    borderRadius: Radii.sm,
                    child: InkWell(
                      borderRadius: Radii.sm,
                      onTap: _applying ? null : _apply,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _applying
                            ? Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: t.accent.surface),
                                ),
                              )
                            : Text(
                                _approveLabel(action),
                                textAlign: TextAlign.center,
                                style: AppType.button.copyWith(
                                  fontSize: 14,
                                  // Violet is a mid-tone, so its label is the
                                  // dark end of the same hue rather than white.
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF140F22)
                                      : const Color(0xFFF6F3FE),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  borderRadius: Radii.sm,
                  child: InkWell(
                    borderRadius: Radii.sm,
                    onTap:
                        _applying ? null : () => setState(() => _dismissed = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: Radii.sm,
                        border: Border.all(color: t.outline),
                      ),
                      child: Text('Dismiss',
                          style: AppType.label
                              .copyWith(fontSize: 14, color: t.inkBody)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (String, String) _describe(CoachAction action) => switch (action) {
        final TransferAction a => (
            'Move ${formatMoney(a.amount)} from ${a.fromAccountName} '
                'to ${a.toAccountName}',
            a.reason,
          ),
        final CommitmentAction a => (
            '${a.direction == ObligationDirection.out ? 'Record bill' : 'Record income'}: '
                '${a.name} — ${formatMoney(a.amount)}',
            '${a.cadence.label}, next ${dateLongFmt.format(a.nextDue)}'
                '${a.accountName == null ? '' : ' · ${a.accountName}'}',
          ),
      };

  String _approveLabel(CoachAction action) => switch (action) {
        TransferAction() => 'Approve transfer',
        CommitmentAction() => 'Save it',
      };
}

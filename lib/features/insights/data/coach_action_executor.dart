import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planning/data/obligation_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../domain/coach_action.dart';

/// Carries out an action the user approved.
///
/// This is the only place a coach proposal turns into a real record, and it
/// only ever runs from a button press. Nothing here is reachable from the
/// model.
class CoachActionExecutor {
  final TransactionRepository transactions;
  final ObligationRepository obligations;

  const CoachActionExecutor({
    required this.transactions,
    required this.obligations,
  });

  Future<void> apply(CoachAction action) => switch (action) {
        final TransferAction a => transactions.createTransfer(
            fromAccountId: a.fromAccountId,
            toAccountId: a.toAccountId,
            amount: a.amount,
            description: a.reason,
            date: DateTime.now(),
          ),
        final CommitmentAction a => obligations.create(
            name: a.name,
            amount: a.amount,
            nextDue: a.nextDue,
            direction: a.direction,
            cadence: a.cadence,
            accountId: a.accountId,
          ),
      };
}

final coachActionExecutorProvider = Provider(
  (ref) => CoachActionExecutor(
    transactions: ref.watch(transactionRepositoryProvider),
    obligations: ref.watch(obligationRepositoryProvider),
  ),
);

import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/planning/domain/goal.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

/// Fixed "today" so nothing in the suite depends on when it runs.
final now = DateTime(2026, 7, 15);

Account acc(
  String id,
  String name,
  double balance, {
  AccountKind kind = AccountKind.bank,
  Liquidity liquidity = Liquidity.liquid,
  double minBalance = 0,
  bool archived = false,
}) =>
    Account(
      id: id,
      userId: 'u1',
      name: name,
      balance: balance,
      kind: kind,
      liquidity: liquidity,
      minBalance: minBalance,
      purpose: null,
      openingBalance: 0,
      isArchived: archived,
      sortOrder: 0,
      createdAt: DateTime(2025),
    );

Txn txn({
  required String account,
  required TxnType type,
  required double amount,
  required DateTime date,
  String category = 'Food & Dining',
  String? to,
}) =>
    Txn(
      id: 't${date.microsecondsSinceEpoch}$amount$account',
      userId: 'u1',
      accountId: account,
      toAccountId: to,
      type: type,
      amount: amount,
      category: category,
      description: null,
      date: date,
      createdAt: date,
    );

Obligation obl({
  required String name,
  required double amount,
  required DateTime nextDue,
  ObligationDirection direction = ObligationDirection.out,
  Cadence cadence = Cadence.monthly,
  String? accountId,
}) =>
    Obligation(
      id: 'o$name',
      userId: 'u1',
      name: name,
      direction: direction,
      amount: amount,
      cadence: cadence,
      nextDue: nextDue,
      accountId: accountId,
      category: null,
      isActive: true,
      createdAt: DateTime(2025),
    );

Goal goal({
  required String name,
  required double target,
  required double saved,
  String? accountId,
  int priority = 0,
}) =>
    Goal(
      id: 'g$name',
      userId: 'u1',
      name: name,
      targetAmount: target,
      savedAmount: saved,
      targetDate: null,
      accountId: accountId,
      priority: priority,
      isActive: true,
      createdAt: DateTime(2025),
    );

/// GHS 3,000 of spending spread over exactly 60 days, so the burn rate is a
/// clean 50/day.
List<Txn> steadySpending(String account) => [
      txn(
        account: account,
        type: TxnType.expense,
        amount: 1500,
        date: now.subtract(const Duration(days: 59)),
      ),
      txn(
        account: account,
        type: TxnType.expense,
        amount: 1500,
        date: now.subtract(const Duration(days: 1)),
      ),
    ];

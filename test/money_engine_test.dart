import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

import 'support/fixtures.dart';

void main() {
  group('transfers are not spending', () {
    test('a transfer changes no income or expense figure', () {
      final accounts = [acc('a', 'Fidelity', 3000), acc('b', 'Cash', 500)];
      final base = steadySpending('a');

      final without = buildSnapshot(accounts: accounts, txns: base, now: now);
      final with_ = buildSnapshot(
        accounts: accounts,
        txns: [
          ...base,
          txn(
            account: 'a',
            to: 'b',
            type: TxnType.transfer,
            amount: 800,
            category: 'Transfer',
            date: now.subtract(const Duration(days: 2)),
          ),
        ],
        now: now,
      );

      expect(with_.spend30d, without.spend30d);
      expect(with_.income30d, without.income30d);
      expect(with_.dailyBurn, without.dailyBurn);
    });

    test('a transfer never appears as a spending category', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000), acc('b', 'Cash', 500)],
        txns: [
          txn(account: 'a', type: TxnType.expense, amount: 200, date: now.subtract(const Duration(days: 3))),
          txn(
            account: 'a',
            to: 'b',
            type: TxnType.transfer,
            amount: 800,
            category: 'Transfer',
            date: now.subtract(const Duration(days: 2)),
          ),
        ],
        now: now,
      );

      expect(s.categories.map((c) => c.category), isNot(contains('Transfer')));
      expect(s.spend30d, 200);
    });

    test('legacy faked transfers are excluded too', () {
      // Before transfers existed, one movement was written as an Expense plus
      // an Income, both tagged 'Transfer'. Those rows are still in the history.
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000), acc('b', 'Cash', 500)],
        txns: [
          txn(account: 'a', type: TxnType.expense, amount: 200, date: now.subtract(const Duration(days: 3))),
          txn(account: 'a', type: TxnType.expense, amount: 800, category: 'Transfer', date: now.subtract(const Duration(days: 2))),
          txn(account: 'b', type: TxnType.income, amount: 800, category: 'Transfer', date: now.subtract(const Duration(days: 2))),
        ],
        now: now,
      );

      expect(s.spend30d, 200);
      expect(s.income30d, 0);
    });
  });

  group('what is actually spendable', () {
    test('locked and reserved money is not liquid', () {
      final s = buildSnapshot(
        accounts: [
          acc('a', 'Fidelity', 3000),
          acc('b', 'Fixed deposit', 5000, liquidity: Liquidity.locked),
          acc('c', 'School fees', 900, liquidity: Liquidity.reserved),
        ],
        txns: const [],
        now: now,
      );

      expect(s.totalBalance, 8900);
      expect(s.liquid, 3000);
      expect(s.locked, 5000);
      expect(s.reserved, 900);
    });

    test('safe to spend subtracts floors, goals and bills due', () {
      final s = buildSnapshot(
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('cash', 'Cash', 300, kind: AccountKind.cash, minBalance: 200),
          acc('momo', 'Mobile Money', 1200, kind: AccountKind.momo),
        ],
        txns: const [],
        obligations: [
          obl(name: 'Rent', amount: 1200, nextDue: DateTime(2026, 7, 28), accountId: 'momo'),
          obl(
            name: 'Salary',
            amount: 4000,
            nextDue: DateTime(2026, 7, 31),
            direction: ObligationDirection.incoming,
          ),
        ],
        goals: [goal(name: 'Emergency fund', target: 6000, saved: 1000)],
        now: now,
      );

      expect(s.liquid, 4500);
      expect(s.floors, 200);
      expect(s.goalReserve, 1000);
      expect(s.committed, 1200); // rent lands before the salary does
      expect(s.safeToSpend, 2100);
      expect(s.daysUntilIncome, 16);
    });

    test('a goal parked in a locked account is not subtracted twice', () {
      final s = buildSnapshot(
        accounts: [
          acc('fid', 'Fidelity', 2000),
          acc('vault', 'Fixed deposit', 5000, liquidity: Liquidity.locked),
        ],
        txns: const [],
        goals: [goal(name: 'House', target: 5000, saved: 5000, accountId: 'vault')],
        now: now,
      );

      // The 5,000 is already outside the liquid pool; reserving it again would
      // wrongly show nothing spendable.
      expect(s.goalReserve, 0);
      expect(s.safeToSpend, 2000);
    });

    test('archived accounts are ignored entirely', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000), acc('old', 'Closed', 900, archived: true)],
        txns: const [],
        now: now,
      );

      expect(s.totalBalance, 3000);
      expect(s.standings.map((x) => x.account.id), isNot(contains('old')));
    });

    test('an account below its floor offers nothing to move', () {
      final s = buildSnapshot(
        accounts: [acc('cash', 'Cash', 120, minBalance: 300)],
        txns: const [],
        now: now,
      );

      final cash = s.standings.single;
      expect(cash.available, 0);
      expect(cash.freeToMove, 0);
      expect(cash.isBelowFloor, isTrue);
    });

    test('bills pinned to an account reduce what can leave it', () {
      final s = buildSnapshot(
        accounts: [acc('momo', 'Mobile Money', 1500, kind: AccountKind.momo)],
        txns: const [],
        obligations: [
          obl(name: 'Rent', amount: 1200, nextDue: DateTime(2026, 7, 28), accountId: 'momo'),
          obl(
            name: 'Salary',
            amount: 4000,
            nextDue: DateTime(2026, 7, 31),
            direction: ObligationDirection.incoming,
          ),
        ],
        now: now,
      );

      final momo = s.standings.single;
      expect(momo.available, 1500);
      expect(momo.committed, 1200);
      expect(momo.freeToMove, 300);
    });
  });

  group('runway', () {
    test('burn rate is measured over the days actually observed', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: steadySpending('a'),
        now: now,
      );

      expect(s.dailyBurn, closeTo(50, 0.001)); // 3,000 over 60 days
      expect(s.runwayDays, closeTo(60, 0.001)); // 3,000 usable / 50
    });

    test('falling short before payday is detected', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 500)],
        txns: steadySpending('a'),
        obligations: [
          obl(
            name: 'Salary',
            amount: 4000,
            nextDue: DateTime(2026, 7, 31),
            direction: ObligationDirection.incoming,
          ),
        ],
        now: now,
      );

      expect(s.runwayDays, closeTo(10, 0.001)); // 500 / 50 a day
      expect(s.daysUntilIncome, 16);
      expect(s.willFallShort, isTrue);
      expect(s.shortfallDays, 6);
    });

    test('no spending means no runway figure rather than a wrong one', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: const [],
        now: now,
      );

      expect(s.dailyBurn, 0);
      expect(s.runwayDays, isNull);
      expect(s.willFallShort, isFalse);
    });
  });

  group('category movement', () {
    test('this month is compared against the one before it', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: [
          txn(account: 'a', type: TxnType.expense, amount: 400, date: now.subtract(const Duration(days: 5))),
          txn(account: 'a', type: TxnType.expense, amount: 200, date: now.subtract(const Duration(days: 45))),
        ],
        now: now,
      );

      final food = s.categories.firstWhere((c) => c.category == 'Food & Dining');
      expect(food.amount, 400);
      expect(food.previousAmount, 200);
      expect(food.changeRatio, closeTo(1.0, 0.001)); // doubled
    });
  });

  group('obligation recurrence', () {
    test('a monthly bill reports every landing in the window', () {
      final rent = obl(name: 'Rent', amount: 1200, nextDue: DateTime(2026, 7, 28));
      final hits = rent.occurrencesBetween(DateTime(2026, 7, 1), DateTime(2026, 10, 1));

      expect(hits, [
        DateTime(2026, 7, 28),
        DateTime(2026, 8, 28),
        DateTime(2026, 9, 28),
      ]);
    });

    test('an anchor left in the past still rolls forward correctly', () {
      final rent = obl(name: 'Rent', amount: 1200, nextDue: DateTime(2025, 1, 5));
      final next = rent.nextOccurrenceOnOrAfter(DateTime(2026, 7, 15));

      expect(next, DateTime(2026, 8, 5));
    });

    test('month-end dates clamp instead of overflowing', () {
      final bill = obl(name: 'Loan', amount: 300, nextDue: DateTime(2026, 1, 31));
      final hits = bill.occurrencesBetween(DateTime(2026, 1, 1), DateTime(2026, 4, 1));

      expect(hits, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 28),
      ]);
    });

    test('a one-off lands exactly once', () {
      final o = obl(
        name: 'School fees',
        amount: 2500,
        nextDue: DateTime(2026, 8, 10),
        cadence: Cadence.once,
      );

      expect(o.occurrencesBetween(DateTime(2026, 7, 1), DateTime(2027, 7, 1)),
          [DateTime(2026, 8, 10)]);
      expect(o.occurrencesBetween(DateTime(2026, 9, 1), DateTime(2027, 7, 1)), isEmpty);
    });
  });

  group('horizon', () {
    test('an imminent payday does not shrink the window below a week', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: const [],
        obligations: [
          obl(
            name: 'Salary',
            amount: 4000,
            nextDue: DateTime(2026, 7, 16), // tomorrow
            direction: ObligationDirection.incoming,
          ),
        ],
        now: now,
      );

      expect(s.daysUntilIncome, 1);
      expect(s.horizon, now.add(const Duration(days: kMinHorizonDays)));
    });

    test('with no known income the window falls back to 30 days', () {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: const [],
        now: now,
      );

      expect(s.daysUntilIncome, isNull);
      expect(s.horizon, now.add(const Duration(days: kDefaultHorizonDays)));
    });
  });
}

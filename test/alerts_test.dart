import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/alerts.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/planning/domain/goal.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

import 'support/fixtures.dart';

/// A salary far enough out that it never accidentally triggers the setup nudge
/// or shrink the horizon in tests that are about something else.
final salary = obl(
  name: 'Salary',
  amount: 4000,
  nextDue: DateTime(2026, 7, 31),
  direction: ObligationDirection.incoming,
);

List<MoneyAlert> alertsFor({
  required List<Account> accounts,
  List<Txn> txns = const [],
  List<Obligation> obligations = const [],
  List<Goal> goals = const [],
}) {
  final snapshot = buildSnapshot(
    accounts: accounts,
    txns: txns,
    obligations: obligations,
    goals: goals,
    now: now,
  );
  return buildAlerts(
    snapshot: snapshot,
    obligations: obligations,
    goals: goals,
    now: now,
  );
}

MoneyAlert? find(List<MoneyAlert> alerts, String id) {
  for (final a in alerts) {
    if (a.id == id) return a;
  }
  return null;
}

void main() {
  group('setup nudges', () {
    test('asks for an income date when none is known', () {
      final alerts = alertsFor(accounts: [acc('a', 'Fidelity', 3000)]);
      expect(find(alerts, 'setup.no-income'), isNotNull);
    });

    test('stays quiet once income is recorded', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 3000)],
        obligations: [salary],
      );
      expect(find(alerts, 'setup.no-income'), isNull);
    });
  });

  group('running short before payday', () {
    test('fires with the daily cut needed to close the gap', () {
      // 500 usable, 50/day burn -> 10 days of cash, income 16 days away.
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 500)],
        txns: steadySpending('a'),
        obligations: [salary],
      );

      final alert = find(alerts, 'cash.shortfall');
      expect(alert, isNotNull);
      expect(alert!.severity, AlertSeverity.critical);
      expect(alert.title, contains('6 days before payday'));
      // 500 / 16 days = 31.25 a day sustainable, down from 50.
      expect(alert.detail, contains('31.25'));
    });

    test('stays quiet when the cash comfortably outlasts the wait', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: steadySpending('a'),
        obligations: [salary],
      );
      expect(find(alerts, 'cash.shortfall'), isNull);
    });
  });

  group('overcommitted', () {
    test('fires when bills exceed spendable money', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 1000)],
        obligations: [
          salary,
          obl(name: 'Rent', amount: 1500, nextDue: DateTime(2026, 7, 25)),
        ],
      );

      final alert = find(alerts, 'cash.overcommitted');
      expect(alert, isNotNull);
      expect(alert!.severity, AlertSeverity.critical);
      expect(alert.title, contains('500')); // short by exactly 500
    });

    test('stays quiet when bills fit', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 3000)],
        obligations: [
          salary,
          obl(name: 'Rent', amount: 1500, nextDue: DateTime(2026, 7, 25)),
        ],
      );
      expect(find(alerts, 'cash.overcommitted'), isNull);
    });
  });

  group('accounts below their floor', () {
    test('names the account that should top it up', () {
      final alerts = alertsFor(
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('cash', 'Cash', 120, kind: AccountKind.cash, minBalance: 300),
        ],
        obligations: [salary],
      );

      final alert = find(alerts, 'account.below-floor.cash');
      expect(alert, isNotNull);
      expect(alert!.title, 'Move GHS 180.00 from Fidelity to Cash');
      expect(alert.actionRoute, '/add');
    });

    test('says so plainly when nothing can cover the gap', () {
      final alerts = alertsFor(
        accounts: [
          acc('cash', 'Cash', 120, kind: AccountKind.cash, minBalance: 300),
        ],
        obligations: [salary],
      );

      final alert = find(alerts, 'account.below-floor.cash');
      expect(alert, isNotNull);
      expect(alert!.title, 'Cash is below the floor you set');
      expect(alert.detail, contains('No other account'));
      expect(alert.actionRoute, isNull);
    });
  });

  group('bills the account cannot cover', () {
    test('warns before the money is due to leave', () {
      final alerts = alertsFor(
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('momo', 'Mobile Money', 450, kind: AccountKind.momo),
        ],
        obligations: [
          salary,
          obl(
            name: 'Rent',
            amount: 1200,
            nextDue: DateTime(2026, 7, 18), // 3 days out
            accountId: 'momo',
          ),
        ],
      );

      final alert = alerts.firstWhere((a) => a.id.startsWith('bill.uncovered.'));
      expect(alert.severity, AlertSeverity.critical);
      expect(alert.title, contains('Move GHS 750.00 to Mobile Money'));
      expect(alert.detail, contains('in 3 days'));
      expect(alert.detail, contains('Fidelity'));
    });

    test('ignores a bill the account can already cover', () {
      final alerts = alertsFor(
        accounts: [acc('momo', 'Mobile Money', 2000, kind: AccountKind.momo)],
        obligations: [
          salary,
          obl(
            name: 'Rent',
            amount: 1200,
            nextDue: DateTime(2026, 7, 18),
            accountId: 'momo',
          ),
        ],
      );
      expect(alerts.where((a) => a.id.startsWith('bill.uncovered.')), isEmpty);
    });

    test('ignores a bill still far away', () {
      final alerts = alertsFor(
        accounts: [acc('momo', 'Mobile Money', 100, kind: AccountKind.momo)],
        obligations: [
          salary,
          obl(
            name: 'Rent',
            amount: 1200,
            nextDue: DateTime(2026, 8, 20), // well past the warning window
            accountId: 'momo',
          ),
        ],
      );
      expect(alerts.where((a) => a.id.startsWith('bill.uncovered.')), isEmpty);
    });

    test('respects the floor when judging what is available', () {
      // 1,300 in the account, but 500 must stay -> only 800 free for a 1,200 bill.
      final alerts = alertsFor(
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('momo', 'Mobile Money', 1300, kind: AccountKind.momo, minBalance: 500),
        ],
        obligations: [
          salary,
          obl(
            name: 'Rent',
            amount: 1200,
            nextDue: DateTime(2026, 7, 18),
            accountId: 'momo',
          ),
        ],
      );

      final alert = alerts.firstWhere((a) => a.id.startsWith('bill.uncovered.'));
      expect(alert.title, contains('GHS 400.00'));
    });
  });

  group('category spikes', () {
    test('flags a category that jumped', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: [
          txn(account: 'a', type: TxnType.expense, amount: 600, date: now.subtract(const Duration(days: 5))),
          txn(account: 'a', type: TxnType.expense, amount: 300, date: now.subtract(const Duration(days: 45))),
        ],
        obligations: [salary],
      );

      final alert = find(alerts, 'category.spike.Food & Dining');
      expect(alert, isNotNull);
      expect(alert!.title, contains('100%'));
    });

    test('ignores a big percentage on a trivial amount', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: [
          txn(account: 'a', type: TxnType.expense, amount: 30, date: now.subtract(const Duration(days: 5))),
          txn(account: 'a', type: TxnType.expense, amount: 5, date: now.subtract(const Duration(days: 45))),
        ],
        obligations: [salary],
      );
      // 500% up, but only GHS 25 more — not worth a warning.
      expect(find(alerts, 'category.spike.Food & Dining'), isNull);
    });

    test('a transfer can never look like a spending spike', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 5000), acc('b', 'Cash', 500)],
        txns: [
          txn(
            account: 'a',
            to: 'b',
            type: TxnType.transfer,
            amount: 2000,
            category: 'Transfer',
            date: now.subtract(const Duration(days: 5)),
          ),
        ],
        obligations: [salary],
      );
      expect(alerts.where((a) => a.id.startsWith('category.spike.')), isEmpty);
    });
  });

  group('idle cash', () {
    test('offers spare money to the highest-priority goal', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: steadySpending('a'), // 50/day -> 700 needed for two weeks
        obligations: [salary],
        goals: [goal(name: 'Emergency fund', target: 10000, saved: 0)],
      );

      final alert = alerts.firstWhere((a) => a.id.startsWith('goal.top-up.'));
      expect(alert.severity, AlertSeverity.info);
      expect(alert.title, contains('Emergency fund'));
    });

    test('never offers money the user needs to live on', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 800)],
        txns: steadySpending('a'), // 50/day -> 700 for two weeks, only 100 spare
        obligations: [salary],
        goals: [goal(name: 'Emergency fund', target: 10000, saved: 0)],
      );
      expect(alerts.where((a) => a.id.startsWith('goal.top-up.')), isEmpty);
    });

    test('stays quiet when there is no goal to fund', () {
      final alerts = alertsFor(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: steadySpending('a'),
        obligations: [salary],
      );
      expect(alerts.where((a) => a.id.startsWith('goal.top-up.')), isEmpty);
    });
  });

  test('the worst news comes first', () {
    final alerts = alertsFor(
      accounts: [
        acc('a', 'Fidelity', 500),
        acc('cash', 'Cash', 50, kind: AccountKind.cash, minBalance: 300),
      ],
      txns: steadySpending('a'),
      obligations: [salary],
    );

    expect(alerts.first.severity, AlertSeverity.critical);
    expect(
      alerts.map((a) => a.severity.index),
      orderedEquals(List.of(alerts.map((a) => a.severity.index))..sort()),
    );
  });
}

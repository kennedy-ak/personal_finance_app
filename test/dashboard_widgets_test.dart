import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/alerts.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/dashboard/presentation/widgets/alert_list.dart';
import 'package:personal_finance_app/features/dashboard/presentation/widgets/money_placement_bar.dart';
import 'package:personal_finance_app/features/dashboard/presentation/widgets/safe_to_spend_hero.dart';
import 'package:personal_finance_app/features/dashboard/presentation/widgets/spending_movement.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

import 'support/fixtures.dart';

final salary = obl(
  name: 'Salary',
  amount: 4000,
  nextDue: DateTime(2026, 7, 31),
  direction: ObligationDirection.incoming,
);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  group('SafeToSpendHero', () {
    testWidgets('leads with what is spendable, not the total balance',
        (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: const [],
        obligations: [
          salary,
          obl(name: 'Rent', amount: 1200, nextDue: DateTime(2026, 7, 25)),
        ],
        now: now,
      );

      await pump(tester, SafeToSpendHero(snapshot: s));

      expect(find.text('GHS 1,800.00'), findsOneWidget); // 3000 - 1200
      expect(find.textContaining('Safe to spend'), findsOneWidget);
      expect(find.textContaining('Income lands in 16 days'), findsOneWidget);
    });

    testWidgets('says plainly when the money runs out first', (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 500)],
        txns: steadySpending('a'),
        obligations: [salary],
        now: now,
      );

      await pump(tester, SafeToSpendHero(snapshot: s));

      expect(find.textContaining('runs out 6 days before'), findsOneWidget);
    });

    testWidgets('calls out bills that exceed spendable money', (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 1000)],
        txns: const [],
        obligations: [
          salary,
          obl(name: 'Rent', amount: 1500, nextDue: DateTime(2026, 7, 25)),
        ],
        now: now,
      );

      await pump(tester, SafeToSpendHero(snapshot: s));

      expect(find.textContaining('GHS 500.00 more than you have spare'),
          findsOneWidget);
    });

    testWidgets('invites logging when there is no history yet', (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 3000)],
        txns: const [],
        now: now,
      );

      await pump(tester, SafeToSpendHero(snapshot: s));

      expect(find.textContaining('Log a few expenses'), findsOneWidget);
    });
  });

  group('MoneyPlacementBar', () {
    testWidgets('separates spendable money from money that is tied up',
        (tester) async {
      final s = buildSnapshot(
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('vault', 'Fixed deposit', 5000, liquidity: Liquidity.locked),
          acc('sch', 'School fees', 900, liquidity: Liquidity.reserved),
        ],
        txns: const [],
        obligations: [
          salary,
          obl(name: 'Rent', amount: 1200, nextDue: DateTime(2026, 7, 25)),
        ],
        now: now,
      );

      await pump(tester, MoneyPlacementBar(snapshot: s));

      expect(find.text('Where your money is'), findsOneWidget);
      expect(find.text('Spendable'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Reserved'), findsOneWidget);
      expect(find.text('GHS 5,000.00'), findsOneWidget); // the locked slice
    });

    testWidgets('segments still add up when bills exceed the cash',
        (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 1000)],
        txns: const [],
        obligations: [
          salary,
          obl(name: 'Rent', amount: 1500, nextDue: DateTime(2026, 7, 25)),
        ],
        now: now,
      );

      await pump(tester, MoneyPlacementBar(snapshot: s));

      // Nothing is shown as spendable, and the gap is stated outright.
      expect(find.text('Spendable'), findsNothing);
      expect(find.textContaining('exceed your spendable money by GHS 500.00'),
          findsOneWidget);
    });

    testWidgets('guides the user when there are no balances', (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 0)],
        txns: const [],
        now: now,
      );

      await pump(tester, MoneyPlacementBar(snapshot: s));

      expect(find.textContaining('No balances yet'), findsOneWidget);
    });
  });

  group('AlertList', () {
    testWidgets('shows the loudest alerts and hides the rest', (tester) async {
      const alerts = [
        MoneyAlert(
          id: 'a',
          severity: AlertSeverity.critical,
          title: 'First',
          detail: 'detail one',
        ),
        MoneyAlert(
          id: 'b',
          severity: AlertSeverity.warning,
          title: 'Second',
          detail: 'detail two',
        ),
        MoneyAlert(
          id: 'c',
          severity: AlertSeverity.info,
          title: 'Third',
          detail: 'detail three',
        ),
      ];

      await pump(tester, const AlertList(alerts: alerts));

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Third'), findsNothing);

      await tester.tap(find.text('1 more'));
      await tester.pumpAndSettle();

      expect(find.text('Third'), findsOneWidget);
    });

    testWidgets('renders nothing when there is nothing to say', (tester) async {
      await pump(tester, const AlertList(alerts: []));
      expect(find.byType(Card), findsNothing);
    });
  });

  group('SpendingMovement', () {
    testWidgets('shows how each category moved against last month',
        (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: [
          txn(account: 'a', type: TxnType.expense, amount: 600, date: now.subtract(const Duration(days: 5))),
          txn(account: 'a', type: TxnType.expense, amount: 300, date: now.subtract(const Duration(days: 45))),
        ],
        now: now,
      );

      await pump(tester, SpendingMovement(snapshot: s));

      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget); // doubled since last month
    });

    testWidgets('says so when nothing has been spent', (tester) async {
      final s = buildSnapshot(
        accounts: [acc('a', 'Fidelity', 5000)],
        txns: const [],
        now: now,
      );

      await pump(tester, SpendingMovement(snapshot: s));

      expect(find.textContaining('No spending logged'), findsOneWidget);
    });
  });
}

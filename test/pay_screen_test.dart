import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/core/finance/snapshot_provider.dart';
import 'package:personal_finance_app/features/accounts/data/account_repository.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/payments/presentation/pay_screen.dart';
import 'package:personal_finance_app/features/planning/data/obligation_repository.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';

import 'support/fixtures.dart';

final salary = obl(
  name: 'Salary',
  amount: 4000,
  nextDue: DateTime(2026, 7, 31),
  direction: ObligationDirection.incoming,
);

Future<void> pumpPayScreen(
  WidgetTester tester, {
  required List<Account> accounts,
  List<Obligation> obligations = const [],
}) async {
  // Tall enough that the whole screen builds — a ListView does not construct
  // children below the viewport, and the action button sits at the bottom.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final snapshot = buildSnapshot(
    accounts: accounts,
    txns: steadySpending(accounts.first.id),
    obligations: obligations,
    now: now,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moneySnapshotProvider.overrideWith((ref) async => snapshot),
        obligationsProvider.overrideWith((ref) async => obligations),
        accountsProvider.overrideWith((ref) async => accounts),
      ],
      child: const MaterialApp(home: PayScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.byType(TextField).first, amount);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks for an amount before saying anything', (tester) async {
    await pumpPayScreen(
      tester,
      accounts: [acc('fid', 'Fidelity', 3000)],
      obligations: [salary],
    );

    expect(find.textContaining('Enter an amount'), findsOneWidget);
    expect(find.text('Record this payment'), findsNothing);
  });

  testWidgets('names the account and why not the others', (tester) async {
    await pumpPayScreen(
      tester,
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('cash', 'Cash', 400, kind: AccountKind.cash, minBalance: 300),
        acc('momo', 'Mobile Money', 1400, kind: AccountKind.momo),
      ],
      obligations: [
        salary,
        obl(
          name: 'Rent',
          amount: 1200,
          nextDue: DateTime(2026, 7, 28),
          accountId: 'momo',
        ),
      ],
    );

    await enterAmount(tester, '800');

    expect(find.text('Take GHS 800.00 from Fidelity'), findsOneWidget);
    expect(find.textContaining('Not Mobile Money'), findsOneWidget);
    expect(find.textContaining('Rent'), findsOneWidget);
    expect(find.text('Record this payment'), findsOneWidget);
  });

  testWidgets('shows what the payment leaves behind', (tester) async {
    await pumpPayScreen(
      tester,
      accounts: [acc('fid', 'Fidelity', 1000)],
      obligations: [salary],
    );

    await enterAmount(tester, '700');

    // 300 left, 50/day burn -> 6 days, income 16 days away.
    expect(find.textContaining('Leaves GHS 300.00 spendable'), findsOneWidget);
    expect(find.textContaining('run short before payday'), findsOneWidget);
  });

  testWidgets('offers the transfer when the money must leave one account',
      (tester) async {
    await pumpPayScreen(
      tester,
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('momo', 'Mobile Money', 400, kind: AccountKind.momo),
      ],
      obligations: [salary],
    );

    await enterAmount(tester, '1000');
    await tester.tap(find.text('Anywhere — you decide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile Money').last);
    await tester.pumpAndSettle();

    expect(find.text('Move GHS 600.00 from Fidelity into Mobile Money first'),
        findsOneWidget);
    expect(find.textContaining('Fidelity → Mobile Money'), findsOneWidget);
    expect(find.text('Move the money and record it'), findsOneWidget);
  });

  testWidgets('refuses plainly when the money is not there', (tester) async {
    await pumpPayScreen(
      tester,
      accounts: [acc('fid', 'Fidelity', 200)],
      obligations: [salary],
    );

    await enterAmount(tester, '5000');

    expect(find.text('You do not have GHS 5,000.00 to send'), findsOneWidget);
    expect(find.text('Record this payment'), findsNothing);
  });
}

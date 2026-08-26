import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/theme.dart';
import 'package:personal_finance_app/features/accounts/data/account_repository.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/insights/data/daily_tip_service.dart';
import 'package:personal_finance_app/features/insights/presentation/insights_screen.dart';
import 'package:personal_finance_app/features/planning/data/goal_repository.dart';
import 'package:personal_finance_app/features/planning/data/obligation_repository.dart';
import 'package:personal_finance_app/features/planning/domain/goal.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';
import 'package:personal_finance_app/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

import 'support/fixtures.dart';

/// The Overview tab renders "Your numbers" as a two-column grid. It used to be
/// a bare `Row(crossAxisAlignment: stretch)` sitting directly in a ListView,
/// which handed the tiles a tight *infinite* height: the page then scrolled
/// far past its content into nothing. These pin the scroll extent to the
/// content.
Future<double> _scrollExtent(
  WidgetTester tester, {
  required List<Account> accounts,
  required List<Txn> txns,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      accountsProvider.overrideWith((_) async => accounts),
      transactionsProvider.overrideWith((_) async => txns),
      obligationsProvider.overrideWith((_) async => const <Obligation>[]),
      goalsProvider.overrideWith((_) async => const <Goal>[]),
      dailyTipProvider.overrideWith((_) async => null),
    ],
    child: MaterialApp(theme: appLightTheme, home: const InsightsScreen()),
  ));
  await tester.pumpAndSettle();

  return tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .maxScrollExtent;
}

void main() {
  testWidgets('with no data the Overview does not scroll at all',
      (tester) async {
    final extent = await _scrollExtent(
      tester,
      accounts: const [],
      txns: const [],
    );

    expect(extent, 0);
  });

  testWidgets('spending draws the numbers grid without an infinite extent',
      (tester) async {
    final txns = [
      for (var i = 0; i < 6; i++)
        txn(
          account: 'a',
          type: TxnType.expense,
          amount: 25,
          date: DateTime.now().subtract(Duration(days: i)),
        ),
    ];

    final extent = await _scrollExtent(
      tester,
      accounts: [acc('a', 'Fidelity', 900), acc('b', 'MoMo', 300)],
      txns: txns,
    );

    // The grid is a handful of cards, so the page overflows by a screen at
    // most. The bug produced an extent of several thousand.
    expect(extent, greaterThan(0));
    expect(extent, lessThan(1000));
  });
}

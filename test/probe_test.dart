import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/planning/domain/goal.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

import 'support/fixtures.dart';

void main() {
  test('PROBE A: expense on a reserved account never moves safeToSpend', () {
    final accounts = [
      acc('main', 'Main', 2000, liquidity: Liquidity.reserved),
      acc('cash', 'Cash', 100),
    ];
    final before = buildSnapshot(accounts: accounts, txns: [], now: now);

    // Same thing after spending 500 from Main (balance settled by DB).
    final after = buildSnapshot(
      accounts: [
        acc('main', 'Main', 1500, liquidity: Liquidity.reserved),
        acc('cash', 'Cash', 100),
      ],
      txns: [
        txn(account: 'main', type: TxnType.expense, amount: 500,
            date: now.subtract(const Duration(days: 1))),
      ],
      now: now,
    );

    print('safeToSpend before=${before.safeToSpend} after=${after.safeToSpend}');
    print('total before=${before.totalBalance} after=${after.totalBalance}');
    print('liquid before=${before.liquid} after=${after.liquid}');
  });

  test('PROBE B: placement bar bands sum to more than total when overdrawn', () {
    final accounts = [acc('main', 'Main', 1000, minBalance: 800)];
    final goals = [
      Goal(id: 'g1', userId: 'u1', name: 'Rent', targetAmount: 1000,
        savedAmount: 500, targetDate: null, accountId: 'main',
        priority: 0, isActive: true, createdAt: DateTime(2025)),
    ];
    final s = buildSnapshot(accounts: accounts, txns: [], goals: goals, now: now);

    final protected = s.floors + s.goalReserve + s.reserved + s.locked;
    final usable = s.usableCash > 0 ? s.usableCash : 0.0;
    final committed = s.committed < usable ? s.committed : usable;
    final liquid = usable - committed;
    final barTotal = protected + committed + liquid;

    print('totalBalance=${s.totalBalance} usableCash=${s.usableCash}');
    print('floors=${s.floors} goalReserve=${s.goalReserve}');
    print('BAR TOTAL SHOWN = $barTotal  (real total = ${s.totalBalance})');
    print('INFLATION = ${barTotal - s.totalBalance}');
  });
}

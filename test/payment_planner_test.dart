import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/core/finance/payment_planner.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';

import 'support/fixtures.dart';

final salary = obl(
  name: 'Salary',
  amount: 4000,
  nextDue: DateTime(2026, 7, 31),
  direction: ObligationDirection.incoming,
);

PaymentPlan planFor(
  double amount, {
  required List<Account> accounts,
  List<Obligation> obligations = const [],
  String? payFrom,
}) {
  final snapshot = buildSnapshot(
    accounts: accounts,
    txns: steadySpending(accounts.first.id),
    obligations: obligations,
    now: now,
  );
  return planPayment(
    amount: amount,
    snapshot: snapshot,
    obligations: obligations,
    payFromAccountId: payFrom,
  );
}

void main() {
  group('picking a single source', () {
    test('names the account and leaves the protected ones alone', () {
      final plan = planFor(
        800,
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

      expect(plan.isPossible, isTrue);
      expect(plan.isClean, isTrue);
      expect(plan.headline, 'Take GHS 800.00 from Fidelity');
      expect(plan.sources.single.account.name, 'Fidelity');
    });

    test('explains why each other account was passed over', () {
      final plan = planFor(
        800,
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('cash', 'Cash', 400, kind: AccountKind.cash, minBalance: 300),
          acc('momo', 'Mobile Money', 1400, kind: AccountKind.momo),
          acc('vault', 'Fixed deposit', 9000, liquidity: Liquidity.locked),
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

      final reasons = plan.reasoning.join(' | ');
      expect(reasons, contains('Not Mobile Money'));
      expect(reasons, contains('Rent'));
      expect(reasons, contains('GHS 1,200.00'));
      expect(reasons, contains('Not Cash'));
      expect(reasons, contains('Not Fixed deposit'));
    });

    test('respects a floor rather than draining an account', () {
      // Cash has 400 but must keep 300, so it cannot cleanly give 200 + ... it
      // can give exactly 100. Fidelity should win.
      final plan = planFor(
        200,
        accounts: [
          acc('cash', 'Cash', 400, kind: AccountKind.cash, minBalance: 300),
          acc('fid', 'Fidelity', 900),
        ],
        obligations: [salary],
      );

      expect(plan.sources.single.account.name, 'Fidelity');
    });

    test('never volunteers locked money when anything else will do', () {
      final plan = planFor(
        500,
        accounts: [
          acc('vault', 'Fixed deposit', 50000, liquidity: Liquidity.locked),
          acc('fid', 'Fidelity', 800),
        ],
        obligations: [salary],
      );

      expect(plan.sources.single.account.name, 'Fidelity');
    });

    test('prefers a spendable account over a reserved one', () {
      final plan = planFor(
        500,
        accounts: [
          acc('sch', 'School fees', 5000, liquidity: Liquidity.reserved),
          acc('fid', 'Fidelity', 900),
        ],
        obligations: [salary],
      );

      expect(plan.sources.single.account.name, 'Fidelity');
    });
  });

  group('when it costs something', () {
    test('falls back to bill money and says which bill', () {
      final plan = planFor(
        1000,
        accounts: [
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

      expect(plan.isPossible, isTrue);
      expect(plan.isClean, isFalse);
      expect(plan.sources.single.quality, SourceQuality.dipsIntoBills);
      expect(plan.sources.single.caution, contains('Rent'));
    });

    test('falls back to breaking a floor only as a last resort', () {
      final plan = planFor(
        350,
        accounts: [
          acc('cash', 'Cash', 400, kind: AccountKind.cash, minBalance: 300),
        ],
        obligations: [salary],
      );

      expect(plan.isPossible, isTrue);
      expect(plan.sources.single.quality, SourceQuality.breaksFloor);
      expect(plan.sources.single.caution, contains('GHS 300.00'));
    });

    test('warns when the payment causes a shortfall before payday', () {
      // 50/day burn, income 16 days out. Paying 700 of 1,000 leaves 6 days.
      final plan = planFor(
        700,
        accounts: [acc('fid', 'Fidelity', 1000)],
        obligations: [salary],
      );

      expect(plan.impact.runwayDaysAfter, closeTo(6, 0.001));
      expect(plan.impact.daysUntilIncome, 16);
      expect(plan.impact.causesShortfall, isTrue);
      expect(plan.impact.safeToSpendAfter, 300);
    });

    test('stays quiet about shortfall when the payment is comfortable', () {
      final plan = planFor(
        200,
        accounts: [acc('fid', 'Fidelity', 5000)],
        obligations: [salary],
      );

      expect(plan.impact.causesShortfall, isFalse);
    });
  });

  group('splitting', () {
    test('combines accounts when no single one can cover it', () {
      final plan = planFor(
        1200,
        accounts: [
          acc('fid', 'Fidelity', 700),
          acc('momo', 'Mobile Money', 600, kind: AccountKind.momo),
        ],
        obligations: [salary],
      );

      expect(plan.isPossible, isTrue);
      expect(plan.isSplit, isTrue);
      expect(plan.headline, contains('Split GHS 1,200.00 across'));
      expect(
        plan.sources.fold<double>(0, (s, x) => s + x.amount),
        closeTo(1200, 0.001),
      );
      // Biggest contributor first, and it gives everything it cleanly can.
      expect(plan.sources.first.account.name, 'Fidelity');
      expect(plan.sources.first.amount, 700);
    });

    test('prefers one account over a split when one can manage', () {
      final plan = planFor(
        600,
        accounts: [
          acc('fid', 'Fidelity', 700),
          acc('momo', 'Mobile Money', 600, kind: AccountKind.momo),
        ],
        obligations: [salary],
      );

      expect(plan.isSplit, isFalse);
    });
  });

  group('when the money has to leave a particular account', () {
    test('works out the top-up needed and where it comes from', () {
      final plan = planFor(
        1000,
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('momo', 'Mobile Money', 400, kind: AccountKind.momo),
        ],
        obligations: [salary],
        payFrom: 'momo',
      );

      expect(plan.isPossible, isTrue);
      expect(plan.transfers, hasLength(1));
      expect(plan.transfers.single.from.name, 'Fidelity');
      expect(plan.transfers.single.to.name, 'Mobile Money');
      expect(plan.transfers.single.amount, 600);
      expect(plan.headline, 'Move GHS 600.00 from Fidelity into Mobile Money first');
    });

    test('does not move money when the account already has enough', () {
      final plan = planFor(
        300,
        accounts: [
          acc('fid', 'Fidelity', 3000),
          acc('momo', 'Mobile Money', 900, kind: AccountKind.momo),
        ],
        obligations: [salary],
        payFrom: 'momo',
      );

      expect(plan.transfers, isEmpty);
      expect(plan.headline, 'Mobile Money can cover GHS 300.00');
    });

    test('draws from several accounts when one top-up is not enough', () {
      final plan = planFor(
        2000,
        accounts: [
          acc('momo', 'Mobile Money', 200, kind: AccountKind.momo),
          acc('fid', 'Fidelity', 1000),
          acc('acc2', 'Access', 900),
        ],
        obligations: [salary],
        payFrom: 'momo',
      );

      expect(plan.isPossible, isTrue);
      expect(plan.transfers, hasLength(2));
      expect(
        plan.transfers.fold<double>(0, (s, t) => s + t.amount),
        closeTo(1800, 0.001),
      );
    });

    test('says how short it still is when even that fails', () {
      final plan = planFor(
        5000,
        accounts: [
          acc('momo', 'Mobile Money', 200, kind: AccountKind.momo),
          acc('fid', 'Fidelity', 1000),
        ],
        obligations: [salary],
      );

      expect(plan.isPossible, isFalse);
      expect(plan.headline, contains('do not have GHS 5,000.00'));
      expect(plan.reasoning.join(' '), contains('GHS 1,200.00'));
    });
  });

  group('edge cases', () {
    test('an empty amount asks for one instead of guessing', () {
      final plan = planFor(
        0,
        accounts: [acc('fid', 'Fidelity', 3000)],
        obligations: [salary],
      );

      expect(plan.isPossible, isFalse);
      expect(plan.headline, contains('Enter an amount'));
    });

    test('locked money is excluded from what you are told you have', () {
      final plan = planFor(
        5000,
        accounts: [
          acc('fid', 'Fidelity', 1000),
          acc('vault', 'Fixed deposit', 20000, liquidity: Liquidity.locked),
        ],
        obligations: [salary],
      );

      expect(plan.isPossible, isFalse);
      expect(plan.reasoning.join(' '), contains('GHS 20,000.00 is locked away'));
    });

    test('archived accounts are never offered', () {
      final plan = planFor(
        500,
        accounts: [
          acc('old', 'Closed account', 9000, archived: true),
          acc('fid', 'Fidelity', 800),
        ],
        obligations: [salary],
      );

      expect(plan.sources.single.account.name, 'Fidelity');
    });
  });
}

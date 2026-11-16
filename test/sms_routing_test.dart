import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/features/sms/domain/parsed_sms.dart';
import 'package:personal_finance_app/features/sms/domain/sms_routing.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

void main() {
  final at = DateTime(2026, 9, 28, 14, 32);

  ParsedSms money({
    SmsDirection direction = SmsDirection.debit,
    double amount = 20,
    double? fee,
    String? counterparty = 'SILVERBIRD CINEMA',
    String dedupeKey = 'mtn_momo|debit|20.00|P1',
  }) =>
      ParsedSms(
        parserId: 'mtn_momo',
        verdict: SmsVerdict.money,
        direction: direction,
        amount: amount,
        fee: fee,
        counterparty: counterparty,
        reference: 'P1',
        occurredAt: at,
        dedupeKey: dedupeKey,
        summary: 's',
      );

  test('a message with no matching rule waits for review, fee already booked',
      () {
    final d = decideForMessage(
      parsed: money(fee: 0.46),
      senderAccountId: 'momo',
      rules: const [],
    );

    expect(d, isA<ReviewDecision>());
    final review = d as ReviewDecision;
    expect(review.fee, isNotNull);
    expect(review.fee!.category, 'Bank Charges');
    expect(review.fee!.externalRef, 'mtn_momo|debit|20.00|P1|fee');
    expect(review.fee!.accountId, 'momo');
  });

  test('a learned expense rule imports without asking', () {
    final rule = SmsRoutingRule(
      id: 'r1',
      matchText: 'Silverbird',
      matchKind: 'contains',
      txnType: TxnType.expense,
      category: 'Entertainment',
    );
    final d = decideForMessage(
      parsed: money(fee: 0.46),
      senderAccountId: 'momo',
      rules: [rule],
    );

    expect(d, isA<ImportDecision>());
    final txn = (d as ImportDecision).txn;
    expect(txn.type, TxnType.expense);
    expect(txn.category, 'Entertainment');
    expect(txn.accountId, 'momo');
    expect(txn.toAccountId, isNull);
    expect(txn.externalRef, 'mtn_momo|debit|20.00|P1');
  });

  test('a transfer rule sends debits to the counterpart account and credits back',
      () {
    final rule = SmsRoutingRule(
      id: 'r2',
      matchText: 'IC WEALTH',
      matchKind: 'contains',
      txnType: TxnType.transfer,
      counterpartAccountId: 'icw',
    );

    // Money leaves MoMo and lands at IC Wealth.
    final out = decideForMessage(
      parsed: money(
        counterparty: 'IC WEALTH BROKERS',
        dedupeKey: 'mtn_momo|debit|500.00|P9',
        amount: 500,
      ),
      senderAccountId: 'momo',
      rules: [rule],
    ) as ImportDecision;
    expect(out.txn.type, TxnType.transfer);
    expect(out.txn.accountId, 'momo');
    expect(out.txn.toAccountId, 'icw');
    expect(out.txn.category, 'Transfer');

    // Redeeming comes back the other way: IC Wealth is the source.
    final back = decideForMessage(
      parsed: money(
        direction: SmsDirection.credit,
        counterparty: 'IC WEALTH BROKERS',
        dedupeKey: 'mtn_momo|credit|500.00|P8',
        amount: 500,
      ),
      senderAccountId: 'momo',
      rules: [rule],
    ) as ImportDecision;
    expect(back.txn.accountId, 'icw');
    expect(back.txn.toAccountId, 'momo');
  });

  test('the more specific rule wins at equal priority', () {
    const broad = SmsRoutingRule(
      id: 'a',
      matchText: 'STANBIC',
      matchKind: 'contains',
      txnType: TxnType.expense,
      category: 'Bank Charges',
    );
    const loan = SmsRoutingRule(
      id: 'b',
      matchText: 'STANBIC LOAN REPAYMENT',
      matchKind: 'contains',
      txnType: TxnType.expense,
      category: 'Bills & Utilities',
    );

    final picked = pickRoutingRule(
      parserId: 'mtn_momo',
      counterparty: 'STANBIC LOAN REPAYMENT FEE',
      rules: [broad, loan],
    );
    expect(picked?.id, 'b');
  });

  test('a rule scoped to another sender does not fire', () {
    const rule = SmsRoutingRule(
      id: 'r3',
      parserId: 'fidelity',
      matchText: 'JUMIA',
      matchKind: 'contains',
      txnType: TxnType.expense,
      category: 'Shopping',
    );
    final picked = pickRoutingRule(
      parserId: 'mtn_momo',
      counterparty: 'JUMIA GH',
      rules: [rule],
    );
    expect(picked, isNull);
  });

  test('promo messages are skipped, unreadable ones queued', () {
    final notMoney = ParsedSms(
      parserId: 'mtn_momo',
      verdict: SmsVerdict.notMoney,
      occurredAt: at,
    );
    expect(
      decideForMessage(parsed: notMoney, senderAccountId: 'momo', rules: const []),
      isA<IgnoreDecision>(),
    );

    final unreadable = ParsedSms(
      parserId: 'mtn_momo',
      verdict: SmsVerdict.unparsed,
      occurredAt: at,
    );
    expect(
      decideForMessage(parsed: unreadable, senderAccountId: 'momo', rules: const []),
      isA<UnparsedDecision>(),
    );
  });

  test('the fee row and its parent never share an external ref', () {
    const rule = SmsRoutingRule(
      id: 'r4',
      matchText: 'SILVERBIRD',
      matchKind: 'contains',
      txnType: TxnType.expense,
      category: 'Entertainment',
    );
    final d = decideForMessage(
      parsed: money(fee: 0.46),
      senderAccountId: 'momo',
      rules: [rule],
    ) as ImportDecision;
    expect(d.fee!.externalRef, isNot(d.txn.externalRef));
  });
}

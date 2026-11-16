import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/features/sms/domain/bank_sms_parser.dart';
import 'package:personal_finance_app/features/sms/domain/parsed_sms.dart';

/// MTN Ghana MoMo alerts, worded the way real ones arrive. The parser is the
/// one part of the import pipeline that cannot check its work against a
/// database constraint — these tests are what says it read the message right.
void main() {
  final receivedAt = DateTime(2026, 9, 28, 14, 32);
  final parser = MtnMomoParser();

  ParsedSms parse(String body) =>
      parser.parse(RawSms(
        address: 'MobileMoney',
        body: body,
        receivedAt: receivedAt,
        providerId: 'p1',
      ));

  group('MTN MoMo money alerts', () {
    test('receiving money reads amount, sender, fee, balance and ref', () {
      final p = parse(
        'You have received GHS50.00 from 0244123456/KWAME MENSAH. '
        'Fee: GHS0.00. Balance: GHS1,234.56. Ref: P250928.1234.A5678. '
        'Thank you for using Mobile Money.',
      );

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.credit);
      expect(p.amount, 50.00);
      expect(p.fee, isNull); // zero fees are stored as absent, not as 0
      expect(p.balance, 1234.56);
      expect(p.counterparty, 'KWAME MENSAH');
      expect(p.reference, 'P250928.1234.A5678');
      expect(p.dedupeKey, 'mtn_momo|credit|50.00|P250928.1234.A5678');
    });

    test('a merchant payment is a debit with its fee kept separate', () {
      final p = parse(
        'Payment made for GHS20.00 to SILVERBIRD CINEMA ACCRA GH '
        'Fee: GHS0.46 Balance: GHS459.54. Ref: P230115.9012. '
        'Thank you for using MTN Mobile Money.',
      );

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.debit);
      expect(p.amount, 20.00);
      expect(p.fee, 0.46);
      expect(p.balance, 459.54);
      expect(p.counterparty, 'SILVERBIRD CINEMA ACCRA GH');
      expect(p.dedupeKey, 'mtn_momo|debit|20.00|P230115.9012');
    });

    test('sending money with a comma amount and no fee', () {
      final p = parse(
        'You have sent GHS1,050.00 to MARY ANN on 28-09-26 at 2:30 pm. '
        'Fee: GHS0.00. Balance: GHS94.00. Ref: P250928.9987.',
      );

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.debit);
      expect(p.amount, 1050.00);
      expect(p.fee, isNull);
      expect(p.counterparty, 'MARY ANN');
    });

    test('agent cash-out finds the counterparty after "at"', () {
      final p = parse(
        'Cash Out of GHS200.00 at MADINA MARKET AGENT 0244555666 '
        'Fee:GHS2.00. Balance: GHS60.00. Ref: P250928.4444.',
      );

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.debit);
      expect(p.amount, 200.00);
      expect(p.fee, 2.00);
      expect(p.counterparty, 'MADINA MARKET AGENT');
    });

    test('airtime bought off the wallet is a debit', () {
      final p = parse(
        'You have bought GHS5.00 airtime. Fee: GHS0.00. '
        'Balance: GHS55.00. Ref: P250928.777.',
      );

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.debit);
      expect(p.amount, 5.00);
    });

    test('a customer paying a merchant wallet is a credit', () {
      final p = parse(
        'Customer JOSEPH ASAMOAH has paid GHS35.00 to your account. '
        'Fee: GHS0.00. Balance: GHS135.00. Ref: P250928.2222.',
      );

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.credit);
      expect(p.amount, 35.00);
      expect(p.counterparty, 'JOSEPH ASAMOAH');
    });
  });

  group('MTN MoMo non-money and unreadable messages', () {
    test('a promo with no figure is not money', () {
      final p = parse(
        'Yello! Get a 100 percent bonus on your next data bundle purchase. '
        'Dial *138# to buy.',
      );
      expect(p.verdict, SmsVerdict.notMoney);
      expect(p.dedupeKey, isNull);
    });

    test('an OTP is not money', () {
      final p = parse('Your OTP is 456789. Do not share it with anyone.');
      expect(p.verdict, SmsVerdict.notMoney);
    });

    test('an amount with no direction is unparsed, never guessed', () {
      final p = parse(
        'Transaction successful. GHS10.00. Ref: P250928.0001.',
      );
      expect(p.verdict, SmsVerdict.unparsed);
      expect(p.amount, 10.00);
      expect(p.dedupeKey, isNull, reason: 'unparsed rows must not carry a '
          'dedupe key that could block a later readable message');
    });
  });

  group('bank parsers stay conservative', () {
    test('a clear Fidelity debit alert imports', () {
      final parser = parserById('fidelity')!;
      final p = parser.parse(RawSms(
        address: 'Fidelity',
        body:
            'Debit Alert: GHS 120.00 Acc: **1234 Details: POS JUMIA GH '
            'Bal: GHS 1,000.50 Ref: 987654321',
        receivedAt: receivedAt,
        providerId: 'p2',
      ));

      expect(p.verdict, SmsVerdict.money);
      expect(p.direction, SmsDirection.debit);
      expect(p.amount, 120.00);
      expect(p.balance, 1000.50);
    });

    test('directionless bank noise goes to the queue, not the books', () {
      final parser = parserById('access')!;
      final p = parser.parse(RawSms(
        address: 'AccessBank',
        body: 'Your balance as at 28 Sep 2026 is GHS 240.10.',
        receivedAt: receivedAt,
        providerId: 'p3',
      ));

      // 'balance is' names no movement; without a debit or credit word there
      // is nothing to import.
      expect(p.verdict, anyOf(SmsVerdict.unparsed, SmsVerdict.notMoney));
    });
  });

  group('sender address matching', () {
    test('shortcodes and spacing variations still match their parser', () {
      final momo = parserById('mtn_momo')!;
      expect(addressMatchesParser('MobileMoney', momo), isTrue);
      expect(addressMatchesParser('Mobile Money', momo), isTrue);
      expect(addressMatchesParser('MTN', momo), isFalse,
          reason: "'MTN' is the promo/OTP sender, not the wallet");
      expect(addressMatchesParser('Fidelity', momo), isFalse);
    });
  });
}

import 'parsed_sms.dart';

/// One message as it sits on the phone, before any parsing.
class RawSms {
  /// The sender address exactly as the content provider reports it — e.g.
  /// 'MobileMoney', 'MTN', 'Fidelity' or a shortcode like '140'.
  final String address;
  final String body;
  final DateTime receivedAt;

  /// The content provider's row id. Stable for the life of the message and
  /// used only to keep re-scans of an unparsed message idempotent.
  final String providerId;

  const RawSms({
    required this.address,
    required this.body,
    required this.receivedAt,
    required this.providerId,
  });
}

/// Turns messages from one sender into [ParsedSms].
///
/// A parser never throws on a message it doesn't understand — it returns an
/// `unparsed` verdict and the review queue takes over. A crash here would stop
/// the whole scan, which is the one thing worse than not reading the message.
abstract class BankSmsParser {
  /// Matches `sms_account_links.parser_id`.
  String get id;

  String get displayName;

  /// Sender addresses this parser claims. Matched case-insensitively against
  /// the SMS address, both exactly and with non-alphanumerics stripped.
  List<String> get senderAddresses;

  /// Text shown in Settings naming what to paste into 'identifiers', e.g.
  /// 'Your MoMo number as alerts write it (024…)'.
  String get identifiersHint;

  ParsedSms parse(RawSms sms);
}

// ---------------------------------------------------------------------------
// Shared extraction helpers
// ---------------------------------------------------------------------------

final RegExp _amountAfterCode = RegExp(
  r'(?:GHS|GH¢|GH₵|GHc|Ghs)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
);

final RegExp _feeAmount = RegExp(
  r'(?:fee|charge|commission|cost)[^0-9GHS]{0,14}'
  r'(?:GHS|GH¢|GH₵|GHc|Ghs)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);

final RegExp _balanceAmount = RegExp(
  r'(?:balance|bal|avail\.? ?bal)[^0-9GHS]{0,12}'
  r'(?:GHS|GH¢|GH₵|GHc|Ghs)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);

final RegExp _reference = RegExp(
  r'(?:ref(?:erence)?|trans(?:action)? ?id)[:.#]?\s*([A-Za-z0-9][A-Za-z0-9.\-/]{4,})',
  caseSensitive: false,
);

/// The ref, minus any sentence punctuation it swallowed on the way out —
/// MTN refs contain internal dots, so the charset above can't exclude them.
String? _extractReference(String text) {
  final raw = _reference.firstMatch(text)?.group(1);
  if (raw == null) return null;
  final trimmed = raw.replaceAll(RegExp(r'^[.,;\-]+|[.,;\-]+$'), '');
  return trimmed.length >= 5 ? trimmed.toUpperCase() : null;
}

double? _toAmount(String? raw) {
  if (raw == null) return null;
  final v = double.tryParse(raw.replaceAll(',', ''));
  // Zero is a real reading ('Fee: GHS0.00'), so only parse failures are null.
  return v;
}

/// The main amount: the first currency figure that is not the fee and not the
/// balance. MTN writes 'Fee:' and 'Balance:' before their own numbers, so the
/// first bare amount in reading order is the transaction itself.
(double? main, double? fee, double? balance) _extractAmounts(String text) {
  final feeMatch = _feeAmount.firstMatch(text);
  final balMatch = _balanceAmount.firstMatch(text);

  double? first;
  for (final m in _amountAfterCode.allMatches(text)) {
    final start = m.start;
    final isFee = feeMatch != null &&
        start >= feeMatch.start &&
        start < feeMatch.end;
    final isBal = balMatch != null &&
        start >= balMatch.start &&
        start < balMatch.end;
    if (!isFee && !isBal) {
      first = _toAmount(m.group(1));
      break;
    }
  }

  // Some alerts write the fee without a currency code at all ('Fee:0.46').
  final fee = _toAmount(feeMatch?.group(1)) ?? 0;
  return (first, fee, _toAmount(balMatch?.group(1)));
}

String? _counterpartyAfter(String text, List<String> prepositions) {
  for (final prep in prepositions) {
    final m = RegExp(
      '$prep\\s+(.{2,80}?)'
      r'(?:\s+on\s+[0-9]|\s+with\s+(?:reference|ref)|\s+has\s+paid|[.,;]?\s*(?:fee|balance|bal|ref|avail|thank|your account)[:.,]|[.,;]$|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) {
      // Drop phone numbers the sender pads the name with —
      // '0244123456/KWAME' and 'KWAME 0244123456' are both just KWAME.
      var name = m
          .group(1)!
          .replaceAll(RegExp(r'\b0[235][0-9]{8,9}\b'), ' ')
          .replaceAll(RegExp(r'\b[0-9]{10,}\b'), ' ');
      name = normalizeCounterparty(name);
      if (name.length >= 2) return name;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// MTN Mobile Money
// ---------------------------------------------------------------------------

/// MTN Ghana MoMo alerts — the sender this whole feature was built around.
///
/// Real alerts vary in phrasing but keep one skeleton: a direction phrase, an
/// amount, a counterparty, a fee, a balance and a ref, in roughly that order.
/// The parser keys on the direction phrase, takes the first non-fee non-balance
/// amount as the transaction, and treats anything with a figure but no
/// recognised direction as unreadable rather than guessing debit.
class MtnMomoParser extends BankSmsParser {
  @override
  String get id => 'mtn_momo';

  @override
  String get displayName => 'MTN MoMo';

  @override
  List<String> get senderAddresses => ['MobileMoney', 'MTN MoMo', 'MTNMoney'];

  @override
  String get identifiersHint =>
      'Your MoMo number as alerts write it, e.g. 0244123456';

  static final List<RegExp> _creditPhrases = [
    RegExp(r'you have received', caseSensitive: false),
    RegExp(r'received\s+(?:GHS|GH¢|GH₵)?\s*[0-9]', caseSensitive: false),
    RegExp(r'has been credited', caseSensitive: false),
    RegExp(r'credited with', caseSensitive: false),
    RegExp(r'paid\s+(?:GHS|GH¢|GH₵)?\s*[0-9].*?to your (?:account|wallet)',
        caseSensitive: false),
    RegExp(r'has paid', caseSensitive: false),
    RegExp(r'deposit of', caseSensitive: false),
  ];

  static final List<RegExp> _debitPhrases = [
    RegExp(r'payment (?:made|of|for)', caseSensitive: false),
    RegExp(r'you have sent', caseSensitive: false),
    RegExp(r'sent to', caseSensitive: false),
    RegExp(r'cash[- ]?out', caseSensitive: false),
    RegExp(r'withdraw(?:n|al)', caseSensitive: false),
    RegExp(r'you have (?:bought|purchased)', caseSensitive: false),
    RegExp(r'(?:airtime|bundle|data).{0,30}(?:purchase|bought)', caseSensitive: false),
    RegExp(r'you have paid', caseSensitive: false),
    RegExp(r'transfer(?: of|red)?\b.*\bto\b', caseSensitive: false),
  ];

  @override
  ParsedSms parse(RawSms sms) {
    final text = sms.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final (main, fee, balance) = _extractAmounts(text);

    // A MoMo alert without any currency figure is a promo, an OTP or a
    // notice. Not money — record it as ignored and move on.
    if (main == null && fee == 0 && balance == null) {
      return ParsedSms(
        parserId: id,
        verdict: SmsVerdict.notMoney,
        occurredAt: sms.receivedAt,
      );
    }

    SmsDirection? direction;
    for (final p in _creditPhrases) {
      if (p.hasMatch(text)) {
        direction = SmsDirection.credit;
        break;
      }
    }
    direction ??= _debitPhrases.any((p) => p.hasMatch(text))
        ? SmsDirection.debit
        : null;

    if (direction == null || main == null) {
      return ParsedSms(
        parserId: id,
        verdict: SmsVerdict.unparsed,
        occurredAt: sms.receivedAt,
        amount: main,
        fee: fee == 0 ? null : fee,
        balance: balance,
        dedupeKey: null,
        summary: 'MoMo alert read but not understood',
      );
    }

    // Who is on the other end. 'from X' for credits, 'to/at X' for debits;
    // withdrawals name the agent with 'at', merchant wallets say 'Customer X
    // has paid'.
    var counterparty = direction == SmsDirection.credit
        ? _counterpartyAfter(text, ['from', 'by', 'customer'])
        : (_counterpartyAfter(text, ['to']) ??
            _counterpartyAfter(text, ['at']));
    // Alerts with no payee at all still name what the money bought. Giving
    // them a stable stand-in is what lets one review ('airtime is Transport…
    // no, Bills') teach every future airtime alert.
    if (counterparty == null) {
      if (RegExp(r'airtime', caseSensitive: false).hasMatch(text)) {
        counterparty = 'AIRTIME';
      } else if (RegExp(r'\b(?:data|bundle)\b', caseSensitive: false)
          .hasMatch(text)) {
        counterparty = 'DATA BUNDLE';
      } else if (direction == SmsDirection.debit &&
          RegExp(r'cash[- ]?out|withdraw', caseSensitive: false)
              .hasMatch(text)) {
        counterparty = 'CASH WITHDRAWAL';
      }
    }

    final ref = _extractReference(text);
    final dedupe = _dedupeKey(direction, main, ref, sms);

    final verb = direction == SmsDirection.credit ? 'from' : 'to';
    final summary = StringBuffer();
    summary.write(direction == SmsDirection.credit ? 'Received' : 'Paid');
    summary.write(' GHS ${main.toStringAsFixed(2)}');
    if (counterparty != null) summary.write(' $verb $counterparty');
    if (fee != null && fee > 0) {
      summary.write(' (fee ${fee.toStringAsFixed(2)})');
    }

    return ParsedSms(
      parserId: id,
      verdict: SmsVerdict.money,
      direction: direction,
      amount: main,
      fee: fee != null && fee > 0 ? fee : null,
      balance: balance,
      counterparty: counterparty,
      reference: ref,
      occurredAt: sms.receivedAt,
      dedupeKey: dedupe,
      summary: summary.toString(),
    );
  }

  /// Qualified by amount and time, never the raw reference alone: Fidelity
  /// bills a transfer and its fee as two alerts sharing one session id, and a
  /// fee row keyed like its parent would silently swallow the parent.
  String _dedupeKey(
    SmsDirection direction,
    double amount,
    String? ref,
    RawSms sms,
  ) {
    final refPart = ref ?? '${sms.receivedAt.millisecondsSinceEpoch}';
    return '$id|${direction.name}|${amount.toStringAsFixed(2)}|$refPart';
  }
}

// ---------------------------------------------------------------------------
// Bank alerts — deliberately conservative
// ---------------------------------------------------------------------------

/// The three bank senders. Bank alert formats are looser than MoMo's and
/// change without notice, so these parsers only claim a message when a debit
/// or credit keyword sits next to an amount; everything else lands in the
/// review queue rather than in the books.
class GenericBankParser extends BankSmsParser {
  @override
  final String id;
  @override
  final String displayName;
  @override
  final List<String> senderAddresses;
  @override
  final String identifiersHint;

  GenericBankParser({
    required this.id,
    required this.displayName,
    required this.senderAddresses,
    required this.identifiersHint,
  });

  static const _debitWords = [
    'debit', 'debited', 'withdrawal', 'withdrew', 'paid to',
    'payment to', 'purchase', 'pos ', 'transfer to', 'sent to',
  ];
  static const _creditWords = [
    'credit', 'credited', 'deposit', 'received', 'reversal',
    'refund', 'transfer from',
  ];

  @override
  ParsedSms parse(RawSms sms) {
    final text = sms.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = ' ${text.toLowerCase()} ';
    final (main, fee, balance) = _extractAmounts(text);

    if (main == null && fee == 0 && balance == null) {
      return ParsedSms(
        parserId: id,
        verdict: SmsVerdict.notMoney,
        occurredAt: sms.receivedAt,
      );
    }

    final isDebit = _debitWords.any(lower.contains);
    final isCredit = _creditWords.any(lower.contains);

    // Both or neither — the words alone can't say which way the money moved.
    if (isDebit == isCredit || main == null) {
      return ParsedSms(
        parserId: id,
        verdict: SmsVerdict.unparsed,
        occurredAt: sms.receivedAt,
        amount: main,
        balance: balance,
        dedupeKey: null,
        summary: 'Bank alert read but not understood',
      );
    }

    final counterparty = _counterpartyAfter(text, ['to', 'from', 'at', 'by']);
    final ref = _extractReference(text);
    final direction =
        isDebit ? SmsDirection.debit : SmsDirection.credit;

    return ParsedSms(
      parserId: id,
      verdict: SmsVerdict.money,
      direction: direction,
      amount: main,
      fee: fee != null && fee > 0 ? fee : null,
      balance: balance,
      counterparty: counterparty,
      reference: ref,
      occurredAt: sms.receivedAt,
      dedupeKey:
          '$id|${direction.name}|${main.toStringAsFixed(2)}|${ref ?? sms.receivedAt.millisecondsSinceEpoch}',
      summary: '${direction == SmsDirection.credit ? 'Received' : 'Paid'} '
          'GHS ${main.toStringAsFixed(2)}'
          '${counterparty == null ? '' : ' ${direction == SmsDirection.credit ? 'from' : 'to'} $counterparty'}',
    );
  }
}

/// Every parser the app knows, keyed by id for `sms_account_links`.
final List<BankSmsParser> kBankSmsParsers = [
  MtnMomoParser(),
  GenericBankParser(
    id: 'fidelity',
    displayName: 'Fidelity Bank',
    senderAddresses: const ['Fidelity', 'FidelityBank', 'Fidelity Bank'],
    identifiersHint: 'Masked account number as alerts write it, e.g. 1234',
  ),
  GenericBankParser(
    id: 'access',
    displayName: 'Access Bank',
    senderAddresses: const ['AccessBank', 'Access Bank', 'Access'],
    identifiersHint: 'Masked account number as alerts write it, e.g. 0912',
  ),
  GenericBankParser(
    id: 'cbg',
    displayName: 'CBG',
    senderAddresses: const ['CBG', 'ConsolidatedBank', 'CB-Ghana'],
    identifiersHint: 'Masked account number as alerts write it, e.g. 0045',
  ),
];

BankSmsParser? parserById(String id) {
  for (final p in kBankSmsParsers) {
    if (p.id == id) return p;
  }
  return null;
}

/// Does this on-device address belong to this parser? Handles the shortcodes
/// and spacing the carriers actually use ('MobileMoney', 'Mobile Money').
bool addressMatchesParser(String address, BankSmsParser parser) {
  String fold(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final a = fold(address);
  if (a.isEmpty) return false;
  return parser.senderAddresses.any((sender) => a.contains(fold(sender)));
}

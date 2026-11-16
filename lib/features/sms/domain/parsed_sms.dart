/// What one bank/MoMo message reduced to, and how confident the parser is.
///
/// The three verdicts drive the whole import decision:
///  * [money]      — we know direction and amount; routing rules decide the rest.
///  * [notMoney]   — an OTP, a promo, a balance notice. Recorded as ignored so
///                   a re-scan skips it, but never shown to the user.
///  * [unparsed]   — from a sender we know, in a shape we don't. Goes to the
///                   review queue; silently dropping it is how a quiet month
///                   hides a real one.
enum SmsVerdict { money, notMoney, unparsed }

/// Which way the money moved, from the account the sender speaks for.
enum SmsDirection { credit, debit }

/// The parsed shape stored in `sms_inbox.parsed` and handed to the import RPCs.
class ParsedSms {
  /// Matches `sms_account_links.parser_id` — 'mtn_momo', 'fidelity', …
  final String parserId;
  final SmsVerdict verdict;
  final SmsDirection? direction;
  final double? amount;
  final double? fee;
  final double? balance;
  final String? counterparty;

  /// The bank's own reference. Part of the dedupe key when present.
  final String? reference;
  final DateTime occurredAt;

  /// Null exactly when [verdict] is [SmsVerdict.unparsed] — a message we
  /// couldn't read has no amount or reference to build a key from, and must
  /// not block a later one that shares its text. The scan pipeline gives
  /// unparsed messages a content-hash fallback key instead, so re-scans stay
  /// idempotent without violating that rule.
  final String? dedupeKey;

  /// One line a human can check the parse against, e.g.
  /// 'Payment to SILVERBIRD, GHS 20.00 (fee 0.46)'.
  final String? summary;

  const ParsedSms({
    required this.parserId,
    required this.verdict,
    required this.occurredAt,
    this.direction,
    this.amount,
    this.fee,
    this.balance,
    this.counterparty,
    this.reference,
    this.dedupeKey,
    this.summary,
  });

  bool get isMoney => verdict == SmsVerdict.money;

  Map<String, dynamic> toJson() => {
        'parser_id': parserId,
        'verdict': verdict.name,
        if (direction != null) 'direction': direction!.name,
        if (amount != null) 'amount': amount,
        if (fee != null) 'fee': fee,
        if (balance != null) 'balance': balance,
        if (counterparty != null) 'counterparty': counterparty,
        if (reference != null) 'reference': reference,
        if (summary != null) 'summary': summary,
      };

  factory ParsedSms.fromJson(Map<String, dynamic> j) => ParsedSms(
        parserId: j['parser_id'] as String,
        verdict: SmsVerdict.values.firstWhere(
          (v) => v.name == j['verdict'],
          orElse: () => SmsVerdict.unparsed,
        ),
        direction: j['direction'] == null
            ? null
            : SmsDirection.values
                .firstWhere((d) => d.name == j['direction']),
        amount: (j['amount'] as num?)?.toDouble(),
        fee: (j['fee'] as num?)?.toDouble(),
        balance: (j['balance'] as num?)?.toDouble(),
        counterparty: j['counterparty'] as String?,
        reference: j['reference'] as String?,
        dedupeKey: null,
        summary: j['summary'] as String?,
        occurredAt: DateTime.now(),
      );
}

/// Counterparty names as rules and matches see them: upper-cased and
/// space-collapsed, so 'INTERCITY STC  COACHES' typed after two spaces and
/// 'Intercity stc coaches' in an alert are one string, not two.
String normalizeCounterparty(String raw) => raw
    .replaceAll(RegExp(r'\s+'), ' ')
    .toUpperCase()
    .replaceAll(RegExp(r'^[ ,./-]+|[ ,./-]+$'), '')
    .trim();

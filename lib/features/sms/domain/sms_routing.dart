import '../../../../core/constants.dart';
import '../../../../core/formatters.dart';
import '../../transactions/domain/transaction.dart';
import 'parsed_sms.dart';

/// One learned routing rule — `sms_routing_rules` as the app sees it.
///
/// Learned once from the review queue, then applied silently on every scan.
class SmsRoutingRule {
  final String id;
  final String? parserId;
  final String matchText;
  final String matchKind; // 'contains' | 'exact'
  final TxnType txnType;
  final String? category;

  /// The account at the other end of a transfer.
  final String? counterpartAccountId;
  final int priority;

  const SmsRoutingRule({
    required this.id,
    required this.matchText,
    required this.txnType,
    required this.matchKind,
    this.parserId,
    this.category,
    this.counterpartAccountId,
    this.priority = 0,
  });

  factory SmsRoutingRule.fromJson(Map<String, dynamic> j) => SmsRoutingRule(
        id: j['id'] as String,
        parserId: j['parser_id'] as String?,
        matchText: j['match_text'] as String,
        matchKind: (j['match_kind'] as String?) ?? 'contains',
        txnType: TxnType.fromLabel((j['txn_type'] as String?) ?? 'Expense'),
        category: j['category'] as String?,
        counterpartAccountId: j['counterpart_account_id'] as String?,
        priority: (j['priority'] as int?) ?? 0,
      );

  /// True when this rule speaks for a message from [parserId]. A null
  /// parser_id matches any sender.
  bool appliesTo(String parserId) =>
      this.parserId == null || this.parserId == parserId;

  /// Whether [counterparty] — already normalized — satisfies the match.
  bool matches(String counterparty) {
    final mine = normalizeCounterparty(matchText);
    if (mine.isEmpty) return false;
    return matchKind == 'exact' ? counterparty == mine : counterparty.contains(mine);
  }
}

/// The first rule that decides this message, or null when nothing matches.
///
/// Highest priority wins so one specific merchant ('STANBIC LOAN') can
/// override a broad rule ('STANBIC'); at equal priority the longer — more
/// specific — match text wins.
SmsRoutingRule? pickRoutingRule({
  required String parserId,
  required String? counterparty,
  required List<SmsRoutingRule> rules,
}) {
  if (counterparty == null || counterparty.isEmpty) return null;
  SmsRoutingRule? best;
  for (final r in rules) {
    if (!r.appliesTo(parserId) || !r.matches(counterparty)) continue;
    final better = best == null ||
        r.priority > best.priority ||
        (r.priority == best.priority &&
            r.matchText.length > best.matchText.length);
    if (better) best = r;
  }
  return best;
}

/// The transaction the importer will write, before the RPC writes it.
/// Mirrors the jsonb `sms_insert_planned_txn` consumes.
class PlannedTxn {
  final String accountId;
  final String? toAccountId;
  final TxnType type;
  final double amount;
  final String category;
  final String? description;
  final DateTime date;
  final String externalRef;

  const PlannedTxn({
    required this.accountId,
    required this.type,
    required this.amount,
    required this.category,
    required this.date,
    required this.externalRef,
    this.toAccountId,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'account_id': accountId,
        'to_account_id': toAccountId ?? '',
        'type': type.label,
        'amount': amount,
        'category': category,
        'description': description ?? '',
        'date': dateFmt.format(date),
        'external_ref': externalRef,
      };
}

/// What a scan decided to do with one message.
sealed class SmsDecision {
  const SmsDecision();
}

/// Import now — a rule knew exactly where this belongs.
class ImportDecision extends SmsDecision {
  final PlannedTxn txn;
  final PlannedTxn? fee;
  final String dedupeKey;
  const ImportDecision(this.txn, this.fee, this.dedupeKey);
}

/// Queue it — parsed fine, but no rule vouches for the counterparty.
class ReviewDecision extends SmsDecision {
  final PlannedTxn? fee;
  final String dedupeKey;
  const ReviewDecision(this.fee, this.dedupeKey);
}

/// Not money — an OTP, promo or notice.
class IgnoreDecision extends SmsDecision {
  const IgnoreDecision();
}

/// From a linked sender, in a shape the parser doesn't understand.
class UnparsedDecision extends SmsDecision {
  const UnparsedDecision();
}

/// Applies routing rules to one parsed message and says what should happen.
///
/// Pure: the scan pipeline calls it per message, tests call it directly.
SmsDecision decideForMessage({
  required ParsedSms parsed,
  required String senderAccountId,
  required List<SmsRoutingRule> rules,
}) {
  switch (parsed.verdict) {
    case SmsVerdict.notMoney:
      return const IgnoreDecision();

    case SmsVerdict.unparsed:
      // No fee either: without a direction we can't even say which account
      // the fee drained, so the whole message waits for the queue.
      return const UnparsedDecision();

    case SmsVerdict.money:
      final rule = pickRoutingRule(
        parserId: parsed.parserId,
        counterparty: parsed.counterparty,
        rules: rules,
      );

      final PlannedTxn? fee = parsed.fee != null && parsed.fee! > 0
          ? PlannedTxn(
              accountId: senderAccountId,
              type: TxnType.expense,
              amount: parsed.fee!,
              category: kBankChargesCategory,
              date: parsed.occurredAt,
              externalRef: '${parsed.dedupeKey}|fee',
              description: 'Fee — ${parsed.summary ?? parsed.parserId}',
            )
          : null;

      // No rule vouches for this counterparty: hold the transaction for
      // review (with its fee already on the books) rather than guessing a
      // category the reports will silently inherit.
      if (rule == null) {
        return ReviewDecision(fee, parsed.dedupeKey!);
      }

      if (rule.txnType == TxnType.transfer) {
        // One rule serves both directions: on a debit the money leaves the
        // sender's account and lands at the counterpart; on a credit it
        // travels the other way.
        final (from, to) = parsed.direction == SmsDirection.debit
            ? (senderAccountId, rule.counterpartAccountId!)
            : (rule.counterpartAccountId!, senderAccountId);
        return ImportDecision(
          PlannedTxn(
            accountId: from,
            toAccountId: to,
            type: TxnType.transfer,
            amount: parsed.amount!,
            // The ledger stores kTransferCategory on transfer rows; the rule's
            // own category stays null by its shape constraint.
            category: kTransferCategory,
            date: parsed.occurredAt,
            externalRef: parsed.dedupeKey!,
            description:
                'Transfer ${parsed.direction == SmsDirection.debit ? 'to' : 'from'} '
                '${parsed.counterparty ?? 'linked account'}',
          ),
          fee,
          parsed.dedupeKey!,
        );
      }

      return ImportDecision(
        PlannedTxn(
          accountId: senderAccountId,
          type: rule.txnType,
          amount: parsed.amount!,
          category: rule.category!,
          date: parsed.occurredAt,
          externalRef: parsed.dedupeKey!,
          description: parsed.summary,
        ),
        fee,
        parsed.dedupeKey!,
      );
  }
}

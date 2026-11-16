import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/bank_sms_parser.dart';
import '../domain/parsed_sms.dart';
import '../domain/sms_routing.dart';
import 'device_sms_reader.dart';

/// A sender the user linked to one of their accounts — `sms_account_links`.
class SmsAccountLink {
  final String id;
  final String parserId;
  final String accountId;
  final List<String> identifiers;

  const SmsAccountLink({
    required this.id,
    required this.parserId,
    required this.accountId,
    required this.identifiers,
  });

  factory SmsAccountLink.fromJson(Map<String, dynamic> j) => SmsAccountLink(
        id: j['id'] as String,
        parserId: j['parser_id'] as String,
        accountId: j['account_id'] as String,
        identifiers: (j['identifiers'] as List?)?.cast<String>() ?? const [],
      );
}

/// One row of the review queue — `sms_inbox`.
class SmsInboxItem {
  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final String status; // 'pending' | 'unparsed'
  final ParsedSms? parsed;

  /// Null only for rows written before this app version set fallback keys.
  final String? dedupeKey;
  final String? transactionId;

  const SmsInboxItem({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.status,
    required this.dedupeKey,
    this.parsed,
    this.transactionId,
  });

  bool get isUnparsed => status == 'unparsed';

  factory SmsInboxItem.fromJson(Map<String, dynamic> j) => SmsInboxItem(
        id: j['id'] as String,
        sender: j['sender'] as String,
        body: j['body'] as String,
        receivedAt: DateTime.parse(j['received_at'] as String),
        status: j['status'] as String,
        dedupeKey: j['dedupe_key'] as String?,
        transactionId: j['transaction_id'] as String?,
        parsed: j['parsed'] == null
            ? null
            : ParsedSms.fromJson((j['parsed'] as Map).cast<String, dynamic>()),
      );
}

/// What one scan of the inbox achieved, as shown on the SMS import screen.
class ScanResult {
  final int scanned;
  final int imported;
  final int fees;
  final int reviewQueued;
  final int unparsed;
  final int ignored;
  final int errors;
  final bool permissionDenied;
  final bool noSendersLinked;

  const ScanResult({
    this.scanned = 0,
    this.imported = 0,
    this.fees = 0,
    this.reviewQueued = 0,
    this.unparsed = 0,
    this.ignored = 0,
    this.errors = 0,
    this.permissionDenied = false,
    this.noSendersLinked = false,
  });

  /// 'Nothing to do' in the words the screen uses.
  String get summaryLine {
    if (noSendersLinked) return 'Link a sender first — nothing to read yet.';
    if (permissionDenied) return 'Permission to read messages was not given.';
    final bits = <String>[
      if (imported > 0) '$imported imported',
      if (fees > 0) '$fees fee${fees == 1 ? '' : 's'}',
      if (reviewQueued > 0) '$reviewQueued to review',
      if (unparsed > 0) '$unparsed unreadable',
      if (ignored > 0) '$ignored skipped',
      if (errors > 0) '$errors failed — is the backend reachable?',
    ];
    if (bits.isEmpty) {
      return scanned == 0
          ? 'No messages from your linked senders.'
          : 'Everything already recorded.';
    }
    return bits.join(' · ');
  }
}

class SmsImportRepository {
  final DeviceSmsReader _reader;

  SmsImportRepository({required DeviceSmsReader reader}) : _reader = reader;

  // ---------------------------------------------------------------- links

  Future<List<SmsAccountLink>> links() async {
    final rows = await api.get('/sms/links');
    return (rows as List)
        .map((r) => SmsAccountLink.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLink({
    required String parserId,
    required String accountId,
    List<String> identifiers = const [],
  }) async {
    // PUT upserts on (user, parser) — one sender speaks for one account.
    await api.put('/sms/links', body: {
      'parser_id': parserId,
      'account_id': accountId,
      'identifiers': identifiers,
    });
  }

  Future<void> deleteLink(String id) async {
    await api.delete('/sms/links/$id');
  }

  // ---------------------------------------------------------------- rules

  Future<List<SmsRoutingRule>> rules() async {
    final rows = await api.get('/sms/rules');
    return (rows as List)
        .map((r) => SmsRoutingRule.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Learns one counterparty so the next scan routes it silently.
  Future<void> addRule({
    required String matchText,
    required TxnType txnType,
    String? parserId,
    String? category,
    String? counterpartAccountId,
  }) async {
    await api.post('/sms/rules', body: {
      'parser_id': parserId,
      'match_text': matchText,
      'match_kind': 'contains',
      'txn_type': txnType.label,
      'category': category,
      'counterpart_account_id': counterpartAccountId,
    });
  }

  Future<void> deleteRule(String id) async {
    await api.delete('/sms/rules/$id');
  }

  // ---------------------------------------------------------------- inbox

  Future<List<SmsInboxItem>> reviewQueue() async {
    final rows = await api.get('/sms/inbox', query: {'limit': '60'});
    return (rows as List)
        .map((r) => SmsInboxItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> ignoreInboxItem(String id) async {
    await api.post('/sms/inbox/$id/ignore');
  }

  // ---------------------------------------------------------------- scan

  /// Reads the inbox once, routes every message from a linked sender, and
  /// writes the outcome. Re-running it is harmless by design: identical
  /// messages hit the dedupe keys and change nothing.
  ///
  /// Messages whose key the server already holds are skipped before any
  /// network call, so repeat scans cost one query plus only what's new, and
  /// the remaining writes go six at a time — a first backfill takes well
  /// under a minute instead of one round trip per old alert.
  Future<ScanResult> scan() async {
    final links = await this.links();
    if (links.isEmpty) {
      return const ScanResult(noSendersLinked: true);
    }

    if (!await _reader.isGranted()) {
      final granted = await _reader.request();
      if (!granted) return const ScanResult(permissionDenied: true);
    }

    // Only senders the user linked are ever read — the Kotlin side receives
    // this list and queries nothing else.
    final addresses = <String>{
      for (final link in links)
        if (parserById(link.parserId) != null)
          ...parserById(link.parserId)!.senderAddresses,
    }.toList();
    final messages = await _reader.query(addresses: addresses);
    if (messages.isEmpty) return const ScanResult();

    // Every message this user has ever dealt with, any status. A key in here
    // means the server's own conflict guards would no-op anyway — paying for
    // the round trip is the only thing being skipped.
    final knownKeys = <String>{};
    final seen = await api.get('/sms/inbox/keys');
    for (final k in (seen as List)) {
      if (k is String && k.isNotEmpty) knownKeys.add(k);
    }

    final rules = await this.rules();
    var scanned = 0, imported = 0, fees = 0;
    var review = 0, unparsed = 0, ignored = 0, errors = 0;

    // Find the linked parser this address belongs to; anything else (a
    // shortcode sibling, a forwarded message) is not ours to read.
    (BankSmsParser, SmsAccountLink)? parserFor(RawSms msg) {
      for (final l in links) {
        final p = parserById(l.parserId);
        if (p != null && addressMatchesParser(msg.address, p)) return (p, l);
      }
      return null;
    }

    Future<void> workOne(RawSms msg) async {
      final match = parserFor(msg);
      if (match == null) return;
      final (parser, link) = match;

      final parsed = parser.parse(msg);
      final key = parsed.verdict == SmsVerdict.money
          ? parsed.dedupeKey!
          : _messageKey(msg, parser.id);
      if (knownKeys.contains(key)) return;
      scanned++;

      try {
        final decision = decideForMessage(
          parsed: parsed,
          senderAccountId: link.accountId,
          rules: rules,
        );

        switch (decision) {
          case ImportDecision(:final txn, :final fee, :final dedupeKey):
            await api.post('/sms/import', body: {
              'sender': msg.address,
              'body': msg.body,
              'received_at': msg.receivedAt.toIso8601String(),
              'dedupe_key': dedupeKey,
              'parsed': parsed.toJson(),
              'txn': txn.toJson(),
              'fee': fee?.toJson(),
            });
            imported++;
            fees += fee == null ? 0 : 1;

          case ReviewDecision(:final fee, :final dedupeKey):
            await api.post('/sms/hold', body: {
              'sender': msg.address,
              'body': msg.body,
              'received_at': msg.receivedAt.toIso8601String(),
              'dedupe_key': dedupeKey,
              'parsed': parsed.toJson(),
              'fee': fee?.toJson(),
            });
            review++;
            fees += fee == null ? 0 : 1;

          case UnparsedDecision():
            // A key derived from the physical message keeps re-scans
            // idempotent while never colliding with a parsed message's key.
            await api.post('/sms/hold', body: {
              'sender': msg.address,
              'body': msg.body,
              'received_at': msg.receivedAt.toIso8601String(),
              'dedupe_key': key,
              'parsed': parsed.toJson(),
            });
            unparsed++;

          case IgnoreDecision():
            await api.post('/sms/ignore', body: {
              'sender': msg.address,
              'body': msg.body,
              'received_at': msg.receivedAt.toIso8601String(),
              'dedupe_key': key,
            });
            ignored++;
        }
      } catch (_) {
        // One bad row must not stop the sweep; the next scan retries it.
        errors++;
      }
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= messages.length) break;
        await workOne(messages[i]);
      }
    }

    await Future.wait([for (var w = 0; w < 6; w++) worker()]);

    return ScanResult(
      scanned: scanned,
      imported: imported,
      fees: fees,
      reviewQueued: review,
      unparsed: unparsed,
      ignored: ignored,
      errors: errors,
    );
  }

  String _messageKey(RawSms msg, String parserId) =>
      'msg|$parserId|${msg.providerId.isEmpty ? msg.receivedAt.millisecondsSinceEpoch : msg.providerId}|${msg.body.hashCode.toRadixString(36)}';

  // ---------------------------------------------------------------- review

  /// Turns one queued message into a transaction, and optionally learns the
  /// rule that would have made the review unnecessary.
  Future<void> resolveReview({
    required SmsInboxItem item,
    required TxnType type,
    required String accountId,
    required double amount,
    required DateTime date,
    String? category,
    String? counterpartAccountId,
    String? description,
    bool rememberRule = false,
  }) async {
    final externalRef =
        item.dedupeKey ?? 'review|${item.id}|${amount.toStringAsFixed(2)}';

    final txn = PlannedTxn(
      accountId: accountId,
      toAccountId: counterpartAccountId,
      type: type,
      amount: amount,
      // Transfer rows wear the shared label — see
      // TransactionRepository.createTransfer, which writes the same one.
      category: category ?? kTransferCategory,
      date: date,
      externalRef: externalRef,
      description: description,
    );

    await api.post('/sms/inbox/${item.id}/resolve', body: {
      'txn': txn.toJson(),
    });

    if (rememberRule) {
      final counterparty = item.parsed?.counterparty;
      if (counterparty != null && counterparty.isNotEmpty) {
        await addRule(
          matchText: counterparty,
          txnType: type,
          parserId: item.parsed?.parserId,
          category: type == TxnType.transfer ? null : category,
          counterpartAccountId:
              type == TxnType.transfer ? counterpartAccountId : null,
        );
      }
    }
  }
}

// The server inserts `txn.category` verbatim, and this app's ledger stores
// 'Transfer' on transfer rows (see TransactionRepository.createTransfer).

// -------------------------------------------------------------- providers

final smsImportRepositoryProvider = Provider<SmsImportRepository>((ref) =>
    SmsImportRepository(reader: ref.watch(deviceSmsReaderProvider)));

/// One knob the screen turns after any write so links, rules and the queue
/// all come back fresh.
final smsRefreshProvider = StateProvider<int>((_) => 0);

final smsLinksProvider = FutureProvider<List<SmsAccountLink>>((ref) async {
  ref.watch(smsRefreshProvider);
  return ref.watch(smsImportRepositoryProvider).links();
});

final smsRulesProvider = FutureProvider<List<SmsRoutingRule>>((ref) async {
  ref.watch(smsRefreshProvider);
  return ref.watch(smsImportRepositoryProvider).rules();
});

final smsInboxProvider = FutureProvider<List<SmsInboxItem>>((ref) async {
  ref.watch(smsRefreshProvider);
  return ref.watch(smsImportRepositoryProvider).reviewQueue();
});

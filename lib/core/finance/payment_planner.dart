import '../../features/accounts/domain/account.dart';
import '../../features/planning/domain/obligation.dart';
import '../formatters.dart';
import 'money_engine.dart';

/// Answers the question the app was never able to answer: *I need to send this
/// money — where should it come from?*
///
/// The decision is made here, in Dart, from floors, pinned bills and liquidity.
/// It is deterministic and explainable: every account that was passed over
/// carries the reason it was passed over. A model may later rephrase this, but
/// it never decides it.

/// How much damage taking money from an account would do.
enum SourceQuality {
  /// Covers it from money that is genuinely spare.
  clean,

  /// Covers it, but eats into money a known bill is going to need.
  dipsIntoBills,

  /// Covers it only by going under the floor the user set.
  breaksFloor,

  /// Does not hold enough at all.
  insufficient,
}

class PaymentCandidate {
  final AccountStanding standing;
  final SourceQuality quality;

  /// Why this account is not ideal, in the user's terms. Null when it is.
  final String? caution;

  const PaymentCandidate({
    required this.standing,
    required this.quality,
    required this.caution,
  });

  Account get account => standing.account;

  /// The most this account can give at each level of harm.
  double get spare => standing.freeToMove;
  double get aboveFloor => standing.available;
  double get everything => standing.account.balance;

  double capacityFor(SourceQuality q) => switch (q) {
        SourceQuality.clean => spare,
        SourceQuality.dipsIntoBills => aboveFloor,
        SourceQuality.breaksFloor => everything,
        SourceQuality.insufficient => 0,
      };
}

/// One account contributing to the payment.
class PaymentSource {
  final Account account;
  final double amount;
  final SourceQuality quality;
  final String? caution;

  const PaymentSource({
    required this.account,
    required this.amount,
    required this.quality,
    required this.caution,
  });
}

/// A move that has to happen before the payment can go out of the account the
/// user insisted on using.
class PaymentTransfer {
  final Account from;
  final Account to;
  final double amount;

  const PaymentTransfer({
    required this.from,
    required this.to,
    required this.amount,
  });
}

/// What the payment does to the user's position.
class PaymentImpact {
  final double safeToSpendAfter;
  final double? runwayDaysAfter;
  final int? daysUntilIncome;

  const PaymentImpact({
    required this.safeToSpendAfter,
    required this.runwayDaysAfter,
    required this.daysUntilIncome,
  });

  /// True when making this payment causes the money to run out before more
  /// arrives — the thing worth knowing *before* pressing send.
  bool get causesShortfall {
    final r = runwayDaysAfter;
    final d = daysUntilIncome;
    if (r == null || d == null) return false;
    return r < d;
  }
}

class PaymentPlan {
  final double amount;

  /// False when the money simply is not there.
  final bool isPossible;

  /// Where to take it from, in order.
  final List<PaymentSource> sources;

  /// Moves needed first, when the payment must leave a particular account.
  final List<PaymentTransfer> transfers;

  /// The recommendation, as a sentence.
  final String headline;

  /// Why each other account was not chosen.
  final List<String> reasoning;

  final PaymentImpact impact;

  const PaymentPlan({
    required this.amount,
    required this.isPossible,
    required this.sources,
    required this.transfers,
    required this.headline,
    required this.reasoning,
    required this.impact,
  });

  bool get isSplit => sources.length > 1;

  /// True when nothing about this plan needs a warning.
  bool get isClean =>
      isPossible && sources.every((s) => s.quality == SourceQuality.clean);
}

/// Ranks every account for a payment of [amount], worst reason last.
List<PaymentCandidate> rankSources({
  required MoneySnapshot snapshot,
  required double amount,
  List<Obligation> obligations = const [],
  String? excludeAccountId,
}) {
  final candidates = <PaymentCandidate>[];

  for (final standing in snapshot.standings) {
    final a = standing.account;
    if (a.isArchived) continue;
    if (a.id == excludeAccountId) continue;

    final quality = _qualityFor(standing, amount);
    candidates.add(PaymentCandidate(
      standing: standing,
      quality: quality,
      caution: _cautionFor(standing, quality, obligations, snapshot),
    ));
  }

  candidates.sort((x, y) {
    // Spendable money first, then reserved, then locked — never raid a fixed
    // deposit when a current account would do.
    final byLiquidity =
        _liquidityRank(x.account).compareTo(_liquidityRank(y.account));
    if (byLiquidity != 0) return byLiquidity;

    final byQuality = x.quality.index.compareTo(y.quality.index);
    if (byQuality != 0) return byQuality;

    // Among equals, take from wherever leaves the most room behind.
    return (y.spare - amount).compareTo(x.spare - amount);
  });

  return candidates;
}

/// Works out where a payment should come from, and what it costs the user.
///
/// [payFromAccountId] forces the payment to leave a particular account — the
/// real case where the money has to go out over mobile money, or from the card
/// attached to one bank. The plan then covers topping that account up first.
PaymentPlan planPayment({
  required double amount,
  required MoneySnapshot snapshot,
  List<Obligation> obligations = const [],
  String? payFromAccountId,
}) {
  if (amount <= 0) {
    return PaymentPlan(
      amount: amount,
      isPossible: false,
      sources: const [],
      transfers: const [],
      headline: 'Enter an amount to see where it should come from.',
      reasoning: const [],
      impact: _impact(snapshot, 0),
    );
  }

  if (payFromAccountId != null) {
    return _planForcedSource(
      amount: amount,
      snapshot: snapshot,
      obligations: obligations,
      accountId: payFromAccountId,
    );
  }

  final candidates =
      rankSources(snapshot: snapshot, amount: amount, obligations: obligations);

  // Prefer one account that can cover it outright, at the least harmful level
  // available. Splitting money across accounts is a hassle; only do it if a
  // single source genuinely cannot manage.
  for (final quality in [
    SourceQuality.clean,
    SourceQuality.dipsIntoBills,
    SourceQuality.breaksFloor,
  ]) {
    final pick = candidates
        .where((c) => c.quality == quality && _isUsable(c.account))
        .firstOrNull;
    if (pick == null) continue;

    final source = PaymentSource(
      account: pick.account,
      amount: amount,
      quality: quality,
      caution: pick.caution,
    );

    return PaymentPlan(
      amount: amount,
      isPossible: true,
      sources: [source],
      transfers: const [],
      headline: 'Take ${formatMoney(amount)} from ${pick.account.name}',
      reasoning: _rejections(candidates, [pick.account.id], obligations, snapshot),
      impact: _impact(snapshot, amount),
    );
  }

  // No single account manages it — combine, still worst-harm-last.
  final split = _splitAcross(candidates, amount);
  if (split.isNotEmpty) {
    final names = split.map((s) => s.account.name).join(' and ');
    return PaymentPlan(
      amount: amount,
      isPossible: true,
      sources: split,
      transfers: const [],
      headline: 'Split ${formatMoney(amount)} across $names',
      reasoning: _rejections(
        candidates,
        split.map((s) => s.account.id).toList(),
        obligations,
        snapshot,
      ),
      impact: _impact(snapshot, amount),
    );
  }

  final total = candidates
      .where((c) => _isUsable(c.account))
      .fold<double>(0, (s, c) => s + c.everything);

  return PaymentPlan(
    amount: amount,
    isPossible: false,
    sources: const [],
    transfers: const [],
    headline: 'You do not have ${formatMoney(amount)} to send',
    reasoning: [
      'Your spendable accounts hold ${formatMoney(total)} in total.',
      if (snapshot.locked > 0)
        'A further ${formatMoney(snapshot.locked)} is locked away and was not counted.',
    ],
    impact: _impact(snapshot, amount),
  );
}

/// The payment must leave [accountId]; work out whether it needs topping up.
PaymentPlan _planForcedSource({
  required double amount,
  required MoneySnapshot snapshot,
  required List<Obligation> obligations,
  required String accountId,
}) {
  final target = snapshot.standings
      .where((s) => s.account.id == accountId)
      .firstOrNull;

  if (target == null) {
    return PaymentPlan(
      amount: amount,
      isPossible: false,
      sources: const [],
      transfers: const [],
      headline: 'That account is no longer available.',
      reasoning: const [],
      impact: _impact(snapshot, amount),
    );
  }

  final account = target.account;
  final quality = _qualityFor(target, amount);

  // It can already cover it — nothing to move.
  if (quality != SourceQuality.insufficient) {
    return PaymentPlan(
      amount: amount,
      isPossible: true,
      sources: [
        PaymentSource(
          account: account,
          amount: amount,
          quality: quality,
          caution: _cautionFor(target, quality, obligations, snapshot),
        ),
      ],
      transfers: const [],
      headline: '${account.name} can cover ${formatMoney(amount)}',
      reasoning: quality == SourceQuality.clean
          ? const []
          : [_forcedCaution(quality, account)],
      impact: _impact(snapshot, amount),
    );
  }

  // Needs a top-up. Find it the same way we would find any source.
  final gap = amount - account.balance;
  final helpers = rankSources(
    snapshot: snapshot,
    amount: gap,
    obligations: obligations,
    excludeAccountId: accountId,
  );

  final transfers = <PaymentTransfer>[];
  var outstanding = gap;

  for (final quality in [
    SourceQuality.clean,
    SourceQuality.dipsIntoBills,
    SourceQuality.breaksFloor,
  ]) {
    for (final c in helpers) {
      if (outstanding <= 0.005) break;
      if (!_isUsable(c.account)) continue;
      if (transfers.any((t) => t.from.id == c.account.id)) continue;

      final capacity = c.capacityFor(quality);
      if (capacity <= 0.005) continue;

      final take = capacity < outstanding ? capacity : outstanding;
      transfers.add(
          PaymentTransfer(from: c.account, to: account, amount: take));
      outstanding -= take;
    }
    if (outstanding <= 0.005) break;
  }

  if (outstanding > 0.005) {
    return PaymentPlan(
      amount: amount,
      isPossible: false,
      sources: const [],
      transfers: const [],
      headline:
          'Even after moving everything, ${account.name} would be ${formatMoney(outstanding)} short',
      reasoning: _rejections(helpers, const [], obligations, snapshot),
      impact: _impact(snapshot, amount),
    );
  }

  final moved = transfers
      .map((t) => '${formatMoney(t.amount)} from ${t.from.name}')
      .join(', then ');

  return PaymentPlan(
    amount: amount,
    isPossible: true,
    sources: [
      PaymentSource(
        account: account,
        amount: amount,
        quality: SourceQuality.clean,
        caution: null,
      ),
    ],
    transfers: transfers,
    headline: 'Move $moved into ${account.name} first',
    reasoning: [
      '${account.name} holds ${formatMoney(account.balance)}, so it is '
          '${formatMoney(gap)} short of ${formatMoney(amount)}.',
      ..._rejections(
        helpers,
        transfers.map((t) => t.from.id).toList(),
        obligations,
        snapshot,
      ),
    ],
    impact: _impact(snapshot, amount),
  );
}

/// Greedily combines accounts, taking the least harmful money first.
List<PaymentSource> _splitAcross(
  List<PaymentCandidate> candidates,
  double amount,
) {
  final taken = <String, PaymentSource>{};
  var outstanding = amount;

  for (final quality in [
    SourceQuality.clean,
    SourceQuality.dipsIntoBills,
    SourceQuality.breaksFloor,
  ]) {
    for (final c in candidates) {
      if (outstanding <= 0.005) break;
      if (!_isUsable(c.account)) continue;

      final already = taken[c.account.id]?.amount ?? 0;
      final capacity = c.capacityFor(quality) - already;
      if (capacity <= 0.005) continue;

      final take = capacity < outstanding ? capacity : outstanding;
      taken[c.account.id] = PaymentSource(
        account: c.account,
        amount: already + take,
        quality: quality,
        caution: c.caution,
      );
      outstanding -= take;
    }
    if (outstanding <= 0.005) break;
  }

  if (outstanding > 0.005) return const [];
  return taken.values.toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
}

SourceQuality _qualityFor(AccountStanding standing, double amount) {
  if (standing.freeToMove >= amount) return SourceQuality.clean;
  if (standing.available >= amount) return SourceQuality.dipsIntoBills;
  if (standing.account.balance >= amount) return SourceQuality.breaksFloor;
  return SourceQuality.insufficient;
}

String? _cautionFor(
  AccountStanding standing,
  SourceQuality quality,
  List<Obligation> obligations,
  MoneySnapshot snapshot,
) {
  final a = standing.account;

  if (a.liquidity == Liquidity.locked) {
    return '${a.name} is locked away for the long term.';
  }
  if (a.liquidity == Liquidity.reserved) {
    return '${a.name} is money you set aside'
        '${a.purpose == null ? '' : ' — ${a.purpose}'}.';
  }

  return switch (quality) {
    SourceQuality.clean => null,
    SourceQuality.dipsIntoBills =>
      'This eats into ${_billNames(a.id, obligations, snapshot)}.',
    SourceQuality.breaksFloor =>
      'This takes ${a.name} below the ${formatMoney(a.minBalance)} you asked to keep.',
    SourceQuality.insufficient =>
      '${a.name} only holds ${formatMoney(a.balance)}.',
  };
}

String _forcedCaution(SourceQuality quality, Account account) =>
    switch (quality) {
      SourceQuality.dipsIntoBills =>
        'Careful — this uses money already earmarked for a bill on ${account.name}.',
      SourceQuality.breaksFloor =>
        'This takes ${account.name} below the ${formatMoney(account.minBalance)} floor you set.',
      _ => '',
    };

/// Names the bills pinned to an account, so a warning says *which* bill.
String _billNames(
  String accountId,
  List<Obligation> obligations,
  MoneySnapshot snapshot,
) {
  final pinned = obligations
      .where((o) =>
          o.isActive && o.isOutflow && o.accountId == accountId)
      .where((o) {
        final due = o.nextOccurrenceOnOrAfter(snapshot.asOf);
        return due != null && !due.isAfter(snapshot.horizon);
      })
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  if (pinned.isEmpty) return 'money already committed here';

  final top = pinned.first;
  final due = top.nextOccurrenceOnOrAfter(snapshot.asOf);
  final extra = pinned.length > 1 ? ' and ${pinned.length - 1} more' : '';
  return '${top.name} (${formatMoney(top.amount)}'
      '${due == null ? '' : ', due ${dateLongFmt.format(due)}'})$extra';
}

/// Plain-language reasons the other accounts were left alone.
List<String> _rejections(
  List<PaymentCandidate> candidates,
  List<String> chosenIds,
  List<Obligation> obligations,
  MoneySnapshot snapshot,
) {
  final out = <String>[];

  for (final c in candidates) {
    if (chosenIds.contains(c.account.id)) continue;
    final caution = c.caution;
    if (caution == null) continue;
    out.add('Not ${c.account.name} — ${_lowerFirst(caution)}');
  }

  return out.take(4).toList();
}

PaymentImpact _impact(MoneySnapshot snapshot, double amount) {
  final usableAfter = snapshot.usableCash - amount;
  return PaymentImpact(
    safeToSpendAfter: snapshot.safeToSpend - amount,
    runwayDaysAfter: snapshot.dailyBurn <= 0
        ? null
        : (usableAfter <= 0 ? 0.0 : usableAfter / snapshot.dailyBurn),
    daysUntilIncome: snapshot.daysUntilIncome,
  );
}

/// Locked money is never offered automatically. The user can still choose it
/// deliberately, but the app will not suggest raiding it.
bool _isUsable(Account a) => !a.isArchived && a.liquidity != Liquidity.locked;

int _liquidityRank(Account a) => switch (a.liquidity) {
      Liquidity.liquid => 0,
      Liquidity.reserved => 1,
      Liquidity.locked => 2,
    };

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

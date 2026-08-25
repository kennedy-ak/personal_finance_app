import '../../../core/finance/alerts.dart';
import '../../../core/finance/money_engine.dart';
import '../../../core/finance/payment_planner.dart';
import '../../../core/formatters.dart';
import '../../accounts/domain/account.dart';
import '../../planning/domain/goal.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/coach_action.dart';

/// What the coach is allowed to do.
///
/// Reading tools run straight against the money engine, so every number the
/// model quotes was computed and tested rather than produced by a language
/// model doing mental arithmetic. The two writing tools do not write: they
/// return a proposal that the user has to tap before anything happens.

/// The result of running one tool: text handed back to the model, plus any
/// action the user is being offered.
class ToolResult {
  final String content;
  final CoachAction? action;

  const ToolResult(this.content, {this.action});
}

/// Everything the tools need in order to answer. Assembled once per turn.
class CoachContext {
  final MoneySnapshot snapshot;
  final List<Account> accounts;
  final List<Txn> txns;
  final List<Obligation> obligations;
  final List<Goal> goals;

  const CoachContext({
    required this.snapshot,
    required this.accounts,
    required this.txns,
    required this.obligations,
    required this.goals,
  });

  /// Resolves whatever the user or the model called an account.
  ///
  /// People do not type account names exactly. In Ghana "Mobile Money" is
  /// universally "Momo", and a coach that replies "there is no account called
  /// Momo" is useless. Matching goes exact, then substring, then run-together
  /// word prefixes.
  Account? accountByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;

    for (final a in accounts) {
      if (a.name.toLowerCase() == needle) return a;
    }

    for (final a in accounts) {
      final candidate = a.name.toLowerCase();
      if (candidate.contains(needle) || needle.contains(candidate)) return a;
    }

    for (final a in accounts) {
      final candidate = a.name.toLowerCase();
      if (_wordPrefixMatch(needle, candidate) ||
          _wordPrefixMatch(candidate, needle)) {
        return a;
      }
    }
    return null;
  }
}

/// Tool definitions in OpenAI function-calling shape.
const List<Map<String, dynamic>> kCoachTools = [
  {
    'type': 'function',
    'function': {
      'name': 'get_position',
      'description':
          'The user\'s current money position: total balance, what is spendable '
              'versus reserved or locked, bills already committed, safe-to-spend, '
              'daily spending rate, days of cash left and days until income. '
              'Call this before answering anything about affordability.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_alerts',
      'description':
          'Problems the app has already detected — running short before payday, '
              'accounts below their floor, bills an account cannot cover, spending '
              'spikes. These are computed, not guessed.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'list_accounts',
      'description':
          'Every account with its balance, kind, whether it is spendable, its '
              'minimum balance, what it is for, and how much is genuinely free to '
              'move out of it.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'list_commitments',
      'description':
          'Recurring bills, expected income, and savings goals, with when each '
              'next lands.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'plan_payment',
      'description':
          'Work out which account a payment should come from. Returns the '
              'recommendation, why every other account was rejected, any transfers '
              'needed first, and what the payment leaves behind. Always use this '
              'rather than reasoning about accounts yourself.',
      'parameters': {
        'type': 'object',
        'properties': {
          'amount': {
            'type': 'number',
            'description': 'Amount to pay, in GHS.',
          },
          'must_leave_account': {
            'type': 'string',
            'description':
                'Optional account name the money has to physically leave from, '
                    'for example when sending over mobile money.',
          },
        },
        'required': ['amount'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_spending',
      'description':
          'Spending by category over a window, with how each category moved '
              'against the previous window of the same length.',
      'parameters': {
        'type': 'object',
        'properties': {
          'days': {
            'type': 'integer',
            'description': 'Window length in days. Defaults to 30.',
          },
        },
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'list_transactions',
      'description':
          'Recent individual transactions, most recent first. Use when the user '
              'asks about specific spending rather than totals.',
      'parameters': {
        'type': 'object',
        'properties': {
          'days': {'type': 'integer', 'description': 'How far back. Default 30.'},
          'category': {
            'type': 'string',
            'description': 'Optional category filter.',
          },
          'limit': {'type': 'integer', 'description': 'Max rows. Default 20.'},
        },
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'propose_transfer',
      'description':
          'Offer the user a transfer between their own accounts. This does NOT '
              'move any money — it shows them a card they can approve. Use it '
              'whenever the right answer is "move money from here to there".',
      'parameters': {
        'type': 'object',
        'properties': {
          'from_account': {'type': 'string'},
          'to_account': {'type': 'string'},
          'amount': {'type': 'number'},
          'reason': {
            'type': 'string',
            'description': 'One short sentence on why, shown on the card.',
          },
        },
        'required': ['from_account', 'to_account', 'amount', 'reason'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'propose_commitment',
      'description':
          'Offer to record a recurring bill or expected income the user has '
              'mentioned but never logged. Does NOT save anything — the user has '
              'to approve the card.',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'amount': {'type': 'number'},
          'direction': {
            'type': 'string',
            'enum': ['bill', 'income'],
          },
          'cadence': {
            'type': 'string',
            'enum': ['once', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'],
          },
          'next_due': {
            'type': 'string',
            'description': 'Date it next lands, as YYYY-MM-DD.',
          },
          'account': {
            'type': 'string',
            'description': 'Optional account it is paid from or arrives into.',
          },
        },
        'required': ['name', 'amount', 'direction', 'cadence', 'next_due'],
      },
    },
  },
];

/// Runs one tool call and returns what the model should see.
///
/// Never throws: a tool that fails hands back an explanation, so the model can
/// recover in the same turn instead of the whole conversation dying.
ToolResult runCoachTool({
  required String name,
  required Map<String, dynamic> args,
  required CoachContext context,
}) {
  try {
    return switch (name) {
      'get_position' => _getPosition(context),
      'get_alerts' => _getAlerts(context),
      'list_accounts' => _listAccounts(context),
      'list_commitments' => _listCommitments(context),
      'plan_payment' => _planPayment(args, context),
      'get_spending' => _getSpending(args, context),
      'list_transactions' => _listTransactions(args, context),
      'propose_transfer' => _proposeTransfer(args, context),
      'propose_commitment' => _proposeCommitment(args, context),
      _ => ToolResult('There is no tool called "$name".'),
    };
  } catch (e) {
    return ToolResult('That tool failed: $e');
  }
}

ToolResult _getPosition(CoachContext c) {
  final s = c.snapshot;
  final lines = <String>[
    'Currency: GHS. Today: ${dateLongFmt.format(s.asOf)}.',
    'Total balance: ${formatMoney(s.totalBalance)}.',
    'Spendable accounts hold ${formatMoney(s.liquid)}; '
        '${formatMoney(s.reserved)} is reserved and ${formatMoney(s.locked)} is locked.',
    'Minimum balances held back: ${formatMoney(s.floors)}. '
        'Held for goals: ${formatMoney(s.goalReserve)}.',
    'Bills due before ${dateLongFmt.format(s.horizon)}: ${formatMoney(s.committed)}.',
    'SAFE TO SPEND: ${formatMoney(s.safeToSpend)}.',
    'Average spending: ${formatMoney(s.dailyBurn)} per day.',
    if (s.runwayDays != null)
      'Cash lasts about ${s.runwayDays!.floor()} days at that rate.',
    if (s.daysUntilIncome != null)
      'Next income arrives in ${s.daysUntilIncome} days.'
    else
      'No expected income is recorded, so runway cannot be judged against payday.',
    if (s.willFallShort)
      'WARNING: money runs out ${s.shortfallDays} days before income arrives.',
    'Last 30 days: ${formatMoney(s.income30d)} in, ${formatMoney(s.spend30d)} out '
        '(transfers between own accounts excluded).',
  ];
  return ToolResult(lines.join('\n'));
}

ToolResult _getAlerts(CoachContext c) {
  final alerts = buildAlerts(
    snapshot: c.snapshot,
    obligations: c.obligations,
    goals: c.goals,
  );
  if (alerts.isEmpty) {
    return const ToolResult('No problems detected right now.');
  }
  return ToolResult(alerts
      .map((a) => '[${a.severity.name.toUpperCase()}] ${a.title} — ${a.detail}')
      .join('\n'));
}

ToolResult _listAccounts(CoachContext c) {
  if (c.snapshot.standings.isEmpty) {
    return const ToolResult('The user has no accounts set up.');
  }
  final lines = c.snapshot.standings.map((st) {
    final a = st.account;
    return [
      a.name,
      '${a.kind.label}, ${a.liquidity.label.toLowerCase()}',
      'balance ${formatMoney(a.balance)}',
      if (a.minBalance > 0) 'must keep ${formatMoney(a.minBalance)}',
      if (st.committed > 0) 'bills pinned here ${formatMoney(st.committed)}',
      'free to move ${formatMoney(st.freeToMove)}',
      if (a.purpose != null && a.purpose!.isNotEmpty) 'purpose: ${a.purpose}',
      if (st.isBelowFloor) 'WARNING: below its minimum balance',
    ].join(' · ');
  });
  return ToolResult(lines.join('\n'));
}

ToolResult _listCommitments(CoachContext c) {
  final out = <String>[];

  for (final o in c.obligations.where((o) => o.isActive)) {
    final next = o.nextOccurrenceOnOrAfter(c.snapshot.asOf);
    out.add([
      o.isOutflow ? 'BILL' : 'INCOME',
      o.name,
      formatMoney(o.amount),
      o.cadence.label.toLowerCase(),
      if (next != null) 'next ${dateLongFmt.format(next)}',
    ].join(' · '));
  }

  for (final g in c.goals.where((g) => g.isActive)) {
    out.add('GOAL · ${g.name} · ${formatMoney(g.savedAmount)} saved of '
        '${formatMoney(g.targetAmount)}'
        '${g.targetDate == null ? '' : ' · by ${dateLongFmt.format(g.targetDate!)}'}');
  }

  if (out.isEmpty) {
    return const ToolResult(
        'Nothing recorded. The user has not told the app about any bills, '
        'income or goals — say so, because it limits what can be worked out.');
  }
  return ToolResult(out.join('\n'));
}

ToolResult _planPayment(Map<String, dynamic> args, CoachContext c) {
  final amount = _toDouble(args['amount']);
  if (amount == null || amount <= 0) {
    return const ToolResult('Need a positive amount to plan a payment.');
  }

  String? forcedId;
  final forcedName = args['must_leave_account'] as String?;
  if (forcedName != null && forcedName.trim().isNotEmpty) {
    final match = c.accountByName(forcedName);
    if (match == null) {
      return ToolResult(
          'There is no account called "$forcedName". Accounts are: '
          '${c.accounts.map((a) => a.name).join(', ')}.');
    }
    forcedId = match.id;
  }

  final plan = planPayment(
    amount: amount,
    snapshot: c.snapshot,
    obligations: c.obligations,
    payFromAccountId: forcedId,
  );

  final lines = <String>[
    plan.headline,
    if (!plan.isPossible) 'This payment is not currently possible.',
    for (final t in plan.transfers)
      'Transfer first: ${formatMoney(t.amount)} from ${t.from.name} to ${t.to.name}.',
    for (final s in plan.sources)
      'Take ${formatMoney(s.amount)} from ${s.account.name}'
          '${s.caution == null ? '' : ' — ${s.caution}'}',
    ...plan.reasoning,
    if (plan.isPossible)
      'After this: ${formatMoney(plan.impact.safeToSpendAfter)} spendable'
          '${plan.impact.runwayDaysAfter == null ? '' : ', about ${plan.impact.runwayDaysAfter!.floor()} days of cash'}'
          '${plan.impact.causesShortfall ? '. WARNING: this causes a shortfall before income arrives.' : '.'}',
  ];

  return ToolResult(lines.join('\n'));
}

ToolResult _getSpending(Map<String, dynamic> args, CoachContext c) {
  final days = _toInt(args['days']) ?? 30;
  final asOf = c.snapshot.asOf;
  final start = asOf.subtract(Duration(days: days));
  final prevStart = asOf.subtract(Duration(days: days * 2));

  final current = <String, double>{};
  final previous = <String, double>{};

  for (final t in c.txns) {
    if (!t.isSpending) continue;
    if (!t.date.isBefore(start) && !t.date.isAfter(asOf)) {
      current[t.category] = (current[t.category] ?? 0) + t.amount;
    } else if (!t.date.isBefore(prevStart) && t.date.isBefore(start)) {
      previous[t.category] = (previous[t.category] ?? 0) + t.amount;
    }
  }

  if (current.isEmpty) {
    return ToolResult('No spending recorded in the last $days days.');
  }

  final entries = current.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = current.values.fold<double>(0, (s, v) => s + v);

  final lines = <String>['Total spending over $days days: ${formatMoney(total)}.'];
  for (final e in entries) {
    final before = previous[e.key] ?? 0;
    final change = before <= 0
        ? 'no comparison available'
        : '${((e.value - before) / before * 100).round()}% versus ${formatMoney(before)} the $days days before';
    lines.add('${e.key}: ${formatMoney(e.value)} ($change)');
  }
  return ToolResult(lines.join('\n'));
}

ToolResult _listTransactions(Map<String, dynamic> args, CoachContext c) {
  final days = _toInt(args['days']) ?? 30;
  final limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
  final category = (args['category'] as String?)?.trim().toLowerCase();
  final start = c.snapshot.asOf.subtract(Duration(days: days));
  final names = {for (final a in c.accounts) a.id: a.name};

  final rows = c.txns
      .where((t) => t.isRealMoneyMovement)
      .where((t) => !t.date.isBefore(start))
      .where((t) =>
          category == null || t.category.toLowerCase().contains(category))
      .take(limit)
      .map((t) => '${dateFmt.format(t.date)} · ${t.type.label} · '
          '${formatMoney(t.amount)} · ${t.category} · '
          '${names[t.accountId] ?? 'unknown account'}'
          '${t.description == null || t.description!.isEmpty ? '' : ' · ${t.description}'}')
      .toList();

  if (rows.isEmpty) {
    return ToolResult('No matching transactions in the last $days days.');
  }
  return ToolResult(rows.join('\n'));
}

ToolResult _proposeTransfer(Map<String, dynamic> args, CoachContext c) {
  final amount = _toDouble(args['amount']);
  if (amount == null || amount <= 0) {
    return const ToolResult('A transfer needs a positive amount.');
  }

  final from = c.accountByName((args['from_account'] as String?) ?? '');
  final to = c.accountByName((args['to_account'] as String?) ?? '');
  final known = c.accounts.map((a) => a.name).join(', ');

  if (from == null) {
    return ToolResult('No account matches "${args['from_account']}". '
        'Accounts are: $known.');
  }
  if (to == null) {
    return ToolResult('No account matches "${args['to_account']}". '
        'Accounts are: $known.');
  }
  if (from.id == to.id) {
    return const ToolResult('A transfer needs two different accounts.');
  }
  if (from.balance < amount) {
    return ToolResult('${from.name} only holds ${formatMoney(from.balance)}, '
        'so it cannot send ${formatMoney(amount)}.');
  }

  final reason = (args['reason'] as String?)?.trim();

  return ToolResult(
    'Offered the user a transfer of ${formatMoney(amount)} from ${from.name} '
    'to ${to.name}. It has NOT happened — they must approve it. Tell them '
    'briefly what it does; do not claim it is done.',
    action: TransferAction(
      fromAccountId: from.id,
      fromAccountName: from.name,
      toAccountId: to.id,
      toAccountName: to.name,
      amount: amount,
      reason: reason == null || reason.isEmpty ? 'Suggested by your coach' : reason,
    ),
  );
}

ToolResult _proposeCommitment(Map<String, dynamic> args, CoachContext c) {
  final amount = _toDouble(args['amount']);
  if (amount == null || amount <= 0) {
    return const ToolResult('A commitment needs a positive amount.');
  }

  final name = (args['name'] as String?)?.trim();
  if (name == null || name.isEmpty) {
    return const ToolResult('A commitment needs a name.');
  }

  final rawDate = (args['next_due'] as String?)?.trim();
  final nextDue = rawDate == null ? null : DateTime.tryParse(rawDate);
  if (nextDue == null) {
    return const ToolResult('next_due must be a date like 2026-08-01.');
  }

  final direction = (args['direction'] as String?) == 'income'
      ? ObligationDirection.incoming
      : ObligationDirection.out;

  final cadence = Cadence.fromValue((args['cadence'] as String?) ?? 'monthly');

  Account? account;
  final accountName = (args['account'] as String?)?.trim();
  if (accountName != null && accountName.isNotEmpty) {
    account = c.accountByName(accountName);
  }

  return ToolResult(
    'Offered the user a ${direction == ObligationDirection.out ? 'bill' : 'income'} '
    'record: $name, ${formatMoney(amount)}, ${cadence.label.toLowerCase()}, next '
    '${dateLongFmt.format(nextDue)}. It has NOT been saved — they must approve it.',
    action: CommitmentAction(
      name: name,
      amount: amount,
      direction: direction,
      cadence: cadence,
      nextDue: nextDue,
      accountId: account?.id,
      accountName: account?.name,
    ),
  );
}

/// Whether [needle] is [name]'s words run together by their prefixes —
/// "momo" for "mobile money", "accbank" for "Access Bank".
///
/// Every word must contribute at least two matched characters and the needle
/// must be fully consumed, so a stray letter cannot match an unrelated account.
bool _wordPrefixMatch(String needle, String name) {
  if (needle.length < 3) return false;

  final words = name
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length < 2) return false;

  var rest = needle;
  for (final word in words) {
    var taken = 0;
    while (taken < word.length && taken < rest.length && rest[taken] == word[taken]) {
      taken++;
    }
    if (taken < 2) return false;
    rest = rest.substring(taken);
  }
  return rest.isEmpty;
}

double? _toDouble(Object? v) => switch (v) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

int? _toInt(Object? v) => switch (v) {
      final num n => n.toInt(),
      final String s => int.tryParse(s),
      _ => null,
    };

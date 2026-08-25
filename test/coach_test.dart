import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/finance/money_engine.dart';
import 'package:personal_finance_app/features/accounts/domain/account.dart';
import 'package:personal_finance_app/features/insights/data/coach_service.dart';
import 'package:personal_finance_app/features/insights/data/coach_tools.dart';
import 'package:personal_finance_app/features/insights/data/coach_transport.dart';
import 'package:personal_finance_app/features/insights/domain/coach_action.dart';
import 'package:personal_finance_app/features/insights/domain/coach_message.dart';
import 'package:personal_finance_app/features/planning/domain/goal.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';
import 'package:personal_finance_app/features/transactions/domain/transaction.dart';

import 'support/fixtures.dart';

final salary = obl(
  name: 'Salary',
  amount: 4000,
  nextDue: DateTime(2026, 7, 31),
  direction: ObligationDirection.incoming,
);

final rent = obl(
  name: 'Rent',
  amount: 1200,
  nextDue: DateTime(2026, 7, 28),
  accountId: 'momo',
);

/// Builds a thread the way saveTurn writes one: a question, the assistant turn
/// that asked for tools, one row per result, then the spoken answer.
List<CoachMessage> toolTurn(String question, String answer, {String id = 'a'}) => [
      CoachMessage(
        id: '${id}1',
        threadId: 't',
        role: CoachRole.user,
        content: question,
        createdAt: DateTime(2026, 7, 14),
      ),
      CoachMessage(
        id: '${id}2',
        threadId: 't',
        role: CoachRole.assistant,
        content: null,
        toolCalls: [
          {
            'id': 'call_$id',
            'type': 'function',
            'function': {'name': 'get_position', 'arguments': '{}'},
          },
        ],
        createdAt: DateTime(2026, 7, 14),
      ),
      CoachMessage(
        id: '${id}3',
        threadId: 't',
        role: CoachRole.tool,
        content: 'Spendable: GHS 2,350.00',
        toolCallId: 'call_$id',
        name: 'get_position',
        createdAt: DateTime(2026, 7, 14),
      ),
      CoachMessage(
        id: '${id}4',
        threadId: 't',
        role: CoachRole.assistant,
        content: answer,
        createdAt: DateTime(2026, 7, 14),
      ),
    ];

/// Every tool row must sit directly behind an assistant turn that asked for it.
/// This is the rule the provider enforces, restated so a test can check it.
void expectWireIsValid(List<Map<String, dynamic>> wire) {
  final open = <String>{};
  for (final m in wire) {
    if (m['role'] == 'assistant') {
      open
        ..clear()
        ..addAll([
          for (final c in (m['tool_calls'] as List? ?? const []))
            (c as Map)['id'] as String,
        ]);
    } else if (m['role'] == 'tool') {
      expect(
        open,
        contains(m['tool_call_id']),
        reason: 'orphaned tool result: ${m['tool_call_id']}',
      );
    } else {
      open.clear();
    }
  }
}

CoachContext contextWith({
  List<Account>? accounts,
  List<Txn>? txns,
  List<Obligation> obligations = const [],
  List<Goal> goals = const [],
}) {
  final accs = accounts ??
      [
        acc('fid', 'Fidelity', 3000),
        acc('momo', 'Mobile Money', 450, kind: AccountKind.momo),
        acc('cash', 'Cash', 400, kind: AccountKind.cash, minBalance: 300),
      ];
  final transactions = txns ?? steadySpending('fid');

  return CoachContext(
    snapshot: buildSnapshot(
      accounts: accs,
      txns: transactions,
      obligations: obligations,
      goals: goals,
      now: now,
    ),
    accounts: accs,
    txns: transactions,
    obligations: obligations,
    goals: goals,
  );
}

/// Replays a scripted set of provider responses, and records what it was sent.
class FakeTransport implements CoachTransport {
  final List<Map<String, dynamic>> responses;
  final List<List<Map<String, dynamic>>> sent = [];
  final List<List<Map<String, dynamic>>?> toolsSeen = [];
  int _index = 0;

  FakeTransport(this.responses);

  @override
  String get label => 'fake';

  @override
  Future<Map<String, dynamic>> complete({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async {
    sent.add(List.of(messages));
    toolsSeen.add(tools);
    if (_index >= responses.length) {
      throw CoachException('FakeTransport ran out of scripted responses.');
    }
    return responses[_index++];
  }
}

Map<String, dynamic> saysText(String text) => {'content': text};

Map<String, dynamic> callsTool(
  String name,
  Map<String, dynamic> args, {
  String id = 'call_1',
}) =>
    {
      'content': null,
      'tool_calls': [
        {
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': jsonEncode(args)},
        },
      ],
    };

void main() {
  group('reading tools', () {
    test('get_position reports the computed figures, not guesses', () {
      final result = runCoachTool(
        name: 'get_position',
        args: const {},
        context: contextWith(obligations: [salary, rent]),
      );

      expect(result.content, contains('SAFE TO SPEND: GHS 2,350.00'));
      expect(result.content, contains('Next income arrives in 16 days'));
      expect(result.content, contains('GHS 50.00 per day'));
    });

    test('get_position flags a missing income date rather than inventing one', () {
      final result = runCoachTool(
        name: 'get_position',
        args: const {},
        context: contextWith(),
      );

      expect(result.content, contains('No expected income is recorded'));
    });

    test('list_accounts exposes floors, pinned bills and free money', () {
      final result = runCoachTool(
        name: 'list_accounts',
        args: const {},
        context: contextWith(obligations: [salary, rent]),
      );

      expect(result.content, contains('Cash'));
      expect(result.content, contains('must keep GHS 300.00'));
      expect(result.content, contains('bills pinned here GHS 1,200.00'));
    });

    test('list_commitments admits when nothing is recorded', () {
      final result = runCoachTool(
        name: 'list_commitments',
        args: const {},
        context: contextWith(),
      );

      expect(result.content, contains('Nothing recorded'));
    });

    test('plan_payment defers to the planner and names the account', () {
      final result = runCoachTool(
        name: 'plan_payment',
        args: const {'amount': 800},
        context: contextWith(obligations: [salary, rent]),
      );

      expect(result.content, contains('Take GHS 800.00 from Fidelity'));
      expect(result.content, contains('Not Mobile Money'));
    });

    test('plan_payment handles a forced source', () {
      final result = runCoachTool(
        name: 'plan_payment',
        args: const {'amount': 1000, 'must_leave_account': 'Momo'},
        context: contextWith(obligations: [salary]),
      );

      // "Momo" resolves to "Mobile Money" by partial match.
      expect(result.content, contains('Mobile Money'));
      expect(result.content, contains('Transfer first'));
    });

    test('an unknown account is reported, not silently ignored', () {
      final result = runCoachTool(
        name: 'plan_payment',
        args: const {'amount': 500, 'must_leave_account': 'Barclays'},
        context: contextWith(),
      );

      expect(result.content, contains('no account called "Barclays"'));
      expect(result.content, contains('Fidelity'));
    });

    test('get_spending excludes transfers between the user\'s own accounts', () {
      final result = runCoachTool(
        name: 'get_spending',
        args: const {'days': 30},
        context: contextWith(
          txns: [
            txn(account: 'fid', type: TxnType.expense, amount: 400, date: now.subtract(const Duration(days: 3))),
            txn(
              account: 'fid',
              to: 'momo',
              type: TxnType.transfer,
              amount: 2000,
              category: 'Transfer',
              date: now.subtract(const Duration(days: 2)),
            ),
          ],
        ),
      );

      expect(result.content, contains('GHS 400.00'));
      expect(result.content, isNot(contains('2,000')));
    });

    test('an unknown tool name is reported rather than throwing', () {
      final result = runCoachTool(
        name: 'delete_everything',
        args: const {},
        context: contextWith(),
      );

      expect(result.content, contains('no tool called'));
    });
  });

  group('proposing actions', () {
    test('propose_transfer returns a card and insists nothing happened', () {
      final result = runCoachTool(
        name: 'propose_transfer',
        args: const {
          'from_account': 'Fidelity',
          'to_account': 'Mobile Money',
          'amount': 750,
          'reason': 'Rent leaves Momo on the 28th',
        },
        context: contextWith(obligations: [salary, rent]),
      );

      final action = result.action;
      expect(action, isA<TransferAction>());
      final transfer = action as TransferAction;
      expect(transfer.fromAccountName, 'Fidelity');
      expect(transfer.toAccountName, 'Mobile Money');
      expect(transfer.amount, 750);
      expect(result.content, contains('has NOT happened'));
    });

    test('refuses a transfer the source cannot fund', () {
      final result = runCoachTool(
        name: 'propose_transfer',
        args: const {
          'from_account': 'Mobile Money',
          'to_account': 'Fidelity',
          'amount': 5000,
          'reason': 'because',
        },
        context: contextWith(),
      );

      expect(result.action, isNull);
      expect(result.content, contains('only holds GHS 450.00'));
    });

    test('refuses a transfer to the same account', () {
      final result = runCoachTool(
        name: 'propose_transfer',
        args: const {
          'from_account': 'Fidelity',
          'to_account': 'Fidelity',
          'amount': 100,
          'reason': 'because',
        },
        context: contextWith(),
      );

      expect(result.action, isNull);
      expect(result.content, contains('two different accounts'));
    });

    test('propose_commitment builds a record awaiting approval', () {
      final result = runCoachTool(
        name: 'propose_commitment',
        args: const {
          'name': 'Rent',
          'amount': 1200,
          'direction': 'bill',
          'cadence': 'monthly',
          'next_due': '2026-08-28',
          'account': 'Mobile Money',
        },
        context: contextWith(),
      );

      final action = result.action as CommitmentAction;
      expect(action.name, 'Rent');
      expect(action.amount, 1200);
      expect(action.direction, ObligationDirection.out);
      expect(action.cadence, Cadence.monthly);
      expect(action.accountName, 'Mobile Money');
      expect(result.content, contains('has NOT been saved'));
    });

    test('rejects a commitment with an unusable date', () {
      final result = runCoachTool(
        name: 'propose_commitment',
        args: const {
          'name': 'Rent',
          'amount': 1200,
          'direction': 'bill',
          'cadence': 'monthly',
          'next_due': 'next month sometime',
        },
        context: contextWith(),
      );

      expect(result.action, isNull);
      expect(result.content, contains('must be a date'));
    });
  });

  group('actions survive a round trip through storage', () {
    test('a transfer keeps every field', () {
      const original = TransferAction(
        fromAccountId: 'fid',
        fromAccountName: 'Fidelity',
        toAccountId: 'momo',
        toAccountName: 'Mobile Money',
        amount: 750,
        reason: 'Rent is due',
      );

      final revived = CoachAction.fromJson(original.toJson()) as TransferAction;

      expect(revived.fromAccountId, original.fromAccountId);
      expect(revived.toAccountName, original.toAccountName);
      expect(revived.amount, original.amount);
      expect(revived.reason, original.reason);
    });

    test('a commitment keeps every field', () {
      final original = CommitmentAction(
        name: 'Rent',
        amount: 1200,
        direction: ObligationDirection.out,
        cadence: Cadence.monthly,
        nextDue: DateTime(2026, 8, 28),
        accountId: 'momo',
        accountName: 'Mobile Money',
      );

      final revived =
          CoachAction.fromJson(original.toJson()) as CommitmentAction;

      expect(revived.name, 'Rent');
      expect(revived.cadence, Cadence.monthly);
      expect(revived.nextDue, DateTime(2026, 8, 28));
      expect(revived.accountId, 'momo');
    });
  });

  group('the agent loop', () {
    test('answers directly when no tool is needed', () async {
      final transport = FakeTransport([saysText('Budgeting is a habit.')]);

      final turn = await CoachService(transport: transport).send(
        question: 'Any general advice?',
        history: const [],
        context: contextWith(),
      );

      expect(turn.reply, 'Budgeting is a habit.');
      expect(turn.toolsUsed, isEmpty);
      expect(turn.actions, isEmpty);
    });

    test('runs a tool, feeds the result back, then answers', () async {
      final transport = FakeTransport([
        callsTool('get_position', {}),
        saysText('You have GHS 2,350.00 spendable.'),
      ]);

      final turn = await CoachService(transport: transport).send(
        question: 'How much can I spend?',
        history: const [],
        context: contextWith(obligations: [salary, rent]),
      );

      expect(turn.toolsUsed, ['get_position']);
      expect(turn.reply, contains('2,350.00'));

      // The second request must carry the tool result, or the model is
      // answering blind.
      final second = transport.sent[1];
      expect(second.last['role'], 'tool');
      expect(second.last['content'], contains('SAFE TO SPEND'));
    });

    test('chains tools across rounds', () async {
      final transport = FakeTransport([
        callsTool('get_position', {}, id: 'c1'),
        callsTool('plan_payment', {'amount': 800}, id: 'c2'),
        saysText('Take it from Fidelity.'),
      ]);

      final turn = await CoachService(transport: transport).send(
        question: 'I need to send 800',
        history: const [],
        context: contextWith(obligations: [salary, rent]),
      );

      expect(turn.toolsUsed, ['get_position', 'plan_payment']);
      expect(turn.reply, 'Take it from Fidelity.');
    });

    test('surfaces a proposed action to the user', () async {
      final transport = FakeTransport([
        callsTool('propose_transfer', {
          'from_account': 'Fidelity',
          'to_account': 'Mobile Money',
          'amount': 750,
          'reason': 'Rent leaves Momo on the 28th',
        }),
        saysText('Approve the move below.'),
      ]);

      final turn = await CoachService(transport: transport).send(
        question: 'Rent is due from Momo, sort it out',
        history: const [],
        context: contextWith(obligations: [salary, rent]),
      );

      expect(turn.actions, hasLength(1));
      expect((turn.actions.single as TransferAction).amount, 750);

      // The action rides on the final visible message, so it renders under the
      // reply rather than floating loose.
      final visible = turn.messages
          .where((m) => m.role == CoachRole.assistant && m.content != null)
          .last;
      expect(visible.actions, hasLength(1));
    });

    test('replays history so the coach remembers', () async {
      final transport = FakeTransport([saysText('Still Fidelity.')]);

      final history = [
        CoachMessage(
          id: '1',
          threadId: 't',
          role: CoachRole.user,
          content: 'Which account should I use?',
          createdAt: DateTime(2026, 7, 14),
        ),
        CoachMessage(
          id: '2',
          threadId: 't',
          role: CoachRole.assistant,
          content: 'Fidelity.',
          createdAt: DateTime(2026, 7, 14),
        ),
      ];

      await CoachService(transport: transport).send(
        question: 'And for a bigger amount?',
        history: history,
        context: contextWith(),
      );

      final wire = transport.sent.single;
      expect(wire.first['role'], 'system');
      expect(wire[1]['content'], 'Which account should I use?');
      expect(wire[2]['content'], 'Fidelity.');
      expect(wire.last['content'], 'And for a bigger amount?');
    });

    group('replaying a thread that used tools', () {
      test('a whole tool group survives the trip', () async {
        final transport = FakeTransport([saysText('Still fine.')]);

        await CoachService(transport: transport).send(
          question: 'And now?',
          history: toolTurn('How am I doing?', 'You have GHS 2,350.00.'),
          context: contextWith(),
        );

        final wire = transport.sent.single;
        expectWireIsValid(wire);
        expect(wire.map((m) => m['role']),
            ['system', 'user', 'assistant', 'tool', 'assistant', 'user']);
      });

      test('a tool result whose call was trimmed away is dropped', () async {
        // Exactly what the window used to hand over: a thread beginning on a
        // tool row. The provider rejects the entire request for this, so the
        // orphan has to go before it is ever sent.
        final transport = FakeTransport([saysText('Fine.')]);
        final orphaned = toolTurn('How am I doing?', 'All good.').sublist(2);

        await CoachService(transport: transport).send(
          question: 'And now?',
          history: orphaned,
          context: contextWith(),
        );

        final wire = transport.sent.single;
        expectWireIsValid(wire);
        expect(wire.any((m) => m['role'] == 'tool'), isFalse);
        // The prose the coach spoke is still there — only the bookkeeping went.
        expect(wire.any((m) => m['content'] == 'All good.'), isTrue);
      });

      test('a call that never got its result keeps the prose, drops the call',
          () async {
        final transport = FakeTransport([saysText('Fine.')]);
        final turn = toolTurn('How am I doing?', 'All good.');
        // The tool row is missing — a turn that failed to save completely.
        final broken = [turn[0], turn[1], turn[3]];

        await CoachService(transport: transport).send(
          question: 'And now?',
          history: broken,
          context: contextWith(),
        );

        final wire = transport.sent.single;
        expectWireIsValid(wire);
        expect(wire.any((m) => m.containsKey('tool_calls')), isFalse);
      });

      test('trimming a long thread never cuts a tool group in half', () async {
        final transport = FakeTransport([saysText('Fine.')]);

        // Comfortably past kHistoryWindow, so the trim definitely bites — and
        // with an odd row in between, so the cut cannot land on a turn
        // boundary by luck and pass for the wrong reason.
        final long = <CoachMessage>[];
        for (var i = 0; i < 12; i++) {
          long.addAll(toolTurn('Question $i', 'Answer $i', id: 'q$i'));
          if (i.isEven) {
            long.add(CoachMessage(
              id: 'plain$i',
              threadId: 't',
              role: CoachRole.assistant,
              content: 'Aside $i.',
              createdAt: DateTime(2026, 7, 14),
            ));
          }
        }
        expect(long.length, greaterThan(kHistoryWindow));

        await CoachService(transport: transport).send(
          question: 'And now?',
          history: long,
          context: contextWith(),
        );

        final wire = transport.sent.single;
        expectWireIsValid(wire);
        // Cut at a turn boundary: the first replayed row is a question.
        expect(wire[1]['role'], 'user');
        // And it stayed inside the budget.
        expect(wire.length, lessThanOrEqualTo(kHistoryWindow + 2));
      });

      test('an assistant row with neither text nor calls is not sent', () async {
        final transport = FakeTransport([saysText('Fine.')]);

        await CoachService(transport: transport).send(
          question: 'And now?',
          history: [
            CoachMessage(
              id: 'x',
              threadId: 't',
              role: CoachRole.assistant,
              content: null,
              createdAt: DateTime(2026, 7, 14),
            ),
          ],
          context: contextWith(),
        );

        final wire = transport.sent.single;
        expect(wire.map((m) => m['role']), ['system', 'user']);
      });
    });

    test('records every message needed to replay the turn', () async {
      final transport = FakeTransport([
        callsTool('get_position', {}),
        saysText('Here you go.'),
      ]);

      final turn = await CoachService(transport: transport).send(
        question: 'How am I doing?',
        history: const [],
        context: contextWith(),
      );

      expect(turn.messages.map((m) => m.role), [
        CoachRole.user,
        CoachRole.assistant, // the tool request
        CoachRole.tool, // the result
        CoachRole.assistant, // the reply
      ]);
    });

    test('withholds tools on the final round so it must answer', () async {
      final transport = FakeTransport([
        for (var i = 0; i < kMaxToolRounds; i++)
          callsTool('get_position', {}, id: 'c$i'),
      ]);

      // The last response is still a tool call, but by then tools are gone.
      transport.responses[kMaxToolRounds - 1] = saysText('Fine, here it is.');

      final turn = await CoachService(transport: transport).send(
        question: 'Loop please',
        history: const [],
        context: contextWith(),
      );

      expect(transport.toolsSeen.last, isNull);
      expect(transport.toolsSeen.first, isNotNull);
      expect(turn.reply, 'Fine, here it is.');
    });

    test('a failing tool does not kill the conversation', () async {
      final transport = FakeTransport([
        callsTool('propose_transfer', {'from_account': 'Nowhere'}),
        saysText('That account does not exist — try another.'),
      ]);

      final turn = await CoachService(transport: transport).send(
        question: 'Move money from Nowhere',
        history: const [],
        context: contextWith(),
      );

      expect(turn.actions, isEmpty);
      expect(turn.reply, contains('does not exist'));
    });

    test('an empty reply says so rather than showing a blank bubble', () async {
      final transport = FakeTransport([saysText('   ')]);

      final turn = await CoachService(transport: transport).send(
        question: 'Hello?',
        history: const [],
        context: contextWith(),
      );

      expect(turn.reply, contains('could not put an answer together'));
    });
  });
}

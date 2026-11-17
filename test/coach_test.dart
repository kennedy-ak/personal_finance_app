// The coach tests, for the server-side contract: the Dart client sends a
// question and renders a finished answer. The math the tools used to do lives
// on the server now, pinned by the backend's own suite.

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/features/insights/data/coach_service.dart';
import 'package:personal_finance_app/features/insights/data/coach_transport.dart';
import 'package:personal_finance_app/features/insights/domain/coach_action.dart';
import 'package:personal_finance_app/features/insights/domain/coach_message.dart';
import 'package:personal_finance_app/features/planning/domain/obligation.dart';

CoachAnswer answer({
  String reply = '',
  List<CoachAction> actions = const [],
  List<String> toolsUsed = const [],
}) =>
    CoachAnswer(reply: reply, actions: actions, toolsUsed: toolsUsed);

void main() {
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

    test('an unknown action type is dropped, not thrown', () {
      expect(CoachAction.fromJson({'type': 'mystery'}), isNull);
    });
  });

  group('the server round trip', () {
    test('one question, one finished answer', () async {
      final asked = <String, String>{};
      final turn = await CoachService(
        ask: ({required String threadId, required String question}) async {
          asked['threadId'] = threadId;
          asked['question'] = question;
          return answer(
            reply: 'Take it from Fidelity.',
            toolsUsed: ['get_position', 'plan_payment'],
          );
        },
      ).send(question: 'I need to send 800', threadId: 't1');

      expect(asked['threadId'], 't1');
      expect(asked['question'], 'I need to send 800');
      expect(turn.reply, 'Take it from Fidelity.');
      expect(turn.toolsUsed, ['get_position', 'plan_payment']);
      expect(turn.actions, isEmpty);
    });

    test('a proposal action rides on the turn', () async {
      const action = TransferAction(
        fromAccountId: 'fid',
        fromAccountName: 'Fidelity',
        toAccountId: 'momo',
        toAccountName: 'Mobile Money',
        amount: 750,
        reason: 'Rent is due',
      );
      final turn = await CoachService(
        ask: ({required String threadId, required String question}) async =>
            answer(reply: 'Approve the move below.', actions: [action]),
      ).send(question: 'Sort out rent', threadId: 't1');

      expect(turn.actions, hasLength(1));
      expect((turn.actions.single as TransferAction).amount, 750);
    });

    test('a blank reply gets a fallback sentence instead of an empty bubble',
        () async {
      final turn = await CoachService(
        ask: ({required String threadId, required String question}) async =>
            answer(reply: '  '),
      ).send(question: 'Hello?', threadId: 't1');

      expect(turn.reply, contains('could not put an answer together'));
    });

    test('a server failure surfaces as the error the UI shows', () async {
      await expectLater(
        CoachService(
          ask: ({required String threadId, required String question}) async =>
              throw CoachException('The coach is not configured.'),
        ).send(question: 'Hello?', threadId: 't1'),
        throwsA(isA<CoachException>()),
      );
    });
  });

  group('old threads still read', () {
    test('a legacy tool row parses and stays invisible', () {
      final m = CoachMessage.fromJson({
        'id': 'm2',
        'thread_id': 't1',
        'role': 'tool',
        'content': 'Spendable: GHS 2,350.00',
        'tool_call_id': 'call_1',
        'name': 'get_position',
        'created_at': '2026-07-14T10:00:01.000',
      });
      expect(m.role, CoachRole.tool);
      expect(m.isVisible, isFalse);
    });

    test('a stored action comes back attached to its assistant row', () {
      const original = TransferAction(
        fromAccountId: 'fid',
        fromAccountName: 'Fidelity',
        toAccountId: 'momo',
        toAccountName: 'Mobile Money',
        amount: 750,
        reason: 'Rent is due',
      );
      final m = CoachMessage.fromJson({
        'id': 'm3',
        'thread_id': 't1',
        'role': 'assistant',
        'content': 'Approve the move below.',
        'actions': [original.toJson()],
        'created_at': '2026-07-14T10:00:02.000',
      });
      expect(m.actions, hasLength(1));
      expect((m.actions.single as TransferAction).amount, 750);
      expect(m.isVisible, isTrue);
    });
  });
}

// Parity port of test/coach_test.dart.

import { describe, expect, it } from 'vitest';
import { makeDate } from '@/lib/dates';
import { type Account } from '@/lib/domain/account';
import { type Goal } from '@/lib/domain/goal';
import { type Obligation } from '@/lib/domain/obligation';
import { type Txn } from '@/lib/domain/transaction';
import { buildSnapshot } from '@/lib/finance/money-engine';
import { acc, daysAgo, now, obl, salary, steadySpending, txn } from '@/test/fixtures';
import {
  CoachError,
  CoachService,
  HISTORY_WINDOW,
  MAX_TOOL_ROUNDS,
  type CoachTransport,
} from './service';
import { CoachContext, runCoachTool } from './tools';
import {
  actionFromJson,
  actionToJson,
  type CoachMessage,
  type CommitmentAction,
  type TransferAction,
  type WireMessage,
} from './types';

const rent = obl({ name: 'Rent', amount: 1200, nextDue: makeDate(2026, 7, 28), accountId: 'momo' });
const at = new Date(Date.UTC(2026, 6, 14));

function toolTurn(question: string, answer: string, id = 'a'): CoachMessage[] {
  return [
    { id: `${id}1`, threadId: 't', role: 'user', content: question, createdAt: at },
    {
      id: `${id}2`,
      threadId: 't',
      role: 'assistant',
      content: null,
      toolCalls: [{ id: `call_${id}`, type: 'function', function: { name: 'get_position', arguments: '{}' } }],
      createdAt: at,
    },
    {
      id: `${id}3`,
      threadId: 't',
      role: 'tool',
      content: 'Spendable: GHS 2,350.00',
      toolCallId: `call_${id}`,
      name: 'get_position',
      createdAt: at,
    },
    { id: `${id}4`, threadId: 't', role: 'assistant', content: answer, createdAt: at },
  ];
}

/** Every tool row must sit directly behind an assistant turn that asked for it. */
function expectWireIsValid(wire: WireMessage[]) {
  let open = new Set<string>();
  for (const m of wire) {
    if (m.role === 'assistant') {
      open = new Set(((m.tool_calls as { id: string }[] | undefined) ?? []).map((c) => c.id));
    } else if (m.role === 'tool') {
      expect(open.has(m.tool_call_id as string), `orphaned tool result: ${m.tool_call_id}`).toBe(true);
    } else {
      open = new Set();
    }
  }
}

function contextWith({
  accounts,
  txns,
  obligations = [],
  goals = [],
}: {
  accounts?: Account[];
  txns?: Txn[];
  obligations?: Obligation[];
  goals?: Goal[];
} = {}) {
  const accs = accounts ?? [
    acc('fid', 'Fidelity', 3000),
    acc('momo', 'Mobile Money', 450, { kind: 'momo' }),
    acc('cash', 'Cash', 400, { kind: 'cash', minBalance: 300 }),
  ];
  const transactions = txns ?? steadySpending('fid');
  return new CoachContext(
    buildSnapshot({ accounts: accs, txns: transactions, obligations, goals, now }),
    accs,
    transactions,
    obligations,
    goals,
  );
}

class FakeTransport implements CoachTransport {
  sent: WireMessage[][] = [];
  toolsSeen: (unknown[] | null)[] = [];
  private index = 0;
  constructor(public responses: Record<string, unknown>[]) {}

  async complete(messages: WireMessage[], tools: unknown[] | null) {
    this.sent.push([...messages]);
    this.toolsSeen.push(tools);
    if (this.index >= this.responses.length) {
      throw new CoachError('FakeTransport ran out of scripted responses.');
    }
    return this.responses[this.index++];
  }
}

const saysText = (text: string) => ({ content: text });
const callsTool = (name: string, args: Record<string, unknown>, id = 'call_1') => ({
  content: null,
  tool_calls: [{ id, type: 'function', function: { name, arguments: JSON.stringify(args) } }],
});

describe('reading tools', () => {
  it('get_position reports the computed figures, not guesses', () => {
    const r = runCoachTool('get_position', {}, contextWith({ obligations: [salary, rent] }));
    expect(r.content).toContain('SAFE TO SPEND: GHS 2,350.00');
    expect(r.content).toContain('Next income arrives in 16 days');
    expect(r.content).toContain('GHS 50.00 per day');
  });

  it('get_position flags a missing income date rather than inventing one', () => {
    expect(runCoachTool('get_position', {}, contextWith()).content).toContain(
      'No expected income is recorded',
    );
  });

  it('list_accounts exposes floors, pinned bills and free money', () => {
    const r = runCoachTool('list_accounts', {}, contextWith({ obligations: [salary, rent] }));
    expect(r.content).toContain('Cash');
    expect(r.content).toContain('must keep GHS 300.00');
    expect(r.content).toContain('bills pinned here GHS 1,200.00');
  });

  it('list_commitments admits when nothing is recorded', () => {
    expect(runCoachTool('list_commitments', {}, contextWith()).content).toContain('Nothing recorded');
  });

  it('plan_payment defers to the planner and names the account', () => {
    const r = runCoachTool('plan_payment', { amount: 800 }, contextWith({ obligations: [salary, rent] }));
    expect(r.content).toContain('Take GHS 800.00 from Fidelity');
    expect(r.content).toContain('Not Mobile Money');
  });

  it('plan_payment handles a forced source', () => {
    const r = runCoachTool(
      'plan_payment',
      { amount: 1000, must_leave_account: 'Momo' },
      contextWith({ obligations: [salary] }),
    );
    expect(r.content).toContain('Mobile Money');
    expect(r.content).toContain('Transfer first');
  });

  it('an unknown account is reported, not silently ignored', () => {
    const r = runCoachTool('plan_payment', { amount: 500, must_leave_account: 'Barclays' }, contextWith());
    expect(r.content).toContain('no account called "Barclays"');
    expect(r.content).toContain('Fidelity');
  });

  it("get_spending excludes transfers between the user's own accounts", () => {
    const r = runCoachTool(
      'get_spending',
      { days: 30 },
      contextWith({
        txns: [
          txn({ account: 'fid', type: 'Expense', amount: 400, date: daysAgo(3) }),
          txn({ account: 'fid', to: 'momo', type: 'Transfer', amount: 2000, category: 'Transfer', date: daysAgo(2) }),
        ],
      }),
    );
    expect(r.content).toContain('GHS 400.00');
    expect(r.content).not.toContain('2,000');
  });

  it('an unknown tool name is reported rather than throwing', () => {
    expect(runCoachTool('delete_everything', {}, contextWith()).content).toContain('no tool called');
  });
});

describe('proposing actions', () => {
  it('propose_transfer returns a card and insists nothing happened', () => {
    const r = runCoachTool(
      'propose_transfer',
      { from_account: 'Fidelity', to_account: 'Mobile Money', amount: 750, reason: 'Rent leaves Momo on the 28th' },
      contextWith({ obligations: [salary, rent] }),
    );
    const t = r.action as TransferAction;
    expect(t.type).toBe('transfer');
    expect(t.fromAccountName).toBe('Fidelity');
    expect(t.toAccountName).toBe('Mobile Money');
    expect(t.amount).toBe(750);
    expect(r.content).toContain('has NOT happened');
  });

  it('refuses a transfer the source cannot fund', () => {
    const r = runCoachTool(
      'propose_transfer',
      { from_account: 'Mobile Money', to_account: 'Fidelity', amount: 5000, reason: 'because' },
      contextWith(),
    );
    expect(r.action ?? null).toBeNull();
    expect(r.content).toContain('only holds GHS 450.00');
  });

  it('refuses a transfer to the same account', () => {
    const r = runCoachTool(
      'propose_transfer',
      { from_account: 'Fidelity', to_account: 'Fidelity', amount: 100, reason: 'because' },
      contextWith(),
    );
    expect(r.action ?? null).toBeNull();
    expect(r.content).toContain('two different accounts');
  });

  it('propose_commitment builds a record awaiting approval', () => {
    const r = runCoachTool(
      'propose_commitment',
      {
        name: 'Rent',
        amount: 1200,
        direction: 'bill',
        cadence: 'monthly',
        next_due: '2026-08-28',
        account: 'Mobile Money',
      },
      contextWith(),
    );
    const a = r.action as CommitmentAction;
    expect(a.name).toBe('Rent');
    expect(a.amount).toBe(1200);
    expect(a.direction).toBe('out');
    expect(a.cadence).toBe('monthly');
    expect(a.accountName).toBe('Mobile Money');
    expect(r.content).toContain('has NOT been saved');
  });

  it('rejects a commitment with an unusable date', () => {
    const r = runCoachTool(
      'propose_commitment',
      { name: 'Rent', amount: 1200, direction: 'bill', cadence: 'monthly', next_due: 'next month sometime' },
      contextWith(),
    );
    expect(r.action ?? null).toBeNull();
    expect(r.content).toContain('must be a date');
  });
});

describe('actions survive a round trip through storage', () => {
  it('a transfer keeps every field', () => {
    const original: TransferAction = {
      type: 'transfer',
      fromAccountId: 'fid',
      fromAccountName: 'Fidelity',
      toAccountId: 'momo',
      toAccountName: 'Mobile Money',
      amount: 750,
      reason: 'Rent is due',
    };
    expect(actionFromJson(actionToJson(original))).toEqual(original);
  });

  it('a commitment keeps every field', () => {
    const original: CommitmentAction = {
      type: 'commitment',
      name: 'Rent',
      amount: 1200,
      direction: 'out',
      cadence: 'monthly',
      nextDue: makeDate(2026, 8, 28),
      accountId: 'momo',
      accountName: 'Mobile Money',
    };
    expect(actionFromJson(actionToJson(original))).toEqual(original);
  });

  it('reads an action the Flutter app stored', () => {
    // Exactly what CommitmentAction.toJson() writes from Dart.
    const fromDart = {
      type: 'commitment',
      name: 'Rent',
      amount: 1200,
      direction: 'out',
      cadence: 'monthly',
      next_due: '2026-08-28T00:00:00.000',
      account_id: null,
      account_name: null,
    };
    expect((actionFromJson(fromDart) as CommitmentAction).nextDue).toEqual(makeDate(2026, 8, 28));
  });
});

describe('the agent loop', () => {
  it('answers directly when no tool is needed', async () => {
    const transport = new FakeTransport([saysText('Budgeting is a habit.')]);
    const turn = await new CoachService(transport).send('Any general advice?', [], contextWith());
    expect(turn.reply).toBe('Budgeting is a habit.');
    expect(turn.toolsUsed).toEqual([]);
    expect(turn.actions).toEqual([]);
  });

  it('runs a tool, feeds the result back, then answers', async () => {
    const transport = new FakeTransport([callsTool('get_position', {}), saysText('You have GHS 2,350.00 spendable.')]);
    const turn = await new CoachService(transport).send(
      'How much can I spend?',
      [],
      contextWith({ obligations: [salary, rent] }),
    );
    expect(turn.toolsUsed).toEqual(['get_position']);
    expect(turn.reply).toContain('2,350.00');
    const second = transport.sent[1];
    expect(second.at(-1)!.role).toBe('tool');
    expect(second.at(-1)!.content).toContain('SAFE TO SPEND');
  });

  it('chains tools across rounds', async () => {
    const transport = new FakeTransport([
      callsTool('get_position', {}, 'c1'),
      callsTool('plan_payment', { amount: 800 }, 'c2'),
      saysText('Take it from Fidelity.'),
    ]);
    const turn = await new CoachService(transport).send(
      'I need to send 800',
      [],
      contextWith({ obligations: [salary, rent] }),
    );
    expect(turn.toolsUsed).toEqual(['get_position', 'plan_payment']);
    expect(turn.reply).toBe('Take it from Fidelity.');
  });

  it('surfaces a proposed action to the user', async () => {
    const transport = new FakeTransport([
      callsTool('propose_transfer', {
        from_account: 'Fidelity',
        to_account: 'Mobile Money',
        amount: 750,
        reason: 'Rent leaves Momo on the 28th',
      }),
      saysText('Approve the move below.'),
    ]);
    const turn = await new CoachService(transport).send(
      'Rent is due from Momo, sort it out',
      [],
      contextWith({ obligations: [salary, rent] }),
    );
    expect(turn.actions).toHaveLength(1);
    expect((turn.actions[0] as TransferAction).amount).toBe(750);
    const visible = turn.messages.filter((m) => m.role === 'assistant' && m.content != null).at(-1)!;
    expect(visible.actions).toHaveLength(1);
  });

  it('replays history so the coach remembers', async () => {
    const transport = new FakeTransport([saysText('Still Fidelity.')]);
    await new CoachService(transport).send(
      'And for a bigger amount?',
      [
        { id: '1', threadId: 't', role: 'user', content: 'Which account should I use?', createdAt: at },
        { id: '2', threadId: 't', role: 'assistant', content: 'Fidelity.', createdAt: at },
      ],
      contextWith(),
    );
    const wire = transport.sent[0];
    expect(wire[0].role).toBe('system');
    expect(wire[1].content).toBe('Which account should I use?');
    expect(wire[2].content).toBe('Fidelity.');
    expect(wire.at(-1)!.content).toBe('And for a bigger amount?');
  });

  describe('replaying a thread that used tools', () => {
    it('a whole tool group survives the trip', async () => {
      const transport = new FakeTransport([saysText('Still fine.')]);
      await new CoachService(transport).send(
        'And now?',
        toolTurn('How am I doing?', 'You have GHS 2,350.00.'),
        contextWith(),
      );
      const wire = transport.sent[0];
      expectWireIsValid(wire);
      expect(wire.map((m) => m.role)).toEqual(['system', 'user', 'assistant', 'tool', 'assistant', 'user']);
    });

    it('a tool result whose call was trimmed away is dropped', async () => {
      const transport = new FakeTransport([saysText('Fine.')]);
      await new CoachService(transport).send(
        'And now?',
        toolTurn('How am I doing?', 'All good.').slice(2),
        contextWith(),
      );
      const wire = transport.sent[0];
      expectWireIsValid(wire);
      expect(wire.some((m) => m.role === 'tool')).toBe(false);
      expect(wire.some((m) => m.content === 'All good.')).toBe(true);
    });

    it('a call that never got its result keeps the prose, drops the call', async () => {
      const transport = new FakeTransport([saysText('Fine.')]);
      const turn = toolTurn('How am I doing?', 'All good.');
      await new CoachService(transport).send('And now?', [turn[0], turn[1], turn[3]], contextWith());
      const wire = transport.sent[0];
      expectWireIsValid(wire);
      expect(wire.some((m) => 'tool_calls' in m)).toBe(false);
    });

    it('trimming a long thread never cuts a tool group in half', async () => {
      const transport = new FakeTransport([saysText('Fine.')]);
      const long: CoachMessage[] = [];
      for (let i = 0; i < 12; i++) {
        long.push(...toolTurn(`Question ${i}`, `Answer ${i}`, `q${i}`));
        if (i % 2 === 0) {
          long.push({ id: `plain${i}`, threadId: 't', role: 'assistant', content: `Aside ${i}.`, createdAt: at });
        }
      }
      expect(long.length).toBeGreaterThan(HISTORY_WINDOW);
      await new CoachService(transport).send('And now?', long, contextWith());
      const wire = transport.sent[0];
      expectWireIsValid(wire);
      expect(wire[1].role).toBe('user');
      expect(wire.length).toBeLessThanOrEqual(HISTORY_WINDOW + 2);
    });

    it('an assistant row with neither text nor calls is not sent', async () => {
      const transport = new FakeTransport([saysText('Fine.')]);
      await new CoachService(transport).send(
        'And now?',
        [{ id: 'x', threadId: 't', role: 'assistant', content: null, createdAt: at }],
        contextWith(),
      );
      expect(transport.sent[0].map((m) => m.role)).toEqual(['system', 'user']);
    });
  });

  it('records every message needed to replay the turn', async () => {
    const transport = new FakeTransport([callsTool('get_position', {}), saysText('Here you go.')]);
    const turn = await new CoachService(transport).send('How am I doing?', [], contextWith());
    expect(turn.messages.map((m) => m.role)).toEqual(['user', 'assistant', 'tool', 'assistant']);
  });

  it('withholds tools on the final round so it must answer', async () => {
    const responses: Record<string, unknown>[] = [];
    for (let i = 0; i < MAX_TOOL_ROUNDS; i++) responses.push(callsTool('get_position', {}, `c${i}`));
    responses[MAX_TOOL_ROUNDS - 1] = saysText('Fine, here it is.');
    const transport = new FakeTransport(responses);
    const turn = await new CoachService(transport).send('Loop please', [], contextWith());
    expect(transport.toolsSeen.at(-1)).toBeNull();
    expect(transport.toolsSeen[0]).not.toBeNull();
    expect(turn.reply).toBe('Fine, here it is.');
  });

  it('a failing tool does not kill the conversation', async () => {
    const transport = new FakeTransport([
      callsTool('propose_transfer', { from_account: 'Nowhere' }),
      saysText('That account does not exist — try another.'),
    ]);
    const turn = await new CoachService(transport).send('Move money from Nowhere', [], contextWith());
    expect(turn.actions).toEqual([]);
    expect(turn.reply).toContain('does not exist');
  });

  it('an empty reply says so rather than showing a blank bubble', async () => {
    const transport = new FakeTransport([saysText('   ')]);
    const turn = await new CoachService(transport).send('Hello?', [], contextWith());
    expect(turn.reply).toContain('could not put an answer together');
  });
});

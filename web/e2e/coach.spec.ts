import { expect, test, type Page, type Route } from '@playwright/test';
import { accountByName, apiAs, createConfirmedUser, rows, signIn } from './helpers';

/**
 * The model is the one thing not run locally: the backend's /coach/complete
 * is replaced by a scripted stand-in at the network layer. Everything else —
 * tool execution in the browser, persistence, the Approve button — is real.
 */

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const reply = (route: Route, message: Record<string, unknown>) =>
  route.fulfill({
    status: 200,
    headers: { ...cors, 'Content-Type': 'application/json' },
    body: JSON.stringify({ choices: [{ message }] }),
  });

async function openAskAi(page: Page) {
  await page.goto('/insights');
  await page.getByRole('tab', { name: 'Ask AI' }).click();
  await expect(page.getByRole('heading', { name: 'Your coach' })).toBeVisible();
}

test('coach runs tools in the browser, proposes a transfer, and Approve records it', async ({ page }) => {
  const user = await createConfirmedUser('coach');
  const requests: { body: Record<string, unknown>; auth: string | null }[] = [];

  await page.route('**/coach/complete', async (route) => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    const body = route.request().postDataJSON() as Record<string, unknown>;
    if (!body.tools) {
      return reply(route, { content: '1. Tip one.\n2. Tip two.\n3. Tip three.\n4. Four.\n5. Five.' });
    }
    requests.push({ body, auth: route.request().headers()['authorization'] ?? null });
    const msgs = body.messages as { role: string }[];
    if (msgs.at(-1)!.role === 'user') {
      return reply(route, {
        content: null,
        tool_calls: [
          { id: 'c1', type: 'function', function: { name: 'get_position', arguments: '{}' } },
          {
            id: 'c2',
            type: 'function',
            function: {
              name: 'propose_transfer',
              arguments: JSON.stringify({ from_account: 'Fidelity', to_account: 'Momo', amount: 250, reason: 'Top up MoMo for the week' }),
            },
          },
        ],
      });
    }
    return reply(route, { content: 'Approve the **move** below.' });
  });

  await apiAs(user.id, 'PATCH', `/accounts/${(await accountByName(user.id, 'Fidelity Account')).id}`, {
    opening_balance: 1000,
  });

  await signIn(page, user.email, user.password);

  // The daily tip lives on Insights → Overview and comes through the Edge Function.
  await page.goto('/insights');
  await expect(page.getByText('Tip one.')).toBeVisible();

  await page.getByRole('tab', { name: 'Ask AI' }).click();
  // Suggestions are built from the user's own numbers (no income date yet).
  await expect(page.getByRole('button', { name: 'Help me record my salary and bills.' })).toBeVisible();

  await page.getByLabel('Message the coach').fill('Sort out MoMo for me');
  await page.getByRole('button', { name: 'Send', exact: true }).click();

  await expect(page.getByText('Approve the')).toBeVisible();
  await expect(page.getByText('Proposed · not yet done')).toBeVisible();
  await expect(page.getByText('Move GHS 250.00 from Fidelity Account to Mobile Money')).toBeVisible();

  expect(requests).toHaveLength(2);
  expect(requests[0].auth).toMatch(/^Bearer ey/);
  const first = requests[0].body.messages as { role: string; content: string }[];
  expect(first[0].role).toBe('system');
  expect(first[0].content).toContain('Fidelity Account');
  expect((requests[0].body.tools as unknown[]).length).toBe(9);
  const second = requests[1].body.messages as { role: string; content: string }[];
  expect(second.find((m) => m.role === 'tool')!.content).toContain('Total balance: GHS 1,000.00.');

  expect((await rows('transactions', user.id)).length).toBe(0);

  await page.getByRole('button', { name: 'Approve transfer' }).click();
  await expect(page.getByText('Done', { exact: true })).toBeVisible();

  const txns = await rows<{ type: string; amount: number }>('transactions', user.id);
  expect(txns).toHaveLength(1);
  expect(txns[0].type).toBe('Transfer');
  expect(Number(txns[0].amount)).toBe(250);
  expect((await accountByName(user.id, 'Mobile Money')).balance).toBe(250);

  const msgs = await rows<{ role: string; actions: unknown; created_at: string }>('ai_messages', user.id);
  msgs.sort((a, b) => a.created_at.localeCompare(b.created_at));
  expect(msgs.map((m) => m.role)).toEqual(['user', 'assistant', 'tool', 'tool', 'assistant']);
  expect(msgs.at(-1)!.actions).toEqual([
    expect.objectContaining({ type: 'transfer', amount: 250, from_account_name: 'Fidelity Account' }),
  ]);

  // Reload: the thread and its card come back from the database.
  await openAskAi(page);
  await expect(page.getByText('Sort out MoMo for me')).toBeVisible();
  await expect(page.getByText('Move GHS 250.00 from Fidelity Account to Mobile Money')).toBeVisible();

  // New chat asks first, as in the app.
  await page.getByRole('button', { name: 'New chat' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Start fresh' }).click();
  await expect(page.getByText('Sort out MoMo for me')).toHaveCount(0);
  expect((await rows('ai_threads', user.id)).length).toBe(2);
});

test('coach errors are shown with Retry, not swallowed', async ({ page }) => {
  const user = await createConfirmedUser('coach-err');
  let fail = true;
  await page.route('**/coach/complete', (route) => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    if (fail) {
      return route.fulfill({
        status: 500,
        headers: { ...cors, 'Content-Type': 'application/json' },
        body: JSON.stringify({ detail: 'The coach is not configured. Set OPENAI_API_KEY in backend/.env.' }),
      });
    }
    return reply(route, { content: 'Back now.' });
  });
  await signIn(page, user.email, user.password);
  await openAskAi(page);
  await page.getByLabel('Message the coach').fill('Hello?');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  const card = page.getByRole('alert').filter({ hasText: 'Could not reach the coach' });
  await expect(card).toContainText('Set OPENAI_API_KEY');

  fail = false;
  await card.getByRole('button', { name: 'Retry' }).click();
  await expect(page.getByText('Back now.')).toBeVisible();
});

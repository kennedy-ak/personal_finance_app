import { expect, test } from '@playwright/test';
import { accountByName, createConfirmedUser, rows, seedInboxHold, signIn } from './helpers';

/**
 * The phone reads the inbox; the web manages what it found. Messages are
 * seeded through /sms/hold the way the Android scan writes them.
 */
test('link a sender, review a held message, learn a rule, ignore a non-money one', async ({ page }) => {
  const user = await createConfirmedUser('sms');
  const now = new Date().toISOString();
  await seedInboxHold(user.id, {
    sender: 'MobileMoney',
    body: 'Payment made for GHS 45.00 to MELCOM LTD. Current Balance: GHS 955.00.',
    receivedAt: now,
    dedupeKey: 'e2e-k1',
    parsed: {
      parser_id: 'mtn_momo',
      verdict: 'needs_category',
      direction: 'debit',
      amount: 45,
      counterparty: 'MELCOM LTD',
      summary: 'Paid MELCOM LTD',
    },
  });
  // No parsed payload → the backend holds it as 'unparsed' (unreadable).
  await seedInboxHold(user.id, {
    sender: 'MobileMoney',
    body: 'Your one-time code is 123456.',
    receivedAt: now,
    dedupeKey: 'e2e-k2',
    parsed: null,
  });

  await signIn(page, user.email, user.password);

  // Settings shows the queue size, like the app.
  await page.goto('/settings');
  await expect(page.getByText('2 messages to review')).toBeVisible();

  await page.goto('/sms-import');
  await expect(page.getByText('Needs review · 2')).toBeVisible();

  // Link MTN MoMo to the Mobile Money account.
  await page.getByRole('button', { name: /^MTN MoMo/ }).click();
  let dialog = page.getByRole('dialog');
  await dialog.getByLabel('Records into').selectOption({ label: 'Mobile Money' });
  await dialog.getByLabel('Your identifiers (optional)').fill('0244123456, 0201112222');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText('Records into Mobile Money')).toBeVisible();
  const links = await rows<{ parser_id: string; identifiers: string[] }>('sms_account_links', user.id);
  expect(links).toEqual([expect.objectContaining({ parser_id: 'mtn_momo', identifiers: ['0244123456', '0201112222'] })]);

  // Unreadable messages can't be resolved, only dismissed.
  const unreadable = page.getByRole('listitem').filter({ hasText: 'Could not read this message' });
  await expect(unreadable.getByRole('button', { name: 'Review' })).toBeDisabled();
  await unreadable.getByRole('button', { name: 'Not money' }).click();

  // Review the parsed one into a transaction, and remember the payee.
  await page.getByRole('listitem').filter({ hasText: 'Paid MELCOM LTD' }).getByRole('button', { name: 'Review' }).click();
  dialog = page.getByRole('dialog');
  await expect(dialog.getByLabel('Amount (GHS)')).toHaveValue('45');
  await expect(dialog.getByRole('radio', { name: 'Expense' })).toHaveAttribute('aria-checked', 'true');
  await dialog.getByLabel('Category').selectOption({ label: 'Shopping' });
  await expect(dialog.getByLabel(/Remember MELCOM LTD/)).toBeChecked();
  await dialog.getByRole('button', { name: 'Add to records' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText('Needs review · 0')).toBeVisible();

  // Ground truth: one sms transaction, inbox resolved, rule learned.
  const txns = await rows<{ source: string; external_ref: string; amount: number; category: string; account_id: string }>(
    'transactions',
    user.id,
  );
  expect(txns).toHaveLength(1);
  expect(txns[0]).toEqual(
    expect.objectContaining({ source: 'sms', external_ref: 'e2e-k1', category: 'Shopping' }),
  );
  expect(txns[0].account_id).toBe((await accountByName(user.id, 'Mobile Money')).id);
  const inbox = await rows<{ status: string; dedupe_key: string | null }>('sms_inbox', user.id);
  expect(inbox.map((i) => i.status).sort()).toEqual(['ignored', 'imported']);

  await expect(page.getByText('MELCOM LTD')).toBeVisible();
  await expect(page.getByText('Expense · Shopping')).toBeVisible();
  expect(await rows('sms_routing_rules', user.id)).toHaveLength(1);

  // History marks it as imported from SMS.
  await page.goto('/history');
  await expect(page.getByText('SMS', { exact: true })).toBeVisible();

  // Rules can be deleted.
  await page.goto('/sms-import');
  await page.getByRole('button', { name: 'Delete rule MELCOM LTD' }).click();
  await expect(page.getByText('Rules are learned when you tick')).toBeVisible();
  expect(await rows('sms_routing_rules', user.id)).toHaveLength(0);
});

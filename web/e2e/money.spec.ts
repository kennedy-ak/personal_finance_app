import { expect, test, type Locator, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { accountByName, apiAs, createConfirmedUser, iso, rows, signIn } from './helpers';

/**
 * One user walks the whole money flow. Every figure is worked out by hand in
 * the comments, so the screens have to agree with arithmetic, not with themselves.
 */
test.describe.configure({ mode: 'serial' });

let user: Awaited<ReturnType<typeof createConfirmedUser>>;
let page: Page;

test.beforeAll(async ({ browser }) => {
  user = await createConfirmedUser('money');
  page = await browser.newPage();
  await signIn(page, user.email, user.password);
});

test.afterAll(async () => page.close());

async function editAccount(name: string, fill: Record<string, string>) {
  await page.goto('/accounts');
  await page.getByRole('button', { name: new RegExp(`^${name}, `) }).click();
  const dialog = page.getByRole('dialog');
  for (const [label, value] of Object.entries(fill)) await dialog.getByLabel(label, { exact: true }).fill(value);
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();
}

/** Account options read "Name · Kind · Balance"; pick by the name part. */
async function selectAccount(select: Locator, name: string) {
  const option = select.locator('option', { hasText: new RegExp(`^${name} ·`) });
  await select.selectOption(await option.getAttribute('value'));
}

async function addTxn(o: {
  type: 'Expense' | 'Income' | 'Transfer';
  amount: string;
  from?: string;
  to?: string;
  category?: string;
  note?: string;
}) {
  await page.goto('/add');
  await expect(page.getByRole('heading', { name: 'New transaction' })).toBeVisible();
  await page.getByRole('radio', { name: o.type }).click();
  await page.getByLabel('Amount (GHS)').fill(o.amount);
  const fromLabel = o.type === 'Transfer' ? 'From' : 'Account';
  if (o.from) await selectAccount(page.getByLabel(fromLabel, { exact: true }), o.from);
  if (o.to) await selectAccount(page.getByLabel('To', { exact: true }), o.to);
  if (o.category) await page.getByLabel('Category').selectOption({ label: o.category });
  if (o.note) await page.getByLabel('Note (optional)').fill(o.note);
  await page.getByRole('button', { name: `Save ${o.type.toLowerCase()}` }).click();
  await page.waitForURL(/\/history$/);
}

test('balances: correcting a balance adjusts the opening balance, not history', async () => {
  await editAccount('Fidelity Account', { Balance: '3000' });
  await editAccount('Mobile Money', { Balance: '1200' });
  await editAccount('Cash', { Balance: '300', Floor: '200' });

  const fid = await accountByName(user.id, 'Fidelity Account');
  expect(fid.balance).toBe(3000);
  expect(fid.opening_balance).toBe(3000);
  expect(await rows('transactions', user.id)).toHaveLength(0);

  // Floor progress on the card, as in the app.
  await expect(page.getByText(/Floor GHS 200\.00 · 67% held back/)).toBeVisible();
});

test('a new locked account is created with its starting balance', async () => {
  await page.goto('/accounts');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Name').fill('Fixed deposit');
  await dialog.getByRole('radio', { name: 'Locked' }).click();
  await dialog.getByLabel('Starting balance').fill('5000');
  await dialog.getByRole('button', { name: 'Add account' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByRole('heading', { name: 'Fixed deposit' })).toBeVisible();
  expect((await accountByName(user.id, 'Fixed deposit')).balance).toBe(5000);
});

test('add: validation, quick add, new category inline, and the three types', async () => {
  // A transfer larger than the source holds is refused, with the app's wording.
  await page.goto('/add');
  await page.getByRole('radio', { name: 'Transfer' }).click();
  await page.getByLabel('Amount (GHS)').fill('999999');
  await page.getByRole('button', { name: 'Save transfer' }).click();
  await expect(page.getByText('Fidelity Account only holds GHS 3,000.00.')).toBeVisible();

  // Quick add fills amount and category.
  await page.getByRole('radio', { name: 'Expense' }).click();
  await page.getByRole('button', { name: /^Lunch · GHS 15\.00/ }).click();
  await expect(page.getByLabel('Amount (GHS)')).toHaveValue('15');

  // Create a category from the picker; it becomes the selection.
  await page.getByRole('button', { name: 'New', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Name').fill('Snacks');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByLabel('Category')).toHaveValue('Snacks');

  await addTxn({ type: 'Expense', amount: '150', from: 'Fidelity Account', category: 'Food & Dining', note: 'Lunch e2e' });
  await addTxn({ type: 'Income', amount: '500', from: 'Fidelity Account', category: 'Salary' });
  await addTxn({ type: 'Transfer', amount: '400', from: 'Fidelity Account', to: 'Mobile Money' });

  // 3000 - 150 + 500 - 400 = 2950 ; Momo 1200 + 400 = 1600
  expect((await accountByName(user.id, 'Fidelity Account')).balance).toBe(2950);
  expect((await accountByName(user.id, 'Mobile Money')).balance).toBe(1600);

  await expect(page.getByText('Lunch e2e')).toBeVisible();
  await expect(page.getByText('Fidelity Account → Mobile Money')).toBeVisible();
  // Day net = income − spending = 500 − 150; transfers count zero.
  await expect(page.getByText('+GHS 350.00')).toBeVisible();
});

test('commitments: income, a bill and a goal', async () => {
  await page.goto('/plan');
  await expect(page.getByRole('heading', { name: 'Commitments' })).toBeVisible();

  await page.getByRole('button', { name: 'Add', exact: true }).click();
  let dialog = page.getByRole('dialog');
  await dialog.getByRole('radio', { name: 'Income' }).click();
  await dialog.getByLabel('What is it').fill('Salary');
  await dialog.getByLabel('Amount (GHS)').fill('4000');
  await dialog.getByLabel('Next due').fill(iso(16));
  await dialog.getByLabel('Lands in').selectOption({ label: 'Fidelity Account' });
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();

  await page.getByRole('button', { name: 'Add', exact: true }).click();
  dialog = page.getByRole('dialog');
  await dialog.getByLabel('What is it').fill('Rent');
  await dialog.getByLabel('Amount (GHS)').fill('1200');
  await dialog.getByLabel('Next due').fill(iso(5));
  await dialog.getByLabel('Leaves from').selectOption({ label: 'Mobile Money' });
  await dialog.getByLabel('Category').selectOption({ label: 'Housing' });
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();

  // Momo holds 1600 >= 1200, so the bill is covered.
  await expect(page.getByText(/^Covered · due/)).toBeVisible();
  await expect(page.getByText('Leaving before')).toBeVisible();

  await page.getByRole('tab', { name: 'Goals' }).click();
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  dialog = page.getByRole('dialog');
  await dialog.getByLabel('Goal').fill('Emergency fund');
  await dialog.getByLabel('Target (GHS)').fill('6000');
  await dialog.getByLabel('Saved').fill('1000');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText('GHS 1,000.00 saved of GHS 6,000.00')).toBeVisible();

  const obs = await rows<{ next_due: string; direction: string; category: string | null }>('obligations', user.id);
  expect(obs.map((o) => [o.direction, o.next_due]).sort()).toEqual([['in', iso(16)], ['out', iso(5)]].sort());
  expect(obs.find((o) => o.direction === 'out')!.category).toBe('Housing');
});

test('dashboard shows the figures the engine should compute', async () => {
  await page.goto('/');
  // liquid = 2950 + 0 + 1600 + 300 = 4850 (Fixed deposit is locked)
  // floors 200, goal 1000, rent 1200 lands before salary
  // safe to spend = 4850 - 200 - 1000 - 1200 = 2450
  await expect(page.getByTestId('safe-to-spend')).toHaveText('2,450.00');
  await expect(page.getByText(/before your next income on .* · 16 days/)).toBeVisible();
  // Per day = 2450 / 16 = 153.125
  await expect(page.getByText('GHS 153.13')).toBeVisible();
  // total = 4850 + 5000
  await expect(page.getByText('GHS 9,850.00').first()).toBeVisible();
  await expect(page.getByText('Where your money sits')).toBeVisible();
  // Protected = floors 200 + goals 1000 + locked 5000
  await expect(page.getByText('GHS 6,200.00')).toBeVisible();
  await expect(page.getByRole('link', { name: /I need to pay someone/ })).toBeVisible();
});

test('pay: plans the source, then records the top-up and the payment', async () => {
  await page.goto('/pay');
  await page.getByLabel('Amount (GHS)').fill('1000');
  await expect(page.getByRole('heading', { name: 'Take GHS 1,000.00 from Fidelity Account' })).toBeVisible();

  // Momo: 1600 held, 1200 pinned to rent. Paying 2000 from it needs 400 more.
  await page.getByLabel('Amount (GHS)').fill('2000');
  await page.getByLabel('It has to leave from').selectOption({ label: 'Mobile Money' });
  await expect(page.getByRole('heading', { name: 'Move GHS 400.00 from Fidelity Account into Mobile Money first' })).toBeVisible();

  // Record a smaller one end to end.
  await page.getByLabel('Amount (GHS)').fill('100');
  await page.getByLabel('It has to leave from').selectOption({ label: 'Anywhere — you decide' });
  await page.getByLabel('What is it for?').fill('Sending to Kwame');
  await page.getByRole('button', { name: 'Record this payment' }).click();
  await expect(page.getByText('Recorded GHS 100.00.')).toBeVisible();

  const txns = await rows<{ description: string; category: string; amount: number; type: string }>('transactions', user.id);
  const paid = txns.find((t) => t.description === 'Sending to Kwame')!;
  expect(paid.type).toBe('Expense');
  expect(Number(paid.amount)).toBe(100);
  expect(paid.category).toBe('Other');
  // 2950 - 100
  expect((await accountByName(user.id, 'Fidelity Account')).balance).toBe(2850);
});

test('categories: rename relabels transactions, hide and restore', async () => {
  await page.goto('/categories');
  await page.getByRole('button', { name: 'Food & Dining options' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Rename or change icon' }).click();
  const editor = page.getByRole('dialog');
  await editor.getByLabel('Name').fill('Food');
  await editor.getByRole('button', { name: 'Restaurant' }).click();
  await editor.getByRole('button', { name: 'Save' }).click();
  await expect(editor).toBeHidden();

  const txns = await rows<{ category: string; description: string | null }>('transactions', user.id);
  expect(txns.find((t) => t.description === 'Lunch e2e')!.category).toBe('Food');
  const cats = await rows<{ name: string; icon: string }>('categories', user.id);
  expect(cats.find((c) => c.name === 'Food')!.icon).toBe('restaurant');

  await page.getByRole('button', { name: 'Travel options' }).click();
  await page.getByRole('dialog').getByRole('button', { name: /Hide from pickers/ }).click();
  await expect(page.getByRole('button', { name: 'Restore Travel' })).toBeVisible();

  await page.goto('/add');
  const picker = page.getByLabel('Category');
  await expect(picker.locator('option', { hasText: /^Food$/ })).toHaveCount(1);
  await expect(picker.locator('option', { hasText: /^Travel$/ })).toHaveCount(0);

  await page.goto('/categories');
  await page.getByRole('button', { name: 'Restore Travel' }).click();
  await expect(page.getByRole('button', { name: 'Travel options' })).toBeVisible();
});

test('history: search by amount, filter, CSV, detail and delete', async () => {
  await page.goto('/history');
  await page.getByLabel('Search').fill('150.00');
  await expect(page.getByText('1 row', { exact: true })).toBeVisible();
  await page.getByLabel('Search').fill('');

  await page.getByRole('button', { name: 'Filters' }).click();
  const filter = page.getByRole('dialog');
  await filter.getByRole('button', { name: 'Income', exact: true }).click();
  await filter.getByRole('button', { name: 'Show 1 transaction' }).click();
  await expect(page.getByText('1 row', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Clear', exact: true }).click();

  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Export CSV' }).click(),
  ]);
  const csv = await readFile((await download.path())!, 'utf8');
  expect(csv).toContain('Date,Type,Amount,Account,Category,Description');
  expect(csv).toContain('Lunch e2e');
  expect(csv.trim().split(/\r?\n/)).toHaveLength(5);

  await page.getByRole('button', { name: /Lunch e2e/ }).click();
  const detail = page.getByRole('dialog');
  await expect(detail.getByText('Fidelity Account')).toBeVisible();
  await detail.getByRole('button', { name: 'Delete transaction' }).click();
  const confirm = page.getByRole('dialog');
  await expect(confirm.getByText(/will be removed and your balances will settle back/)).toBeVisible();
  await confirm.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(page.getByText('Lunch e2e')).toHaveCount(0);
  // 2850 + 150
  await expect.poll(async () => (await accountByName(user.id, 'Fidelity Account')).balance).toBe(3000);
});

test('reports: this week, trends and detailed', async () => {
  await page.goto('/reports');
  // This week: income 500, spending 100 (Kwame). Transfers excluded.
  await expect(page.getByText('Net this week')).toBeVisible();
  await expect(page.getByText('GHS 400.00').first()).toBeVisible();

  await page.getByRole('tab', { name: 'Trends' }).click();
  await expect(page.getByText('Net by month')).toBeVisible();
  await expect(page.getByText(/^Every one of the last six months ended positive/)).toBeVisible();

  await page.getByRole('tab', { name: 'Detailed' }).click();
  await expect(page.getByText('By account')).toBeVisible();
  await expect(page.getByText('In GHS 500.00')).toBeVisible();
});

test('insights: overview sections and the accounts first-run screen', async () => {
  await page.goto('/insights');
  await expect(page.getByRole('heading', { name: 'Needs your attention' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Your numbers' })).toBeVisible();
  await expect(page.getByText('Kept of income')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Goals' })).toBeVisible();

  // An account-less user gets the first-run setup screen.
  for (const a of await rows<{ id: string }>('accounts', user.id)) {
    await apiAs(user.id, 'DELETE', `/accounts/${a.id}`);
  }
  await page.goto('/accounts');
  await expect(page.getByRole('heading', { name: 'Add where your money actually is' })).toBeVisible();
  await page.getByRole('button', { name: /^Mobile Money/ }).click();
  await expect(page.getByRole('dialog').getByLabel('Kind')).toHaveValue('momo');
});

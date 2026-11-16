import { expect, test } from '@playwright/test';
import {
  accountByName,
  apiAs,
  createConfirmedUser,
  rows,
  signIn,
  signInApi,
  skipWelcome,
  testIdentity,
} from './helpers';

test.describe('signed-out guard (proxy)', () => {
  test('a first visit lands on the welcome screen, like the app splash', async ({ page }) => {
    await page.goto('/history');
    await expect(page).toHaveURL(/\/welcome$/);
    await expect(page.getByRole('heading', { name: 'Know what you can spend.' })).toBeVisible();
    await expect(page.getByText('Pursely reads your accounts')).toBeVisible();
    await expect(page).toHaveTitle('Pursely');

    await page.getByRole('button', { name: 'I have an account' }).click();
    await expect(page).toHaveURL(/\/login$/);

    // Seen once: from now on protected pages go straight to login.
    await page.goto('/accounts');
    await expect(page).toHaveURL(/\/login$/);
  });

  test('"Get started" goes to sign up', async ({ page }) => {
    await page.goto('/welcome');
    await page.getByRole('button', { name: 'Get started' }).click();
    await expect(page.getByRole('heading', { name: 'Set up your money' })).toBeVisible();
  });

  for (const path of ['/', '/insights', '/settings', '/sms-import']) {
    test(`${path} redirects to /login once the welcome has been seen`, async ({ page, context }) => {
      await skipWelcome(context);
      await page.goto(path);
      await expect(page).toHaveURL(/\/login$/);
    });
  }
});

test('sign up applies the app’s rules and creates the same starter data', async ({ page, context }) => {
  await skipWelcome(context);
  const who = testIdentity('signup');
  await page.goto('/signup');

  // Same validation as signup_screen.dart.
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByText('Tell us what to call you')).toBeVisible();
  await page.getByLabel('Name').fill(who.name);
  await page.getByLabel('Email').fill(who.email);
  await page.getByLabel('Password', { exact: true }).fill('short1');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByText('At least 8 characters', { exact: true })).toBeVisible();

  await page.getByLabel('Password', { exact: true }).fill(who.password);
  await page.getByRole('button', { name: 'Create account' }).click();
  await page.waitForURL((u) => u.pathname === '/');
  // Greeting uses the first name, like displayName in the app.
  await expect(page.getByRole('heading', { name: 'Hello, E2E' })).toBeVisible();

  // Ground truth through the API, as the user.
  const me = await signInApi(who.email, who.password);
  expect(me.fullName).toBe(who.name);
  const accounts = await rows<{ name: string }>('accounts', me.id);
  expect(accounts.map((a) => a.name).sort()).toEqual(['Access Account', 'Cash', 'Fidelity Account', 'Mobile Money'].sort());
  expect((await rows('categories', me.id)).length).toBe(19);
});

test('log in, app error wording, remembered email, sign out with confirmation', async ({ page, context }) => {
  const user = await createConfirmedUser('signin');
  await skipWelcome(context);

  await page.goto('/login');
  await page.getByLabel('Email').fill(user.email);
  await page.getByLabel('Password', { exact: true }).fill('definitely-wrong');
  await page.getByRole('button', { name: 'Log in' }).click();
  await expect(page.getByText('That password does not match this email. Try again or reset it.')).toBeVisible();

  // Password visibility toggle.
  await page.getByRole('button', { name: 'Show password' }).click();
  await expect(page.getByLabel('Password', { exact: true })).toHaveAttribute('type', 'text');

  await signIn(page, user.email, user.password);
  await page.goto('/login');
  await expect(page).toHaveURL(/\/$/);

  await page.goto('/settings');
  await expect(page.getByText(user.email)).toBeVisible();
  await page.getByRole('main').getByRole('button', { name: 'Sign out' }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByText('Your data stays on the server.')).toBeVisible();
  await dialog.getByRole('button', { name: 'Sign out' }).click();
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByLabel('Email')).toHaveValue(user.email);

  await page.goto('/accounts');
  await expect(page).toHaveURL(/\/login$/);
});

test('changing the password from Settings, with the current one as proof', async ({ page }) => {
  const user = await createConfirmedUser('newpw');
  const newPassword = `${user.password}-new`;

  await signIn(page, user.email, user.password);
  await page.goto('/auth/update-password');

  // The current password is checked, not decorative.
  await page.getByLabel('Current password').fill('definitely-wrong');
  await page.getByLabel('New password', { exact: true }).fill(newPassword);
  await page.getByLabel('Confirm new password').fill(newPassword);
  await page.getByRole('button', { name: 'Update password' }).click();
  await expect(page.getByText('Your current password is not right.')).toBeVisible();

  await page.getByLabel('Current password').fill(user.password);
  await page.getByRole('button', { name: 'Update password' }).click();
  await expect(page.getByText('Password updated')).toBeVisible();

  // Old password is dead, the new one works — same check the app would make.
  await expect(signInApi(user.email, user.password)).rejects.toThrow(/401/);
  const me = await signInApi(user.email, newPassword);
  expect(me.id).toBe(user.id);
});

test('there is no email reset — the login screen says so instead of pretending', async ({ page, context }) => {
  await skipWelcome(context);
  await page.goto('/login');
  await page.getByRole('button', { name: 'Forgot password' }).click();
  await expect(page.getByText('Password reset by email is not available')).toBeVisible();
});

test('ownership: one user can never see or change another user’s rows', async () => {
  const a = await createConfirmedUser('own-a');
  const b = await createConfirmedUser('own-b');
  const aFidelity = await accountByName(a.id, 'Fidelity Account');

  // B sees only B's rows.
  const visible = await rows<{ id: string; user_id: string }>('accounts', b.id);
  expect(visible.length).toBe(4);
  expect(visible.every((r) => r.user_id === b.id)).toBe(true);

  // B cannot touch A's account: the API answers 404, and A's row is unchanged.
  await expect(
    apiAs(b.id, 'PATCH', `/accounts/${aFidelity.id}`, { name: 'hijacked' }),
  ).rejects.toThrow(/404/);
  expect((await accountByName(a.id, 'Fidelity Account')).name).toBe('Fidelity Account');
});

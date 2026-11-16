/**
 * Presentation helpers shared with the Flutter app's wording:
 * txn_style.dart, CategoryGlyph.initials, auth_repository displayName and the
 * dashboard greeting.
 */

import { diffDays, today, type DateOnly } from './dates';
import { type Txn } from './domain/transaction';
import { dateLong, dayMonth } from './format';

/** CategoryGlyph.initials — "Gifts & Donations" -> "GD", "Shopping" -> "SH". */
export function initials(name: string): string {
  const words = name.split(/[\s&/_-]+/).filter((w) => w && /[A-Za-z0-9]/.test(w));
  if (words.length === 0) return '??';
  if (words.length === 1) {
    const w = words[0];
    return (w.length === 1 ? w : w.slice(0, 2)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/** Stable 0–11 hue from a name, so a category keeps its colour everywhere. */
export function hueFor(name: string): number {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) | 0;
  return Math.abs(h) % 12;
}

/** txn_style.titleForTxn: the category, or "From → To" for a transfer. */
export function titleForTxn(t: Txn, accountName: (id: string) => string): string {
  if (t.type === 'Transfer') {
    return `${accountName(t.accountId)} → ${t.toAccountId ? accountName(t.toAccountId) : '?'}`;
  }
  return t.category;
}

/** Signed amount: + for income, − for expense, none for transfers. */
export function signedAmount(t: Txn): number {
  return t.type === 'Expense' ? -t.amount : t.amount;
}

/** "Today · 14 Nov", "Yesterday · 13 Nov", or "Nov 12, 2026". */
export function dayHeader(d: DateOnly, now: DateOnly = today()): string {
  const diff = diffDays(now, d);
  if (diff === 0) return `Today · ${dayMonth(d)}`;
  if (diff === 1) return `Yesterday · ${dayMonth(d)}`;
  return dateLong(d);
}

/** "Today, Nov 14, 2026" / "Yesterday, …" / long date — the Add screen's date row. */
export function relativeDate(d: DateOnly, now: DateOnly = today()): string {
  const diff = diffDays(now, d);
  if (diff === 0) return `Today, ${dateLong(d)}`;
  if (diff === 1) return `Yesterday, ${dateLong(d)}`;
  return dateLong(d);
}

/** auth_repository.displayName: first word of full_name, else the email's local part. */
export function displayName(fullName: string | null | undefined, email: string | null | undefined): string | null {
  const n = fullName?.trim();
  if (n) return n.split(/\s+/)[0];
  const local = email?.split('@')[0];
  if (!local) return null;
  const part = local.split(/[._-]/).find((p) => p) ?? local;
  return part.charAt(0).toUpperCase() + part.slice(1);
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** "Friday morning" — morning before 12, afternoon before 17. */
export function greeting(now: Date): string {
  const h = now.getHours();
  const part = h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening';
  return `${WEEKDAYS[now.getDay()]} ${part}`;
}

export const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

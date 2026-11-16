import { toIsoDate } from './dates';
import { type Txn } from './domain/transaction';

function cell(v: string): string {
  // Neutralise spreadsheet formula injection, then quote when needed.
  const safe = /^[=+\-@]/.test(v) ? `'${v}` : v;
  return /[",\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

/** Same columns, in the same order, as history_screen.dart's export. */
export function transactionsToCsv(txns: Txn[], accountName: (id: string) => string): string {
  const header = ['Date', 'Type', 'Amount', 'Account', 'Category', 'Description'];
  const rows = txns.map((t) => [
    toIsoDate(t.date),
    t.type,
    t.amount.toFixed(2),
    accountName(t.accountId),
    t.category,
    t.description ?? '',
  ]);
  return [header.join(','), ...rows.map((r) => r.map(cell).join(','))].join('\r\n');
}

export function downloadText(filename: string, text: string, type = 'text/csv') {
  const blob = new Blob([`﻿${text}`], { type: `${type};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

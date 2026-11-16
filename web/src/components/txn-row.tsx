'use client';

import { type Txn } from '@/lib/domain/transaction';
import { dateLong, formatMoney, timeOfDay } from '@/lib/format';
import { hueFor, titleForTxn } from '@/lib/present';
import { Badge, Glyph, cx } from './ui';

/** The app's TxnRow: glyph, title over subtitle, signed figure. */
export function TxnRow({
  t,
  accountName,
  subtitle,
  onClick,
}: {
  t: Txn;
  accountName: (id: string) => string;
  /** account-date on the dashboard; account-category-time in History. */
  subtitle: 'account-date' | 'account-category-time';
  onClick?: () => void;
}) {
  const transfer = t.type === 'Transfer';
  const title = t.description || titleForTxn(t, accountName);
  const sub =
    subtitle === 'account-date'
      ? `${accountName(t.accountId)} · ${dateLong(t.date)}`
      : `${transfer ? 'Transfer' : `${accountName(t.accountId)} · ${t.category}`} · ${timeOfDay(t.createdAt)}`;
  const sign = t.type === 'Income' ? '+' : t.type === 'Expense' ? '-' : '';

  const inner = (
    <>
      <Glyph name={t.category} hue={hueFor(t.category)} neutral={transfer} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium">{title}</span>
          {t.cameFromSms && <Badge>SMS</Badge>}
        </div>
        <div className="truncate text-xs text-ink-muted">{sub}</div>
      </div>
      <span
        className={cx(
          'tabular whitespace-nowrap text-sm font-semibold',
          t.type === 'Income' && 'text-income',
          t.type === 'Expense' && 'text-ink',
          transfer && 'text-ink-muted',
        )}
      >
        {sign}
        {formatMoney(t.amount)}
      </span>
    </>
  );

  return (
    <li>
      {onClick ? (
        <button
          type="button"
          onClick={onClick}
          className="flex w-full items-center gap-3 rounded-xl px-2 py-2.5 text-left hover:bg-recessed"
        >
          {inner}
        </button>
      ) : (
        <div className="flex items-center gap-3 px-2 py-2.5">{inner}</div>
      )}
    </li>
  );
}

'use client';

import {
  cloneElement,
  isValidElement,
  useEffect,
  useId,
  useRef,
  useState,
  type ReactElement,
  type ButtonHTMLAttributes,
  type ComponentProps,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react';
import { formatMoney } from '@/lib/format';
import { initials } from '@/lib/present';

export function cx(...parts: (string | false | null | undefined)[]) {
  return parts.filter(Boolean).join(' ');
}

// --- Layout -----------------------------------------------------------------

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-2xl font-semibold tracking-tight text-ink">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-ink-muted">{subtitle}</p>}
      </div>
      {action}
    </header>
  );
}

export function Card({
  children,
  className,
  as: Tag = 'section',
}: {
  children: ReactNode;
  className?: string;
  as?: 'section' | 'div' | 'li' | 'article';
}) {
  return (
    <Tag className={cx('rounded-2xl border border-hairline bg-card p-5', className)}>{children}</Tag>
  );
}

export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between gap-2">
      <h2 className="text-sm font-semibold text-ink">{children}</h2>
      {action}
    </div>
  );
}

// --- Figures ----------------------------------------------------------------

export function Money({
  value,
  tone,
  className,
}: {
  value: number;
  tone?: 'income' | 'expense' | 'muted';
  className?: string;
}) {
  return (
    <span
      className={cx(
        'tabular whitespace-nowrap',
        tone === 'income' && 'text-income',
        tone === 'expense' && 'text-expense',
        tone === 'muted' && 'text-ink-muted',
        className,
      )}
    >
      {formatMoney(value)}
    </span>
  );
}

export function Stat({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
}) {
  return (
    <div className="min-w-0">
      <div className="font-mono text-[11px] uppercase tracking-wider text-ink-faint">{label}</div>
      <div className="mt-1 text-lg font-semibold text-ink">{value}</div>
      {hint && <div className="mt-0.5 text-xs text-ink-muted">{hint}</div>}
    </div>
  );
}

// --- Controls ---------------------------------------------------------------

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';

export function Button({
  variant = 'primary',
  busy,
  className,
  children,
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant; busy?: boolean }) {
  return (
    <button
      {...rest}
      disabled={disabled || busy}
      className={cx(
        'inline-flex h-10 items-center justify-center gap-2 rounded-xl px-4 text-sm font-medium transition-colors',
        'disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary' && 'bg-brand text-on-brand hover:bg-brand-pressed',
        variant === 'secondary' && 'border border-outline bg-card text-ink hover:bg-recessed',
        variant === 'ghost' && 'text-ink-muted hover:bg-recessed hover:text-ink',
        variant === 'danger' && 'border border-expense-border bg-expense-surface text-expense hover:opacity-90',
        className,
      )}
    >
      {busy && <Spinner small />}
      {children}
    </button>
  );
}

const fieldClass =
  'h-10 w-full rounded-xl border border-field-border bg-field px-3 text-sm text-ink placeholder:text-ink-faint focus:border-brand-ink focus:outline-none';

/**
 * A labelled control. The label names the control and nothing else; the hint
 * or error is attached with aria-describedby, so a screen reader announces
 * "To", not "To Access Account Mobile Money Cash…".
 */
export function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: ReactNode;
  error?: string | null;
  children: ReactElement<{ id?: string; 'aria-describedby'?: string; 'aria-invalid'?: boolean }>;
}) {
  const id = useId();
  const noteId = `${id}-note`;
  const note = error ?? hint;
  const control = isValidElement(children)
    ? cloneElement(children, {
        id: children.props.id ?? id,
        'aria-describedby': note ? noteId : undefined,
        'aria-invalid': error ? true : undefined,
      })
    : children;

  return (
    <div>
      <label htmlFor={children.props.id ?? id} className="mb-1.5 block text-xs font-medium text-ink-muted">
        {label}
      </label>
      {control}
      {note && (
        <span id={noteId} className={cx('mt-1 block text-xs', error ? 'text-expense' : 'text-ink-faint')}>
          {note}
        </span>
      )}
    </div>
  );
}

export function Input(props: ComponentProps<'input'>) {
  return <input {...props} className={cx(fieldClass, props.className)} />;
}

/** Password field with a show/hide toggle, like auth_field.dart. */
export function PasswordInput(props: ComponentProps<'input'> & { invalid?: boolean }) {
  const [shown, setShown] = useState(false);
  const { invalid, className, ...rest } = props;
  return (
    <div className="relative">
      <input
        {...rest}
        type={shown ? 'text' : 'password'}
        className={cx(fieldClass, 'pr-16', invalid && 'border-expense', className)}
      />
      <button
        type="button"
        onClick={() => setShown((s) => !s)}
        aria-label={shown ? 'Hide password' : 'Show password'}
        className="absolute inset-y-0 right-2 my-auto h-7 rounded-md px-2 text-xs text-ink-muted hover:bg-recessed"
      >
        {shown ? 'Hide' : 'Show'}
      </button>
    </div>
  );
}

export function Textarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      {...props}
      className={cx(fieldClass, 'h-auto min-h-20 py-2', props.className)}
    />
  );
}

export function Select({
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement> & { children: ReactNode }) {
  return (
    <select {...props} className={cx(fieldClass, 'pr-8', props.className)}>
      {children}
    </select>
  );
}

/** A row of mutually exclusive choices. */
export function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
  label: string;
}) {
  return (
    <div role="radiogroup" aria-label={label} className="inline-flex rounded-xl bg-recessed p-1">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={cx(
            'h-8 rounded-lg px-3 text-sm font-medium transition-colors',
            value === o.value ? 'bg-card text-ink shadow-sm' : 'text-ink-muted hover:text-ink',
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

// --- Feedback ---------------------------------------------------------------

export function Spinner({ small }: { small?: boolean }) {
  return (
    <span
      role="status"
      aria-label="Loading"
      className={cx(
        'inline-block animate-spin rounded-full border-2 border-current border-t-transparent',
        small ? 'h-4 w-4' : 'h-6 w-6 text-brand-ink',
      )}
    />
  );
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="flex items-center gap-3 py-16 text-sm text-ink-muted">
      <Spinner /> {label}
    </div>
  );
}

export function ErrorNote({ error }: { error: unknown }) {
  if (!error) return null;
  const message = error instanceof Error ? error.message : String(error);
  return (
    <div
      role="alert"
      className="rounded-xl border border-expense-border bg-expense-surface px-4 py-3 text-sm text-expense"
    >
      {message}
    </div>
  );
}

export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="rounded-2xl border border-dashed border-outline px-6 py-10 text-center">
      <p className="font-medium text-ink">{title}</p>
      {children && <div className="mt-2 text-sm text-ink-muted">{children}</div>}
    </div>
  );
}

export type Tone = 'income' | 'expense' | 'warning' | 'info' | 'accent' | 'neutral';

const TONE: Record<Tone, string> = {
  income: 'bg-income-surface border-income-border text-income',
  expense: 'bg-expense-surface border-expense-border text-expense',
  warning: 'bg-warning-surface border-warning-border text-warning',
  info: 'bg-info-surface border-info-border text-info',
  accent: 'bg-accent-surface border-accent-border text-accent',
  neutral: 'bg-recessed border-hairline text-ink-muted',
};

export function Badge({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span
      className={cx(
        'inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium',
        TONE[tone],
      )}
    >
      {children}
    </span>
  );
}

export function toneClasses(t: Tone) {
  return TONE[t];
}

// --- Glyph ------------------------------------------------------------------

/** CategoryGlyph: two-letter plate on one of 12 hues; transfers are neutral ⇆. */
export function Glyph({
  name,
  hue,
  neutral,
  size = 32,
}: {
  name: string;
  hue: number;
  neutral?: boolean;
  size?: number;
}) {
  const i = Math.abs(hue) % 12;
  return (
    <span
      aria-hidden
      className="inline-flex shrink-0 items-center justify-center rounded-full font-bold leading-none"
      style={{
        width: size,
        height: size,
        fontSize: neutral ? size * 0.38 : size * 0.32,
        background: neutral ? 'var(--track)' : `var(--gs-${i})`,
        color: neutral ? 'var(--ink-muted)' : `var(--gi-${i})`,
      }}
    >
      {neutral ? '⇆' : initials(name)}
    </span>
  );
}

/** Small mono uppercase label, the app's "Eyebrow". */
export function Eyebrow({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cx('font-mono text-[11px] uppercase tracking-wider text-ink-faint', className)}>
      {children}
    </div>
  );
}

/** A labelled confirmation, the app's confirm sheet. */
export function Confirm({
  open,
  title,
  body,
  confirmLabel,
  cancelLabel = 'Cancel',
  danger,
  busy,
  error,
  onConfirm,
  onClose,
}: {
  open: boolean;
  title: string;
  body: ReactNode;
  confirmLabel: string;
  cancelLabel?: string;
  danger?: boolean;
  busy?: boolean;
  error?: unknown;
  onConfirm: () => void;
  onClose: () => void;
}) {
  return (
    <Dialog open={open} onClose={onClose} title={title}>
      <div className="space-y-4 text-sm">
        <div className="text-ink-body">{body}</div>
        <ErrorNote error={error} />
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>
            {cancelLabel}
          </Button>
          <Button variant={danger ? 'danger' : 'primary'} busy={busy} onClick={onConfirm}>
            {confirmLabel}
          </Button>
        </div>
      </div>
    </Dialog>
  );
}

/** Underlined tab strip, the app's TabBar. */
export function Tabs<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
  label: string;
}) {
  return (
    <div role="tablist" aria-label={label} className="mb-6 flex gap-6 border-b border-hairline">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="tab"
          aria-selected={value === o.value}
          onClick={() => onChange(o.value)}
          className={cx(
            '-mb-px border-b-2 pb-2.5 text-sm font-medium transition-colors',
            value === o.value ? 'border-brand-ink text-ink' : 'border-transparent text-ink-muted hover:text-ink',
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

// --- Dialog -----------------------------------------------------------------

/** A native <dialog>, so focus trapping and Esc come for free. */
export function Dialog({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      // Only a user dismissal (Esc, backdrop, ✕) calls onClose. The native
      // `close` event also fires when the parent closes it via `open`, e.g. to
      // hand over to a confirmation — reacting to that would tear the
      // confirmation down before it appears.
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      onClick={(e) => {
        if (e.target === ref.current) onClose();
      }}
      className="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-2xl border border-hairline bg-card p-0 text-ink backdrop:bg-black/40"
    >
      {open && (
        <div className="p-6">
          <div className="mb-5 flex items-start justify-between gap-4">
            <h2 className="text-lg font-semibold">{title}</h2>
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="-mr-2 -mt-1 rounded-lg px-2 py-1 text-ink-muted hover:bg-recessed"
            >
              ✕
            </button>
          </div>
          {children}
        </div>
      )}
    </dialog>
  );
}

/** Parses a money field. Returns null for anything that is not a positive-or-zero number. */
export function parseAmount(s: string): number | null {
  const n = Number(s.replace(/,/g, '').trim());
  return s.trim() === '' || !Number.isFinite(n) ? null : Math.round(n * 100) / 100;
}

/**
 * Formatting that matches the Flutter app character for character, because
 * alert and coach text is built from these strings and the tests pin them.
 *
 * Dart: NumberFormat.currency(locale: 'en_GH', symbol: 'GHS ', decimalDigits: 2)
 *   -> `GHS 1,298.00`, and `-GHS 1,298.00` when negative.
 */

export const CURRENCY_CODE = 'GHS';

const digits = new Intl.NumberFormat('en-US', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** `1,298.00` / `-1,298.00` — the figure without its code. */
export function moneyDigits(value: number): string {
  return digits.format(normalise(value));
}

/** `GHS 1,298.00`, and `-GHS 1,298.00` when negative. */
export function formatMoney(value: number): string {
  const v = normalise(value);
  const body = digits.format(Math.abs(v));
  return v < 0 && body !== '0.00' ? `-GHS ${body}` : `GHS ${body}`;
}

/** Avoids `-0.00` and float dust like 1199.9999999 printing oddly. */
function normalise(v: number): number {
  const r = Math.round(v * 100) / 100;
  return Object.is(r, -0) ? 0 : r;
}

const MONTHS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/** `Jul 31, 2026` — Dart's `MMM d, yyyy`. Expects a UTC-midnight date. */
export function dateLong(d: Date): string {
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}

/** `12 Sep` — Dart's `d MMM`. */
export function dayMonth(d: Date): string {
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

/** `Aug`. */
export function monthShort(d: Date): string {
  return MONTHS[d.getUTCMonth()];
}

/** `6:42 pm` in the viewer's zone — for real timestamps such as created_at. */
export function timeOfDay(d: Date): string {
  return d
    .toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    .toLowerCase();
}

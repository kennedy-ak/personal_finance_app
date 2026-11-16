'use client';

import { useSyncExternalStore } from 'react';
import { Icon } from './icons';
import { Segmented } from './ui';

type Theme = 'system' | 'light' | 'dark';

const EVENT = 'themechange';

function read(): Theme {
  try {
    const t = localStorage.getItem('theme');
    return t === 'light' || t === 'dark' ? t : 'system';
  } catch {
    return 'system';
  }
}

function subscribe(onChange: () => void) {
  window.addEventListener(EVENT, onChange);
  window.addEventListener('storage', onChange); // other tabs
  return () => {
    window.removeEventListener(EVENT, onChange);
    window.removeEventListener('storage', onChange);
  };
}

/** The saved theme; 'system' during server render. */
function useTheme(): Theme {
  return useSyncExternalStore(subscribe, read, () => 'system');
}

function apply(t: Theme) {
  const root = document.documentElement;
  if (t === 'system') delete root.dataset.theme;
  else root.dataset.theme = t;
  try {
    if (t === 'system') localStorage.removeItem('theme');
    else localStorage.setItem('theme', t);
  } catch {}
  window.dispatchEvent(new Event(EVENT));
}

/** System / Light / Dark — the web twin of lib/core/theme_mode.dart. */
export function ThemeSelect() {
  const theme = useTheme();
  return (
    <Segmented<Theme>
      label="Theme"
      value={theme}
      onChange={apply}
      options={[
        { value: 'system', label: 'System' },
        { value: 'light', label: 'Light' },
        { value: 'dark', label: 'Dark' },
      ]}
    />
  );
}

/** One-tap cycle for the header. */
export function ThemeToggle() {
  const theme = useTheme();
  const next: Theme = theme === 'system' ? 'light' : theme === 'light' ? 'dark' : 'system';
  const icon = theme === 'light' ? 'sun' : theme === 'dark' ? 'moon' : 'monitor';

  return (
    <button
      type="button"
      onClick={() => apply(next)}
      className="rounded-lg p-2 text-ink-muted hover:bg-recessed hover:text-ink"
      aria-label={`Theme: ${theme}. Switch to ${next}.`}
      title={`Theme: ${theme}`}
    >
      <Icon name={icon} />
    </button>
  );
}

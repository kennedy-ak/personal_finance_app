import { useId } from 'react';

/** The app name, as in lib/app.dart and the Android launcher label. */
export const APP_NAME = 'Pursely';

/**
 * The Pursely mark — a straight port of lib/shared/widgets/app_logo.dart
 * (same 100-unit geometry: gradient tile, three rising bars, arrow).
 */
export function LogoMark({ size = 32, className }: { size?: number; className?: string }) {
  const id = useId();
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      className={className}
      role="img"
      aria-label={APP_NAME}
    >
      <defs>
        <linearGradient id={`${id}-bg`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#0E7C66" />
          <stop offset="1" stopColor="#14B8A6" />
        </linearGradient>
        <radialGradient id={`${id}-glow`} cx="78" cy="22" r="55" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#fff" stopOpacity="0.18" />
          <stop offset="1" stopColor="#fff" stopOpacity="0" />
        </radialGradient>
      </defs>
      <rect width="100" height="100" rx="26" fill={`url(#${id}-bg)`} />
      <rect width="100" height="100" rx="26" fill={`url(#${id}-glow)`} />
      <g fill="#fff">
        <rect x="22" y="56" width="11" height="18" rx="4.95" />
        <rect x="40" y="44" width="11" height="30" rx="4.95" />
        <rect x="58" y="28" width="11" height="46" rx="4.95" />
        <path d="M63.5 17 L70.5 24 L62.1 25.4 Z" />
        <circle cx="27.5" cy="52" r="3.8" />
        <circle cx="45.5" cy="40" r="3.8" />
      </g>
      <path
        d="M27.5 52 L45.5 40 L63.5 24"
        fill="none"
        stroke="#fff"
        strokeWidth="5.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function Wordmark({ size = 32 }: { size?: number }) {
  return (
    <span className="flex items-center gap-2.5">
      <LogoMark size={size} />
      <span className="font-semibold tracking-tight text-ink" style={{ fontSize: size * 0.53 }}>
        {APP_NAME}
      </span>
    </span>
  );
}

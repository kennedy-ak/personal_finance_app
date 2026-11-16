import type { Metadata, Viewport } from 'next';
import { IBM_Plex_Mono, Inter_Tight } from 'next/font/google';
import { Providers } from '@/components/providers';
import './globals.css';

const interTight = Inter_Tight({ variable: '--font-inter-tight', subsets: ['latin'] });
const plexMono = IBM_Plex_Mono({
  variable: '--font-plex-mono',
  subsets: ['latin'],
  weight: ['400', '500'],
});

export const metadata: Metadata = {
  title: { default: 'Pursely', template: '%s · Pursely' },
  applicationName: 'Pursely',
  description: 'Your money manager — safe-to-spend, bills, goals and a coach.',
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f6f8f7' },
    { media: '(prefers-color-scheme: dark)', color: '#0f1413' },
  ],
};

/**
 * Applies a saved light/dark choice before first paint so the page never
 * flashes the wrong theme. "system" (the default) leaves it to the OS.
 */
const themeScript = `try{var t=localStorage.getItem('theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}`;

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${interTight.variable} ${plexMono.variable} h-full antialiased`}
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className="min-h-full">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}

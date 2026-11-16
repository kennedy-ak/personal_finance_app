import Link from 'next/link';
import { Wordmark } from '@/components/logo';

export default function AuthLayout({ children }: LayoutProps<'/'>) {
  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm">
        <Link href="/login" className="mb-8 inline-flex">
          <Wordmark size={36} />
        </Link>
        {children}
      </div>
    </main>
  );
}

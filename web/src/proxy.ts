import { NextResponse, type NextRequest } from 'next/server';

/**
 * Mirrors the Flutter router's guard (lib/core/router.dart):
 *   signed out + app route   -> /welcome the first time, then /login
 *   signed in  + auth route  -> /
 *
 * "Signed in" here means the `pf_signed_in` marker cookie the API client sets
 * alongside the bearer token. An optimistic check only — the token itself
 * lives in localStorage and every API call is authorised server-side, so a
 * forged cookie gets an empty app, not someone else's data.
 */

/** Must match SIGNED_IN_COOKIE in lib/api/client.ts (not imported — that
 * module is client-only and this runs in the proxy runtime). */
const SIGNED_IN_COOKIE = 'pf_signed_in';

const AUTH_ROUTES = ['/welcome', '/login', '/signup', '/forgot-password'];

/** Reachable either way: changing a password works signed in or out. */
const OPEN_ROUTES = ['/auth/update-password', '/auth/callback'];

export function proxy(request: NextRequest) {
  const signedIn = request.cookies.get(SIGNED_IN_COOKIE)?.value === '1';

  const path = request.nextUrl.pathname;
  const isAuthRoute = AUTH_ROUTES.includes(path);
  const isOpenRoute = OPEN_ROUTES.some((r) => path.startsWith(r));

  if (!signedIn && !isAuthRoute && !isOpenRoute) {
    // First visit sees the welcome screen once, like the app's splash.
    const seenSplash = request.cookies.get('seen_splash')?.value === '1';
    return redirectTo(request, seenSplash ? '/login' : '/welcome');
  }
  if (signedIn && isAuthRoute) {
    return redirectTo(request, '/');
  }
  return NextResponse.next({ request });
}

function redirectTo(request: NextRequest, to: string) {
  const url = request.nextUrl.clone();
  url.pathname = to;
  url.search = '';
  return NextResponse.redirect(url);
}

export const config = {
  // Everything except static assets and images.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)'],
};

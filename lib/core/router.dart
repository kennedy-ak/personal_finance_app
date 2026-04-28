import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/presentation/accounts_screen.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/signup_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/insights/presentation/ai_history_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/onboarding/data/onboarding_store.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/transactions/presentation/add_transaction_screen.dart';
import '../features/transactions/presentation/history_screen.dart';
import '../shared/widgets/home_shell.dart';
import 'supabase_client.dart';

final routerProvider = Provider<GoRouter>((ref) {
  ref.watch(authStateProvider);
  ref.watch(splashSeenProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefresh(ref),
    redirect: (ctx, state) {
      final session = supabase.auth.currentSession;
      final loggedIn = session != null;
      final seenSplash = ref.read(splashSeenProvider);
      final loc = state.matchedLocation;
      final atSplash = loc == '/splash';
      final atAuth = loc == '/login' || loc == '/signup';
      if (!loggedIn && !seenSplash && !atSplash) return '/splash';
      if (!loggedIn && seenSplash && !atAuth) return '/login';
      if (loggedIn && (atAuth || atSplash)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/add', builder: (_, __) => const AddTransactionScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/ai-history', builder: (_, __) => const AiHistoryScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/insights', builder: (_, __) => const InsightsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/accounts', builder: (_, __) => const AccountsScreen()),
          ]),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route error: ${state.error}')),
    ),
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}

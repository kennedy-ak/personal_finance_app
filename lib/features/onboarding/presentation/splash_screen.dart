import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/app_logo.dart';
import '../data/onboarding_store.dart';

/// One claim, one mark, two ways in.
///
/// The old splash sold three features on a green gradient. Nobody reads a
/// feature list before signing up, and the gradient was the loudest thing in
/// the app. What is left is the promise the product actually makes.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  late final Animation<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _leave(String route) async {
    await ref.read(onboardingStoreProvider).markSeen();
    ref.read(splashSeenProvider.notifier).state = true;
    if (mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _rise,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Hero(tag: 'app-logo', child: AppLogo(size: 56)),
                        const SizedBox(height: 26),
                        Text(
                          'Know what you can spend.',
                          style: AppType.displayLarge.copyWith(color: t.ink),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'Pursely reads your accounts, your bills and your '
                            'payday, then gives you one number.',
                            style: AppType.body.copyWith(
                              fontSize: 16,
                              height: 1.55,
                              color: t.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PrimaryButton(
                    label: 'Get started',
                    onPressed: () => _leave('/signup'),
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: 'I have an account',
                    onPressed: () => _leave('/login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

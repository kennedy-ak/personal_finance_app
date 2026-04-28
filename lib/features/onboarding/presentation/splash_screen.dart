import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/app_logo.dart';
import '../data/onboarding_store.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final AnimationController _contentCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _logoCtrl,
    curve: Curves.elasticOut,
  );

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _logoCtrl,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
  );

  late final Animation<Offset> _contentSlide = Tween<Offset>(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut));

  late final Animation<double> _contentFade =
      CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _contentCtrl.forward();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    await ref.read(onboardingStoreProvider).markSeen();
    ref.read(splashSeenProvider.notifier).state = true;
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.gradStart, AppColors.gradEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: const Hero(
                      tag: 'app-logo',
                      child: AppLogo(size: 110),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: const Column(
                      children: [
                        Text(
                          'Pursely',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Track. Plan. Grow.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Feature(
                          icon: Icons.bolt,
                          title: 'Log in seconds',
                          body: 'Quick-add chips and one-tap categories.',
                        ),
                        SizedBox(height: 14),
                        _Feature(
                          icon: Icons.insights,
                          title: 'See where it goes',
                          body: 'Smart reports and charts of your real spending.',
                        ),
                        SizedBox(height: 14),
                        _Feature(
                          icon: Icons.auto_awesome,
                          title: 'AI money coach',
                          body: 'Personalised tips grounded in your numbers.',
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _contentFade,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.seed,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _continue,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Get started'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Feature({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 2),
              Text(body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.35,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

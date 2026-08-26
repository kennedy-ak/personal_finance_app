import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'features/categories/data/category_repository.dart';

class PersonalFinanceApp extends ConsumerWidget {
  const PersonalFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Warms the category list and keeps custom icons resolvable everywhere.
    ref.watch(categoryIconSyncProvider);
    return MaterialApp.router(
      title: 'Pursely',
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Most screens no longer have an app bar to carry this, and the status
      // bar reading black on a #0F1413 canvas is the kind of detail people
      // notice without being able to name.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: CediTokens.dark.navBar,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: CediTokens.light.navBar,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/notifications.dart';
import 'core/theme_mode.dart';
import 'features/onboarding/data/onboarding_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  await NotificationService().init();

  final seenSplash = await OnboardingStore().seen();
  final themeMode = await ThemeModeStore().load();

  runApp(ProviderScope(
    overrides: [
      splashSeenProvider.overrideWith((_) => seenSplash),
      initialThemeModeProvider.overrideWith((_) => themeMode),
    ],
    child: const PersonalFinanceApp(),
  ));
}

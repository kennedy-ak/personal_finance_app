import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/notifications.dart';
import 'core/theme_mode.dart';
import 'features/onboarding/data/onboarding_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await ApiClient.instance.init(
    baseUrl: dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000',
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeenSplash = 'seen_splash';

class OnboardingStore {
  Future<bool> seen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSeenSplash) ?? false;
  }

  Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSeenSplash, true);
  }
}

/// Initial value loaded from prefs in main() and overridden in ProviderScope.
final splashSeenProvider = StateProvider<bool>((_) => true);

final onboardingStoreProvider = Provider((_) => OnboardingStore());

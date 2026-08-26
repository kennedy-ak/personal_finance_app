import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeMode = 'theme_mode';

/// Remembers the light / dark / system choice across launches.
class ThemeModeStore {
  Future<ThemeMode> load() async {
    final p = await SharedPreferences.getInstance();
    return decode(p.getString(_kThemeMode));
  }

  Future<void> save(ThemeMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, encode(mode));
  }

  static String encode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode decode(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeStoreProvider = Provider((_) => ThemeModeStore());

/// Initial value loaded from prefs in main() and overridden in ProviderScope,
/// so the first frame already paints in the chosen theme.
final initialThemeModeProvider = Provider<ThemeMode>((_) => ThemeMode.system);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> set(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await ref.read(themeModeStoreProvider).save(mode);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

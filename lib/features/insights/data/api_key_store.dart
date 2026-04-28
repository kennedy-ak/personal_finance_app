import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'openai_api_key';
const _kModel = 'openai_model';

String? _envKey() {
  final v = dotenv.maybeGet('OPENAI_API_KEY');
  return (v == null || v.isEmpty) ? null : v;
}

String _envModel() {
  final v = dotenv.maybeGet('OPENAI_MODEL');
  return (v == null || v.isEmpty) ? 'gpt-4o-mini' : v;
}

class ApiKeyStore {
  /// User's personal key, if they set one; otherwise the bundled .env key.
  Future<String?> getKey() async {
    final p = await SharedPreferences.getInstance();
    final user = p.getString(_kKey);
    if (user != null && user.isNotEmpty) return user;
    return _envKey();
  }

  Future<String> getModel() async {
    final p = await SharedPreferences.getInstance();
    final user = p.getString(_kModel);
    if (user != null && user.isNotEmpty) return user;
    return _envModel();
  }

  Future<bool> isUserKey() async {
    final p = await SharedPreferences.getInstance();
    final user = p.getString(_kKey);
    return user != null && user.isNotEmpty;
  }

  Future<void> setKey(String key) async {
    final p = await SharedPreferences.getInstance();
    if (key.isEmpty) {
      await p.remove(_kKey);
    } else {
      await p.setString(_kKey, key);
    }
  }

  Future<void> setModel(String model) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModel, model);
  }
}

final apiKeyStoreProvider = Provider((_) => ApiKeyStore());

final apiKeyProvider = FutureProvider<String?>((ref) async {
  ref.watch(apiKeyRefreshProvider);
  return ref.read(apiKeyStoreProvider).getKey();
});

final modelProvider = FutureProvider<String>((ref) async {
  ref.watch(apiKeyRefreshProvider);
  return ref.read(apiKeyStoreProvider).getModel();
});

final apiKeyRefreshProvider = StateProvider<int>((_) => 0);

void bumpApiKey(WidgetRef ref) =>
    ref.read(apiKeyRefreshProvider.notifier).state++;

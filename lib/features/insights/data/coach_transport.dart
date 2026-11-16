import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_client.dart';
import 'api_key_store.dart';

class CoachException implements Exception {
  final String message;
  CoachException(this.message);
  @override
  String toString() => message;
}

/// How a request reaches the model. Swapped out wholesale in tests.
abstract class CoachTransport {
  /// Sends the conversation and returns the provider's raw choice message.
  Future<Map<String, dynamic>> complete({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  });

  /// Shown in settings so the user knows which path is live.
  String get label;
}

/// The intended path: the key lives on the server, not on the phone.
/// POST /coach/complete on the FastAPI backend — the Edge Function's successor.
class ServerCoachTransport implements CoachTransport {
  final ApiClient client;

  ServerCoachTransport({ApiClient? client}) : client = client ?? api;

  @override
  String get label => 'Server (FastAPI backend)';

  @override
  Future<Map<String, dynamic>> complete({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async {
    final dynamic data;
    try {
      data = await client.post('/coach/complete', body: {
        'messages': messages,
        'tools': ?tools,
      });
    } on ApiException catch (e) {
      throw CoachException(e.message);
    }

    if (data is! Map) {
      throw CoachException('The coach returned an unexpected response.');
    }
    return _firstMessage(Map<String, dynamic>.from(data));
  }
}

/// Fallback for when the backend has no OPENAI_API_KEY: the old per-user key,
/// read from the device.
///
/// Kept so upgrading the app never leaves someone without a working coach. It
/// is not the destination — the key sitting on the phone is exactly what the
/// server path exists to fix.
class DirectKeyTransport implements CoachTransport {
  final String apiKey;
  final String model;
  final http.Client httpClient;

  DirectKeyTransport({
    required this.apiKey,
    this.model = 'gpt-4o-mini',
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  @override
  String get label => 'This device (your own API key)';

  @override
  Future<Map<String, dynamic>> complete({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async {
    final res = await httpClient.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0.4,
        'max_tokens': 900,
        'messages': messages,
        if (tools != null && tools.isNotEmpty) ...{
          'tools': tools,
          'tool_choice': 'auto',
        },
      }),
    );

    if (res.statusCode != 200) {
      var message = 'Model error (${res.statusCode})';
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['error'] is Map && j['error']['message'] is String) {
          message = j['error']['message'] as String;
        }
      } catch (_) {
        // keep the generic message
      }
      throw CoachException(message);
    }

    return _firstMessage(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

/// Prefers the server, drops back to the on-device key if the backend has no
/// model key configured.
///
/// The fallback is deliberately one-way and sticky for the session: once the
/// server has answered, we never quietly start billing the user's own key.
class FallbackTransport implements CoachTransport {
  final CoachTransport primary;
  final CoachTransport? secondary;

  bool _primaryFailed = false;

  FallbackTransport({required this.primary, required this.secondary});

  @override
  String get label =>
      _primaryFailed && secondary != null ? secondary!.label : primary.label;

  @override
  Future<Map<String, dynamic>> complete({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async {
    if (_primaryFailed && secondary != null) {
      return secondary!.complete(messages: messages, tools: tools);
    }

    try {
      return await primary.complete(messages: messages, tools: tools);
    } on CoachException catch (e) {
      if (secondary == null) rethrow;
      debugPrint('Coach: server path failed ($e), falling back to local key.');
      _primaryFailed = true;
      return secondary!.complete(messages: messages, tools: tools);
    }
  }
}

/// Pulls the assistant message out of a chat-completions response.
Map<String, dynamic> _firstMessage(Map<String, dynamic> body) {
  if (body['error'] is String) {
    throw CoachException(body['error'] as String);
  }

  final choices = body['choices'];
  if (choices is! List || choices.isEmpty) {
    throw CoachException('The coach returned an empty response.');
  }

  final message = (choices.first as Map)['message'];
  if (message is! Map) {
    throw CoachException('The coach returned a malformed response.');
  }
  return Map<String, dynamic>.from(message);
}

/// The transport the app should use right now.
final coachTransportProvider = FutureProvider<CoachTransport>((ref) async {
  final store = ref.watch(apiKeyStoreProvider);
  final key = await store.getKey();
  final model = await store.getModel();

  return FallbackTransport(
    primary: ServerCoachTransport(),
    secondary: key == null || key.isEmpty
        ? null
        : DirectKeyTransport(apiKey: key, model: model),
  );
});

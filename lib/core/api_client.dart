import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in user as the backend describes them (`/auth/me`).
class AppUser {
  final String id;
  final String email;
  final String? fullName;

  const AppUser({required this.id, required this.email, this.fullName});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'email': email, 'full_name': fullName};
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

/// The one way the app talks to the FastAPI backend.
///
/// Replaces the Supabase client: it holds the bearer token (persisted in
/// SharedPreferences so a restart stays signed in), exposes the signed-in
/// user, and broadcasts auth changes for the router to react to.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _kToken = 'api_token';
  static const _kUser = 'api_user';

  late String baseUrl;
  String? _token;
  AppUser? _user;
  final _authChanges = StreamController<AppUser?>.broadcast();
  final http.Client _http = http.Client();

  Future<void> init({required String baseUrl}) async {
    this.baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    final stored = prefs.getString(_kUser);
    if (stored != null) {
      try {
        _user = AppUser.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
  }

  bool get isSignedIn => _token != null;
  AppUser? get currentUser => _user;
  Stream<AppUser?> get authStateChanges => _authChanges.stream;

  // ---------------------------------------------------------------- auth

  Future<AppUser> signIn({required String email, required String password}) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  Future<AppUser> signUp({
    required String email,
    required String password,
    String? fullName,
  }) =>
      _authenticate('/auth/signup', {
        'email': email,
        'password': password,
        if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
      });

  Future<AppUser> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await post(path, body: body) as Map<String, dynamic>;
    _token = data['token'] as String;
    _user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, _token!);
    await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
    _authChanges.add(_user);
    return _user!;
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    _authChanges.add(null);
  }

  // ---------------------------------------------------------------- http

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: query?.isEmpty ?? true ? null : query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await _http.send(request);
    } catch (e) {
      throw ApiException(
          0, 'Could not reach the server at $baseUrl. Is the backend running?');
    }
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 401 && _token != null && path != '/auth/login') {
      // The token expired or the account is gone — drop to the login screen
      // rather than failing every request quietly.
      await signOut();
    }

    final text = utf8.decode(res.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _describe(decoded, res.statusCode));
    }
    return decoded;
  }

  String _describe(dynamic decoded, int status) {
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        // FastAPI validation errors.
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return first['msg'] as String;
        }
      }
    }
    return 'The server answered with an error ($status).';
  }
}

/// Shorthand the repositories use, mirroring the old `supabase` getter.
ApiClient get api => ApiClient.instance;

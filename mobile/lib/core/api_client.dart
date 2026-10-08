import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient(this._supabase, {http.Client? httpClient, this._tokenProvider})
      : _http = httpClient ?? http.Client();
  final SupabaseClient? _supabase;
  final http.Client _http;
  final String? Function()? _tokenProvider;

  String? get _effectiveToken => _tokenProvider?.call() ?? _supabase?.auth.currentSession?.accessToken;

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool requireAuth = true}) async {
    final token = _effectiveToken;
    final isDevAuthPath = path.startsWith('/dev/auth/');
    if (requireAuth && !isDevAuthPath && token == null) {
      throw ApiException(401, 'Sign in required');
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _http.post(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, decoded['message']?.toString() ?? 'Request failed');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body, {bool requireAuth = true}) async {
    final token = _effectiveToken;
    if (requireAuth && token == null) {
      throw ApiException(401, 'Sign in required');
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _http.patch(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, decoded['message']?.toString() ?? 'Request failed');
    }
    return decoded;
  }

  Future<dynamic> get(String path, {bool requireAuth = true}) async {
    final token = _effectiveToken;
    if (requireAuth && token == null) {
      throw ApiException(401, 'Sign in required');
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _http.get(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      headers: headers,
    );
    final decoded = response.body.isEmpty ? <dynamic>[] : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = decoded is Map ? decoded['message']?.toString() : null;
      throw ApiException(response.statusCode, msg ?? 'Request failed');
    }
    return decoded;
  }
}


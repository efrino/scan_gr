import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dilempar ketika server mengembalikan 401 Unauthorized.
class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

/// Dilempar ketika server mengembalikan bukan JSON (misal HTML 404/500).
/// [statusCode] berisi HTTP status code, [body] berisi awal response body.
class ApiResponseException implements Exception {
  final int statusCode;
  final String body;
  const ApiResponseException(this.statusCode, this.body);

  @override
  String toString() =>
      'ApiResponseException: HTTP $statusCode\n${body.substring(0, body.length.clamp(0, 200))}';
}

/// Klien HTTP terpusat.
/// - Menyisipkan Bearer token secara otomatis.
/// - Jika respons 401, sesi dibersihkan dan navigator diarahkan ke /login.
/// - Jika respons bukan JSON (HTML), melempar ApiResponseException.
/// - Menggunakan IOClient dengan badCertificateCallback untuk menangani
///   sertifikat SSL yang kedaluwarsa di server.
class ApiClient {
  ApiClient._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  // HTTP client yang melewati verifikasi sertifikat SSL yang kedaluwarsa.
  static final http.Client _client = IOClient(
    HttpClient()..badCertificateCallback = (cert, host, port) => true,
  );

  // ── Unauthenticated POST (login) ──────────────────────────────────────────

  static Future<http.Response> postNoAuth(Uri uri, {Object? body}) async {
    debugPrint('[ApiClient] POST (no-auth) → $uri');
    debugPrint('[ApiClient]   body: $body');
    final response = await _client.post(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    debugPrint('[ApiClient] ← ${response.statusCode} | ${uri.path}');
    debugPrint('[ApiClient]   body: ${response.body}');
    _assertJson(response);
    return response;
  }

  // ── Token helpers ─────────────────────────────────────────────────────────

  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    debugPrint(
      '[ApiClient] token: ${token.isEmpty ? "(kosong)" : "${token.substring(0, token.length.clamp(0, 12))}..."}',
    );
    return token;
  }

  static Future<void> _clearSession() async {
    debugPrint('[ApiClient] ⚠ 401 – menghapus sesi lokal');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('username');
    await prefs.remove('email');
    await prefs.remove('company');
    await prefs.remove('nik');
  }

  static void _redirectToLogin() {
    debugPrint('[ApiClient] → redirect ke /login');
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ── GET ───────────────────────────────────────────────────────────────────

  static Future<http.Response> get(Uri uri) async {
    final token = await _token();
    debugPrint('[ApiClient] GET → $uri');
    final response = await _client.get(uri, headers: _headers(token));
    debugPrint('[ApiClient] ← ${response.statusCode} | ${uri.path}');
    debugPrint('[ApiClient]   body: ${response.body}');

    if (response.statusCode == 401) {
      await _clearSession();
      _redirectToLogin();
      throw const UnauthorizedException();
    }

    // Jika server return HTML (404/500 page), lempar exception khusus
    _assertJson(response);

    return response;
  }

  // ── POST ──────────────────────────────────────────────────────────────────

  static Future<http.Response> post(Uri uri, {Object? body}) async {
    final token = await _token();
    debugPrint('[ApiClient] POST → $uri');
    debugPrint('[ApiClient]   body: $body');
    final response = await _client.post(
      uri,
      headers: _headers(token),
      body: body,
    );
    debugPrint('[ApiClient] ← ${response.statusCode} | ${uri.path}');
    debugPrint('[ApiClient]   body: ${response.body}');

    if (response.statusCode == 401) {
      await _clearSession();
      _redirectToLogin();
      throw const UnauthorizedException();
    }

    _assertJson(response);

    return response;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Melempar [ApiResponseException] jika body terlihat seperti HTML.
  /// Server yang mengembalikan 404/500 HTML akan ter-detect di sini,
  /// bukan crash saat jsonDecode.
  static void _assertJson(http.Response response) {
    final body = response.body.trimLeft();
    final looksLikeHtml =
        body.startsWith('<') || body.toLowerCase().startsWith('<!doctype');
    if (looksLikeHtml) {
      debugPrint(
        '[ApiClient] ✗ Response bukan JSON! HTTP ${response.statusCode} – body dimulai dengan HTML',
      );
      throw ApiResponseException(response.statusCode, response.body);
    }
  }

  static Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
}

import 'dart:async';
import 'dart:io';
import '../constants/api_constants.dart';
import 'notification_service.dart';
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
  static http.Client _client = IOClient(
    HttpClient()..badCertificateCallback = (cert, host, port) => true,
  );

  @visibleForTesting
  static set client(http.Client c) => _client = c;

  @visibleForTesting
  static void resetFallbackState() => _primaryDownUntil = null;

  // ── Unauthenticated POST (login) ──────────────────────────────────────────

  static Future<http.Response> postNoAuth(Uri uri, {Object? body}) async {
    // Body tidak dicatat: berisi password login.
    final response = await _withFallback(
      'POST (no-auth)',
      uri,
      (u) => _client.post(
        u,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: body,
      ),
    );
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

  /// Diset saat sesi dicabut server (401) supaya halaman login bisa
  /// menjelaskan alasannya. Direset oleh halaman login.
  static bool sessionExpired = false;

  static void _redirectToLogin() {
    debugPrint('[ApiClient] → redirect ke /login');
    sessionExpired = true;
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ── GET ───────────────────────────────────────────────────────────────────

  static Future<http.Response> get(Uri uri) async {
    final token = await _token();
    final response = await _withFallback(
      'GET',
      uri,
      (u) => _client.get(u, headers: _headers(token)),
    );

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

  /// POST tidak idempoten: jika server utama timeout atau 5xx, request bisa saja
  /// sudah diproses (mis. GR ke SAP), jadi tidak diulang ke server lokal.
  /// Pindah ke server lokal hanya jika server utama tidak terjangkau.
  /// [timeout] untuk endpoint lambat seperti scan-labelbox yang menunggu SAP.
  static Future<http.Response> post(
    Uri uri, {
    Object? body,
    Duration timeout = postTimeout,
  }) async {
    final token = await _token();
    debugPrint('[ApiClient]   body: $body');
    final response = await _withFallback(
      'POST',
      uri,
      (u) => _client.post(u, headers: _headers(token), body: body),
      idempotent: false,
      primaryTimeout: timeout,
      fallbackTimeout: timeout,
    );

    if (response.statusCode == 401) {
      await _clearSession();
      _redirectToLogin();
      throw const UnauthorizedException();
    }

    _assertJson(response);

    return response;
  }

  // ── Fallback server ───────────────────────────────────────────────────────

  /// Batas waktu per server. Total (utama + lokal) harus di bawah timeout
  /// pemanggil (GET 15 detik, POST 20 detik di ScanPage).
  static const _primaryTimeout = Duration(seconds: 6);
  static const _fallbackTimeout = Duration(seconds: 8);

  /// Batas waktu POST bawaan. Endpoint yang menunggu SAP bisa lebih dari 10 detik.
  static const postTimeout = Duration(seconds: 45);

  /// Setelah server utama gagal, request berikutnya langsung ke server lokal
  /// selama durasi ini. Tanpa ini, tiap request (termasuk tiap item antrian)
  /// harus menunggu timeout server utama dulu.
  static const _primaryCooldown = Duration(seconds: 60);
  static DateTime? _primaryDownUntil;

  /// Kirim ke server utama dulu. Jika gagal jaringan, timeout, atau 5xx,
  /// ulangi request yang sama ke server lokal. Untuk request tidak idempoten
  /// hanya gagal jaringan yang diulang; timeout dan 5xx dikembalikan ke pemanggil.
  static Future<http.Response> _withFallback(
    String method,
    Uri uri,
    Future<http.Response> Function(Uri) send, {
    bool idempotent = true,
    Duration primaryTimeout = _primaryTimeout,
    Duration fallbackTimeout = _fallbackTimeout,
  }) async {
    final fallbackUri = _toFallback(uri);
    final skipPrimary =
        fallbackUri != null &&
        _primaryDownUntil != null &&
        DateTime.now().isBefore(_primaryDownUntil!);

    if (!skipPrimary) {
      try {
        debugPrint('[ApiClient] $method → $uri');
        final response = await send(uri).timeout(primaryTimeout);
        _logResponse(response, uri);
        if (response.statusCode < 500 || fallbackUri == null || !idempotent) {
          _primaryDownUntil = null;
          return response;
        }
        debugPrint(
          '[ApiClient] ⚠ server utama ${response.statusCode}, coba server lokal',
        );
      } on SocketException catch (e) {
        if (fallbackUri == null) rethrow;
        debugPrint(
          '[ApiClient] ⚠ server utama tidak terjangkau ($e), coba server lokal',
        );
      } on TimeoutException {
        if (fallbackUri == null || !idempotent) rethrow;
        debugPrint('[ApiClient] ⚠ server utama timeout, coba server lokal');
      } on http.ClientException catch (e) {
        if (fallbackUri == null) rethrow;
        debugPrint('[ApiClient] ⚠ server utama error ($e), coba server lokal');
      }
      _primaryDownUntil = DateTime.now().add(_primaryCooldown);
    }

    debugPrint('[ApiClient] $method (lokal) → $fallbackUri');
    final response = await send(fallbackUri).timeout(fallbackTimeout);
    _logResponse(response, fallbackUri);
    return response;
  }

  /// Ganti prefix server utama dengan server lokal. Null jika uri bukan
  /// milik server utama.
  static Uri? _toFallback(Uri uri) {
    final url = uri.toString();
    if (!url.startsWith(ApiConstants.baseUrl)) return null;
    return Uri.parse(
      ApiConstants.fallbackBaseUrl + url.substring(ApiConstants.baseUrl.length),
    );
  }

  /// Build terbaru yang diumumkan server lewat header `X-App-Latest-Build`
  /// di setiap respons API. UpdateGate memantau ini untuk cek update seketika.
  static final ValueNotifier<int> latestBuild = ValueNotifier(0);

  static void _logResponse(http.Response response, Uri uri) {
    debugPrint('[ApiClient] ← ${response.statusCode} | ${uri.host}${uri.path}');
    debugPrint('[ApiClient]   body: ${response.body}');
    final build = int.tryParse(response.headers['x-app-latest-build'] ?? '');
    if (build != null && build > latestBuild.value) latestBuild.value = build;
    // `X-System-Status: sap=down|ok` hanya ada di respons yang lewat filter token.
    final status = response.headers['x-system-status'];
    if (status != null) {
      NotificationService.applySapStatus(
        status.contains('sap=down') ? 'down' : 'ok',
        null,
      );
    }
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import 'api_client.dart';

/// Info versi dari `GET api/app/version`.
class AppVersionInfo {
  final int versionCode;
  final String versionName;
  final int minVersionCode;
  final String apkUrl;
  final String? apkUrlLocal;
  final int? apkSize;
  final String? apkSha256;
  final String? releaseNotes;

  const AppVersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.minVersionCode,
    required this.apkUrl,
    this.apkUrlLocal,
    this.apkSize,
    this.apkSha256,
    this.releaseNotes,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
    versionCode: (j['version_code'] as num).toInt(),
    versionName: j['version_name'].toString(),
    minVersionCode: (j['min_version_code'] as num).toInt(),
    apkUrl: j['apk_url'].toString(),
    apkUrlLocal: (j['apk_url_local'] as String?)?.trim().isEmpty ?? true
        ? null
        : j['apk_url_local'] as String,
    apkSize: (j['apk_size'] as num?)?.toInt(),
    apkSha256: j['apk_sha256'] as String?,
    releaseNotes: j['release_notes'] as String?,
  );

  /// Urutan sumber unduhan: GitHub dulu, lalu server sendiri lewat domain,
  /// lalu server sendiri lewat IP LAN (jika internet putus).
  List<String> get downloadUrls {
    final urls = <String>[apkUrl];
    final local = apkUrlLocal;
    if (local != null) {
      urls.add(local);
      final primaryRoot = _root(ApiConstants.baseUrl);
      if (local.startsWith(primaryRoot)) {
        urls.add(
          _root(ApiConstants.fallbackBaseUrl) +
              local.substring(primaryRoot.length),
        );
      }
    }
    return urls.toSet().toList();
  }

  /// `https://host/portal-supplier/public/api` → `https://host/portal-supplier/public`
  static String _root(String apiBase) => apiBase.endsWith('/api')
      ? apiBase.substring(0, apiBase.length - 4)
      : apiBase;
}

enum UpdateKind {
  /// Versi terpasang sama atau lebih baru dari production. Tidak ada aksi.
  none,

  /// Ada versi production lebih baru, user boleh menunda.
  optional,

  /// Versi terpasang di bawah `min_version_code`, wajib update.
  required,
}

class UpdateCheckResult {
  final UpdateKind kind;
  final int installedCode;
  final String installedName;
  final AppVersionInfo? latest;

  const UpdateCheckResult(
    this.kind,
    this.installedCode,
    this.installedName,
    this.latest,
  );
}

/// Cek versi aplikasi dan unduh + pasang APK terbaru.
///
/// Aturan versi (berdasarkan `version_code`, angka setelah `+` di pubspec):
/// - terpasang < `min_version_code`  → wajib update.
/// - terpasang < `version_code`      → update opsional.
/// - terpasang >= `version_code`     → tidak ada aksi. Android tidak bisa
///   menurunkan versi tanpa uninstall (antrian scan ikut terhapus), jadi
///   rollback dirilis ulang sebagai build dengan `version_code` LEBIH TINGGI,
///   misalnya kode 3.3 dirilis sebagai `3.3.1+35`.
class AppUpdateService {
  AppUpdateService._();

  /// Jeda minimum antar cek otomatis (saat app dibuka / resume).
  static const checkInterval = Duration(minutes: 30);

  static DateTime? _lastCheck;

  static Future<UpdateCheckResult?> check({bool ignoreInterval = false}) async {
    final now = DateTime.now();
    if (!ignoreInterval &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < checkInterval) {
      return null;
    }
    _lastCheck = now;

    try {
      final pkg = await PackageInfo.fromPlatform();
      final installed = int.tryParse(pkg.buildNumber) ?? 0;

      final uri = Uri.parse('${ApiConstants.baseUrl}/app/version').replace(
        queryParameters: {
          'platform': 'android',
          'current_version_code': '$installed',
          'current_version_name': pkg.version,
          ...await _deviceParams(),
        },
      );
      final res = await ApiClient.get(uri);
      final body = jsonDecode(res.body);
      if (body is! Map || body['status'] != true || body['data'] is! Map) {
        debugPrint('[AppUpdate] versi tidak tersedia (HTTP ${res.statusCode})');
        return null;
      }

      final latest = AppVersionInfo.fromJson(
        Map<String, dynamic>.from(body['data']),
      );
      final kind = installed < latest.minVersionCode
          ? UpdateKind.required
          : installed < latest.versionCode
          ? UpdateKind.optional
          : UpdateKind.none;

      debugPrint(
        '[AppUpdate] terpasang=$installed (${pkg.version}) | '
        'production=${latest.versionCode} (${latest.versionName}) | '
        'min=${latest.minVersionCode} → $kind',
      );
      return UpdateCheckResult(kind, installed, pkg.version, latest);
    } catch (e) {
      // Offline / server error: app tetap jalan normal, coba lagi nanti.
      debugPrint('[AppUpdate] cek versi gagal: $e');
      _lastCheck = null;
      return null;
    }
  }

  // ── Identitas device (statistik versi di CMS) ────────────────────────────

  static const _deviceIdKey = 'app_device_id';

  /// `device_id` acak dibuat sekali lalu disimpan; ikut terhapus jika app
  /// di-uninstall. Ditambah NIK user yang login dan model device.
  static Future<Map<String, String>> _deviceParams() async {
    final params = <String, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id == null) {
        final rnd = Random.secure();
        id = List.generate(
          16,
          (_) => rnd.nextInt(256),
        ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await prefs.setString(_deviceIdKey, id);
      }
      params['device_id'] = id;

      final nik = prefs.getString('nik');
      if (nik != null && nik.isNotEmpty) params['nik'] = nik;

      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        params['device_model'] = '${info.manufacturer} ${info.model}'.trim();
      }
    } catch (e) {
      debugPrint('[AppUpdate] info device tidak lengkap: $e');
    }
    return params;
  }

  // ── Download ──────────────────────────────────────────────────────────────

  /// Batas tanpa data masuk sebelum sumber dianggap macet dan pindah ke
  /// sumber berikutnya.
  static const _stallTimeout = Duration(seconds: 20);

  static http.Client _newClient() => IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (cert, host, port) => true,
  );

  /// Unduh APK, coba tiap URL berurutan. [onProgress] menerima 0.0–1.0,
  /// atau null jika ukuran tidak diketahui. Isi file dicek dengan sha256.
  static Future<File> download(
    AppVersionInfo info, {
    void Function(double? progress, String source)? onProgress,
  }) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/update');
    await dir.create(recursive: true);
    final file = File('${dir.path}/scan_gr-${info.versionName}.apk');

    Object? lastError;
    for (final url in info.downloadUrls) {
      final source = Uri.parse(url).host;
      final client = _newClient();
      try {
        debugPrint('[AppUpdate] unduh dari $url');
        final res = await client
            .send(http.Request('GET', Uri.parse(url)))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
        }

        final total = res.contentLength ?? info.apkSize;
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in res.stream.timeout(_stallTimeout)) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(
              total != null && total > 0 ? received / total : null,
              source,
            );
          }
        } finally {
          await sink.close();
        }

        if (info.apkSize != null && received != info.apkSize) {
          throw StateError('ukuran tidak cocok: $received / ${info.apkSize}');
        }
        if (info.apkSha256 != null) {
          final digest = (await sha256.bind(file.openRead()).first).toString();
          if (digest != info.apkSha256!.toLowerCase()) {
            throw StateError('sha256 tidak cocok');
          }
        }

        debugPrint('[AppUpdate] ✓ unduh selesai dari $source ($received B)');
        return file;
      } catch (e) {
        debugPrint('[AppUpdate] ✗ gagal unduh dari $source: $e');
        lastError = e;
        if (await file.exists()) await file.delete();
      } finally {
        client.close();
      }
    }
    throw lastError ?? StateError('tidak ada sumber unduhan');
  }

  /// Buka installer Android. Saat pertama kali, Android meminta izin
  /// "Instal aplikasi tak dikenal" untuk app ini.
  static Future<bool> install(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    debugPrint('[AppUpdate] installer: ${result.type} ${result.message}');
    return result.type == ResultType.done;
  }
}

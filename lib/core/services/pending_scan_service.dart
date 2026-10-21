import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import '../../core/constants/api_constants.dart';

/// Cache lokal untuk scan yang belum terkirim ke server.
///
/// Dua tipe item yang bisa tersimpan:
///   1. [has_labelbox_data = true]  → GET berhasil, POST gagal; punya data lengkap.
///   2. [has_labelbox_data = false] → GET pun gagal (offline total); hanya punya barcode & nik.
///
/// Saat sync, tipe-2 akan GET dulu lalu POST.
/// Deduplication by barcode — satu barcode hanya masuk sekali.
/// SharedPreferences memakai internal app storage, tidak butuh izin storage OS.
class PendingScanService {
  PendingScanService._();

  static const _key = 'pending_scans';
  static bool _syncing = false;

  /// Naik tiap isi cache berubah, supaya halaman yang menampilkan antrian
  /// ikut diperbarui saat sync berjalan di latar belakang.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// Barcode yang POST-nya masih berjalan (mis. dilanjutkan di latar belakang
  /// oleh ScanPage). Dilewati syncAll agar tidak terkirim dua kali.
  static final Set<String> _inFlight = {};

  static bool get isSyncing => _syncing;

  /// Interval sync otomatis selama aplikasi terbuka.
  static const autoSyncInterval = Duration(minutes: 2);
  static Timer? _autoTimer;

  /// Timeout beruntun sebelum sync berhenti; server kemungkinan sedang lambat.
  static const _maxConsecutiveTimeouts = 2;

  // ── Read / Write ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
    changes.value++;
  }

  // ── Add ───────────────────────────────────────────────────────────────────

  /// Simpan scan gagal ke cache lokal.
  /// [labelboxData] boleh null jika GET ikut gagal (offline total) — hanya barcode & nik yg tersimpan.
  /// Tidak menambah duplikat jika barcode sudah ada.
  static Future<void> add({
    required String barcode,
    required String nik,
    String qty = '',
    Map<String, dynamic>? labelboxData,
  }) async {
    final list = await getAll();
    if (list.any((e) => e['barcode'] == barcode)) {
      debugPrint('[PendingScanService] add – barcode=$barcode sudah ada di cache, skip');
      return;
    }

    final entry = <String, dynamic>{
      'barcode': barcode,
      'nik': nik,
      'qty': qty,
      'is_scanned': 'N',
      'is_pending': true,
      'has_labelbox_data': labelboxData != null,
      'cached_at': DateTime.now().toIso8601String(),
    };

    if (labelboxData != null) entry.addAll(labelboxData);

    list.add(entry);
    await _save(list);
    debugPrint('[PendingScanService] add – barcode=$barcode tersimpan (hasLabelbox=${labelboxData != null}) | total cache: ${list.length}');
  }

  // ── Remove ────────────────────────────────────────────────────────────────

  static Future<void> remove(String barcode) async {
    final list = await getAll();
    list.removeWhere((e) => e['barcode'] == barcode);
    await _save(list);
    debugPrint('[PendingScanService] remove – barcode=$barcode | sisa cache: ${list.length}');
  }

  static Future<bool> contains(String barcode) async =>
      (await getAll()).any((e) => e['barcode'] == barcode);

  static Future<int> count() async => (await getAll()).length;

  // ── Background ────────────────────────────────────────────────────────────

  /// Tandai barcode sedang dikirim di luar syncAll, lalu bersihkan cache
  /// sesuai hasil akhirnya. Item tetap di cache jika gagal, untuk dicoba lagi.
  static void track(String barcode, Future<http.Response> request) {
    _inFlight.add(barcode);
    request.then((resp) async {
      if (isDone(resp.body)) {
        debugPrint('[PendingScanService] latar belakang ✓ barcode=$barcode → hapus dari cache');
        await remove(barcode);
      } else {
        debugPrint('[PendingScanService] latar belakang ✗ barcode=$barcode tetap di cache');
      }
    }).catchError((Object e) {
      debugPrint('[PendingScanService] latar belakang ✗ barcode=$barcode: $e');
    }).whenComplete(() => _inFlight.remove(barcode));
  }

  /// Respons POST scan-labelbox dianggap selesai jika berhasil, atau server
  /// menolak karena sudah discan/diproses (request sebelumnya ternyata masuk).
  static bool isDone(String body) {
    try {
      final data = jsonDecode(body);
      final msg = (data['message'] as String? ?? '').toLowerCase();
      return data['success'] == true ||
          data['status'] == true ||
          msg.contains('berhasil') ||
          msg.contains('sudah discan') ||
          msg.contains('sudah diproses');
    } catch (_) {
      return false;
    }
  }

  /// Sync otomatis berkala selama aplikasi di depan. Aman dipanggil berulang.
  static void startAutoSync() {
    _autoTimer ??= Timer.periodic(autoSyncInterval, (_) async {
      // Tanpa sesi, POST pasti 401 dan memaksa buka halaman login berulang.
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString('token') ?? '').isEmpty) return;
      if (await count() > 0) await syncAll();
    });
  }

  static void stopAutoSync() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// Server bisa balas `data` sebagai objek tunggal maupun list berisi satu objek.
  static Map<String, dynamic>? _extractLabelboxData(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
      return raw.first as Map<String, dynamic>;
    }
    return null;
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Kirim pending ke server satu per satu.
  /// Item tanpa labelbox data akan GET dulu lalu POST.
  /// Berhenti jika offline atau 401. Mengembalikan jumlah berhasil dikirim.
  static Future<int> syncAll() async {
    if (_syncing) {
      debugPrint('[PendingScanService] syncAll – sudah berjalan, skip');
      return 0;
    }
    _syncing = true;
    int synced = 0;

    try {
      final list = await getAll();
      if (list.isEmpty) {
        debugPrint('[PendingScanService] syncAll – cache kosong, tidak ada yang disinkronkan');
        return 0;
      }

      debugPrint('[PendingScanService] syncAll – mulai sinkronisasi ${list.length} item');
      var timeouts = 0;

      for (final item in List<Map<String, dynamic>>.from(list)) {
        final barcode = item['barcode'] as String? ?? '';
        if (_inFlight.contains(barcode)) {
          debugPrint('[PendingScanService] sync item barcode=$barcode masih dikirim, lewati');
          continue;
        }
        final nik = item['nik'] as String? ?? '';
        String qty = item['qty'] as String? ?? '';
        final hasLabelboxData = item['has_labelbox_data'] == true;

        debugPrint('[PendingScanService] sync item barcode=$barcode | hasLabelbox=$hasLabelboxData');

        try {
          // ── Tipe 2: tidak punya data labelbox — GET dulu ──────────────────
          if (!hasLabelboxData) {
            debugPrint('[PendingScanService]   GET get-labelbox untuk barcode=$barcode');
            final getUri = Uri.parse('${ApiConstants.baseUrl}/scan/get-labelbox')
                .replace(queryParameters: {'barcode': barcode});
            final getResp = await ApiClient.get(getUri);
            debugPrint('[PendingScanService]   GET ← ${getResp.statusCode}');
            debugPrint('[PendingScanService]   body: ${getResp.body}');
            final getData = jsonDecode(getResp.body);

            final labelbox = _extractLabelboxData(getData['data']);
            if (getData['status'] == true && labelbox != null) {
              final alreadyScanned =
                  (labelbox['is_scanned'] as String?)?.toUpperCase() == 'Y';

              if (alreadyScanned) {
                debugPrint('[PendingScanService]   barcode=$barcode sudah discan orang lain → hapus dari cache');
                await remove(barcode);
                synced++;
                continue;
              }
              qty = labelbox['quantity']?.toString() ?? '';
            } else {
              debugPrint('[PendingScanService]   barcode=$barcode tidak ditemukan di server → hapus dari cache');
              await remove(barcode);
              continue;
            }
          }

          // ── POST ke server ──────────────────────────────────────────────
          debugPrint('[PendingScanService]   POST scan-labelbox barcode=$barcode | nik=$nik | qty=$qty');
          final postResp = await ApiClient.post(
            Uri.parse('${ApiConstants.baseUrl}/scan/scan-labelbox'),
            body: jsonEncode({'barcode': barcode, 'nik': nik, 'qty': qty}),
          );
          debugPrint('[PendingScanService]   POST ← ${postResp.statusCode}');
          debugPrint('[PendingScanService]   body: ${postResp.body}');

          timeouts = 0;
          // Termasuk balasan "sudah discan/diproses": request sebelumnya ternyata
          // sudah masuk server, jadi bukan error yang perlu diulang.
          if (isDone(postResp.body)) {
            debugPrint('[PendingScanService]   ✓ berhasil/duplikat sync barcode=$barcode → hapus dari cache');
            await remove(barcode);
            synced++;
          } else {
            debugPrint('[PendingScanService]   ✗ server tolak (SAP error) barcode=$barcode, tetap di cache');
          }
          // Jika SAP error asli (ok & alreadyProcessed = false), biarkan di cache, coba lagi nanti
        } on UnauthorizedException {
          debugPrint('[PendingScanService] ✗ 401 – berhenti sync');
          break; // Sesi habis
        } on SocketException catch (e) {
          debugPrint('[PendingScanService] ✗ SocketException – offline, berhenti sync: $e');
          break; // Masih offline — hentikan loop
        } on TimeoutException catch (e) {
          // POST tidak diulang otomatis; item tetap di cache. Percobaan berikutnya
          // dibalas "sudah discan" jika ternyata sudah diproses server.
          timeouts++;
          debugPrint('[PendingScanService] ✗ Timeout barcode=$barcode ($timeouts beruntun): $e');
          if (timeouts >= _maxConsecutiveTimeouts) {
            debugPrint('[PendingScanService] server lambat – berhenti sync, lanjut nanti');
            break;
          }
        } catch (e) {
          debugPrint('[PendingScanService] ✗ Error item barcode=$barcode (lanjut item berikutnya): $e');
          // Error tidak terduga untuk item ini — lewati, lanjut item berikutnya
        }
      }

      debugPrint('[PendingScanService] syncAll – selesai. berhasil=$synced');
    } finally {
      _syncing = false;
    }

    return synced;
  }
}

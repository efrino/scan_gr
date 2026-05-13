import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import '../../core/constants/api_constants.dart';

/// Cache lokal untuk scan yang belum terkirim ke server.
///
/// Dua tipe item yang bisa tersimpan:
///   1. [has_kanban_data = true]  → GET berhasil, POST gagal; punya data lengkap.
///   2. [has_kanban_data = false] → GET pun gagal (offline total); hanya punya barcode & nik.
///
/// Saat sync, tipe-2 akan GET dulu lalu POST.
/// Deduplication by barcode — satu barcode hanya masuk sekali.
/// SharedPreferences memakai internal app storage, tidak butuh izin storage OS.
class PendingScanService {
  PendingScanService._();

  static const _key = 'pending_scans';
  static bool _syncing = false;

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
  }

  // ── Add ───────────────────────────────────────────────────────────────────

  /// Simpan scan gagal ke cache lokal.
  /// [kanbanData] boleh null jika GET ikut gagal (offline total) — hanya barcode & nik yg tersimpan.
  /// Tidak menambah duplikat jika barcode sudah ada.
  static Future<void> add({
    required String barcode,
    required String nik,
    String qty = '',
    Map<String, dynamic>? kanbanData,
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
      'has_kanban_data': kanbanData != null,
      'cached_at': DateTime.now().toIso8601String(),
    };

    if (kanbanData != null) entry.addAll(kanbanData);

    list.add(entry);
    await _save(list);
    debugPrint('[PendingScanService] add – barcode=$barcode tersimpan (hasKanban=${kanbanData != null}) | total cache: ${list.length}');
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

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Kirim pending ke server satu per satu.
  /// Item tanpa kanban data akan GET dulu lalu POST.
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

      for (final item in List<Map<String, dynamic>>.from(list)) {
        final barcode = item['barcode'] as String? ?? '';
        final nik = item['nik'] as String? ?? '';
        String qty = item['qty'] as String? ?? '';
        final hasKanbanData = item['has_kanban_data'] == true;

        debugPrint('[PendingScanService] sync item barcode=$barcode | hasKanban=$hasKanbanData');

        try {
          // ── Tipe 2: tidak punya data kanban — GET dulu ──────────────────
          if (!hasKanbanData) {
            debugPrint('[PendingScanService]   GET get-kanban untuk barcode=$barcode');
            final getUri = Uri.parse('${ApiConstants.baseUrl}/scan/get-kanban')
                .replace(queryParameters: {'barcode': barcode});
            final getResp = await ApiClient.get(getUri);
            debugPrint('[PendingScanService]   GET ← ${getResp.statusCode}');
            debugPrint('[PendingScanService]   body: ${getResp.body}');
            final getData = jsonDecode(getResp.body);

            if (getData['status'] == true &&
                getData['data'] is List &&
                (getData['data'] as List).isNotEmpty) {
              final kanban = getData['data'][0] as Map<String, dynamic>;
              final alreadyScanned =
                  (kanban['is_scanned'] as String?)?.toUpperCase() == 'Y';

              if (alreadyScanned) {
                debugPrint('[PendingScanService]   barcode=$barcode sudah discan orang lain → hapus dari cache');
                await remove(barcode);
                synced++;
                continue;
              }
              qty = kanban['quantity']?.toString() ?? '';
            } else {
              debugPrint('[PendingScanService]   barcode=$barcode tidak ditemukan di server → hapus dari cache');
              await remove(barcode);
              continue;
            }
          }

          // ── POST ke server ──────────────────────────────────────────────
          debugPrint('[PendingScanService]   POST scan-kanban barcode=$barcode | nik=$nik | qty=$qty');
          final postResp = await ApiClient.post(
            Uri.parse('${ApiConstants.baseUrl}/scan/scan-kanban'),
            body: jsonEncode({'barcode': barcode, 'nik': nik, 'qty': qty}),
          );
          debugPrint('[PendingScanService]   POST ← ${postResp.statusCode}');
          debugPrint('[PendingScanService]   body: ${postResp.body}');

          final data = jsonDecode(postResp.body);
          final msg = (data['message'] as String? ?? '').toLowerCase();
          final ok = data['success'] == true ||
              data['status'] == true ||
              msg.contains('berhasil');

          if (ok) {
            debugPrint('[PendingScanService]   ✓ berhasil sync barcode=$barcode');
            await remove(barcode);
            synced++;
          } else {
            debugPrint('[PendingScanService]   ✗ server tolak (SAP error) barcode=$barcode, tetap di cache');
          }
          // Jika SAP error (ok = false), biarkan di cache, coba lagi nanti
        } on UnauthorizedException {
          debugPrint('[PendingScanService] ✗ 401 – berhenti sync');
          break; // Sesi habis
        } on SocketException catch (e) {
          debugPrint('[PendingScanService] ✗ SocketException – offline, berhenti sync: $e');
          break; // Masih offline — hentikan loop
        } on TimeoutException catch (e) {
          debugPrint('[PendingScanService] ✗ Timeout – berhenti sync: $e');
          break;
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

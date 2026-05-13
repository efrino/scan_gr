import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../core/services/pending_scan_service.dart';
import '../../shared/widgets/app_drawer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _username = 'User';
  String _nik = '';
  bool _loadingHistory = true;
  int _pendingCount = 0;
  bool _syncing = false;
  List<Map<String, dynamic>> _pendingItems = [];

  // Sesi scan terakhir (hasil pengelompokan)
  List<Map<String, dynamic>> _lastSession = [];
  DateTime? _sessionStart;
  DateTime? _sessionEnd;

  // Batas jeda antar scan untuk dianggap satu sesi (menit)
  static const int _sessionGapMinutes = 30;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username') ?? 'User';
    _nik = prefs.getString('nik') ?? prefs.getString('email') ?? '';
    await _syncPending();
    await _fetchLastSession();
  }

  // ── Sync pending scans ────────────────────────────────────────────────────
  Future<void> _syncPending() async {
    final items = await PendingScanService.getAll();
    if (mounted) {
      setState(() {
        _pendingCount = items.length;
        _pendingItems = items;
      });
    }
    if (items.isEmpty) return;

    if (mounted) setState(() => _syncing = true);
    final synced = await PendingScanService.syncAll();
    final remaining = await PendingScanService.getAll();
    if (mounted) {
      setState(() {
        _pendingCount = remaining.length;
        _pendingItems = remaining;
        _syncing = false;
      });
      if (synced > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            elevation: 0,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    '$synced scan berhasil disinkronkan',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
  }

  // ── Fetch history & kelompokkan sesi terakhir ─────────────────────────────
  Future<void> _fetchLastSession() async {
    setState(() => _loadingHistory = true);

    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/scan/history',
      ).replace(queryParameters: {'nik': _nik});

      debugPrint('[HomePage] GET → $uri');
      debugPrint('[HomePage]   nik: $_nik');

      final response = await ApiClient.get(uri);
      debugPrint('[HomePage] GET ← ${response.statusCode}');
      debugPrint('[HomePage]   body: ${response.body}');

      final data = jsonDecode(response.body);
      if (data['status'] == true && data['data'] is List) {
        final all = List<Map<String, dynamic>>.from(data['data']);
        debugPrint('[HomePage] ✓ ${all.length} item history diterima');
        _groupLastSession(all);
      } else {
        debugPrint('[HomePage] ✗ status bukan true atau data bukan list');
      }
    } on UnauthorizedException {
      debugPrint('[HomePage] ✗ 401 – sudah redirect ke login');
      return; // Sesi tidak valid — sudah redirect ke login
    } on ApiResponseException catch (e) {
      debugPrint('[HomePage] ✗ Server return non-JSON (HTML?) HTTP ${e.statusCode}');
      debugPrint('[HomePage]   Kemungkinan endpoint salah atau server error');
      debugPrint('[HomePage]   body awal: ${e.body.substring(0, e.body.length.clamp(0, 100))}');
      // Biarkan kosong; tampilkan "Belum ada scan" ke user
    } catch (e) {
      debugPrint('[HomePage] ✗ Error _fetchLastSession: $e');
      // Biarkan kosong; user bisa lihat semua di halaman Riwayat
    }

    if (mounted) setState(() => _loadingHistory = false);
  }

  // ── Logika pengelompokan sesi ─────────────────────────────────────────────
  // Ambil item yang sudah discan (date_scanned tidak null), urutkan terbaru dulu.
  // Mulai dari scan paling baru, terus masukkan item berikutnya selama jeda
  // dengan item sebelumnya ≤ _sessionGapMinutes. Berhenti saat jeda terlampaui.
  void _groupLastSession(List<Map<String, dynamic>> all) {
    final scanned = all.where((e) {
      return e['is_scanned'] == 'Y' &&
          e['date_scanned'] != null &&
          (e['date_scanned'] as String).isNotEmpty;
    }).toList();

    if (scanned.isEmpty) {
      _lastSession = [];
      _sessionStart = null;
      _sessionEnd = null;
      return;
    }

    // Urutkan terbaru → terlama
    scanned.sort((a, b) {
      final ta = _parseDateTime(a['date_scanned']);
      final tb = _parseDateTime(b['date_scanned']);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    final session = <Map<String, dynamic>>[];
    DateTime? prev;

    for (final item in scanned) {
      final t = _parseDateTime(item['date_scanned']);
      if (t == null) continue;

      if (prev == null) {
        // Item pertama (paling baru) — selalu masuk
        session.add(item);
        prev = t;
      } else {
        // Cek jeda antara item ini (lebih lama) dengan item sebelumnya
        final gap = prev.difference(t).inMinutes;
        if (gap <= _sessionGapMinutes) {
          session.add(item);
          prev = t;
        } else {
          break; // Jeda terlalu besar — sesi sudah selesai
        }
      }
    }

    // Urutkan kembali terlama → terbaru untuk tampilan
    session.sort((a, b) {
      final ta = _parseDateTime(a['date_scanned']);
      final tb = _parseDateTime(b['date_scanned']);
      if (ta == null || tb == null) return 0;
      return ta.compareTo(tb);
    });

    _lastSession = session;
    _sessionStart = _parseDateTime(session.first['date_scanned']);
    _sessionEnd = _parseDateTime(session.last['date_scanned']);
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDateShort(DateTime? dt) {
    if (dt == null) return '-';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Hari ini';
    if (d == today.subtract(const Duration(days: 1))) return 'Kemarin';
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: const Text(
          'GR Scanner',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red, Colors.blue],
              stops: [0.33, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              'assets/images/ico.png',
              height: 32,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _fetchLastSession,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              Text(
                'Halo, $_username 👋',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Selamat datang di Sistem Scan DN',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),

              // Banner pending offline
              if (_pendingCount > 0) ...[
                _PendingBanner(
                  items: _pendingItems,
                  syncing: _syncing,
                  onSync: () async {
                    await _syncPending();
                    if (mounted) _fetchLastSession();
                  },
                ),
                const SizedBox(height: 16),
              ],

              // SCAN button
              _ScanButton(
                onTap: () async {
                  await Navigator.pushNamed(context, '/scan');
                  if (mounted) {
                    await _syncPending();
                    _fetchLastSession();
                  }
                },
              ),

              const SizedBox(height: 32),

              // Scan terakhir section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Scan Terakhir',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/history'),
                    child: const Text(
                      'Lihat Semua',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              _buildLastSession(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget sesi scan terakhir ─────────────────────────────────────────────

  Widget _buildLastSession() {
    if (_loadingHistory) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_lastSession.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Belum ada scan',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Session header
        _SessionHeader(
          itemCount: _lastSession.length,
          sessionStart: _sessionStart,
          sessionEnd: _sessionEnd,
          fmtDateShort: _fmtDateShort,
          fmtTime: _fmtTime,
          gapMinutes: _sessionGapMinutes,
        ),
        const SizedBox(height: 8),

        // Item list (tampilkan maks 5, sisanya kolaps)
        _SessionItemList(
          items: _lastSession,
          fmtTime: _fmtTime,
        ),
      ],
    );
  }
}

// ─── Pending Banner ───────────────────────────────────────────────────────────

class _PendingBanner extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool syncing;
  final VoidCallback onSync;

  static const int _maxVisible = 5;

  const _PendingBanner({
    required this.items,
    required this.syncing,
    required this.onSync,
  });

  String _fmtCachedAt(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(dt.year, dt.month, dt.day);
      final hm =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (d == today) return 'Hari ini $hm';
      if (d == today.subtract(const Duration(days: 1))) return 'Kemarin $hm';
      return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} $hm';
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    final visibleItems = items.take(_maxVisible).toList();
    final extra = count - visibleItems.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.amber.shade800,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count scan menunggu sinkronisasi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tersimpan lokal saat offline',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: syncing ? null : onSync,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: syncing
                          ? Colors.grey.shade200
                          : Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: syncing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.grey.shade500,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Sinkron',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1, color: Colors.amber.shade200),

          // Per-item detail list
          ...visibleItems.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final hasKanban = item['has_kanban_data'] == true;
            final title = hasKanban
                ? (item['material']?.toString() ?? item['barcode']?.toString() ?? '-')
                : (item['barcode']?.toString() ?? '-');
            final subtitle = hasKanban
                ? (item['id_box_label']?.toString() ?? item['barcode']?.toString() ?? '')
                : 'Data belum diambil dari server';
            final qty = hasKanban ? item['qty']?.toString() ?? item['quantity']?.toString() : null;
            final cachedAt = _fmtCachedAt(item['cached_at']);
            final isLast = idx == visibleItems.length - 1 && extra == 0;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      // Number badge
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade200,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Title & subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: hasKanban
                                      ? Colors.grey.shade500
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Qty + time
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (qty != null && qty.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '$qty pcs',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            cachedAt,
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(height: 1, color: Colors.amber.shade100),
              ],
            );
          }),

          // "+N lainnya" indicator
          if (extra > 0) ...[
            Divider(height: 1, color: Colors.amber.shade200),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '+$extra item lainnya',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Scan Button ──────────────────────────────────────────────────────────────

class _ScanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Colors.red, Colors.blue],
                stops: [0.33, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner, color: Colors.white, size: 40),
                SizedBox(width: 16),
                Text(
                  'SCAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Session Header ───────────────────────────────────────────────────────────

class _SessionHeader extends StatelessWidget {
  final int itemCount;
  final DateTime? sessionStart;
  final DateTime? sessionEnd;
  final String Function(DateTime?) fmtDateShort;
  final String Function(DateTime?) fmtTime;
  final int gapMinutes;

  const _SessionHeader({
    required this.itemCount,
    required this.sessionStart,
    required this.sessionEnd,
    required this.fmtDateShort,
    required this.fmtTime,
    required this.gapMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = fmtDateShort(sessionEnd);
    final timeRange = sessionStart != null && sessionEnd != null &&
            sessionStart!.millisecondsSinceEpoch !=
                sessionEnd!.millisecondsSinceEpoch
        ? '${fmtTime(sessionStart)} – ${fmtTime(sessionEnd)}'
        : fmtTime(sessionEnd);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade800],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sesi terakhir  ·  $itemCount item',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$dateLabel  ·  $timeRange',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '≤ ${gapMinutes}m',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Session Item List ────────────────────────────────────────────────────────

class _SessionItemList extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String Function(DateTime?) fmtTime;

  const _SessionItemList({required this.items, required this.fmtTime});

  @override
  State<_SessionItemList> createState() => _SessionItemListState();
}

class _SessionItemListState extends State<_SessionItemList> {
  static const int _previewCount = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final showCount = _expanded
        ? widget.items.length
        : widget.items.length.clamp(0, _previewCount);
    final hasMore = widget.items.length > _previewCount;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Items
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: showCount,
            separatorBuilder: (ctx, i) =>
                Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final t = _parseDateTime(item['date_scanned']);
              return _SessionItem(
                material: item['material']?.toString() ?? '-',
                idBoxLabel: item['id_box_label']?.toString() ?? '-',
                qty: item['quantity']?.toString() ?? '-',
                time: widget.fmtTime(t),
                index: index + 1,
              );
            },
          ),

          // Show more / less
          if (hasMore) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? 'Sembunyikan'
                          : '+${widget.items.length - _previewCount} item lainnya',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }
}

// ─── Session Item Row ─────────────────────────────────────────────────────────

class _SessionItem extends StatelessWidget {
  final String material;
  final String idBoxLabel;
  final String qty;
  final String time;
  final int index;

  const _SessionItem({
    required this.material,
    required this.idBoxLabel,
    required this.qty,
    required this.time,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Nomor urut
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Material & label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  idBoxLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          // Qty + waktu
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$qty pcs',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

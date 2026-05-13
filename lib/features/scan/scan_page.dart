import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../core/services/pending_scan_service.dart';

// State global untuk menyimpan kondisi flash agar persisten antar halaman
bool globalFlashEnabled = false;

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _isScanned = false;
  bool _isLoading = false;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    // Tunggu kamera siap menggunakan event listener atau start secara manual
    _initScanner();
  }

  Future<void> _initScanner() async {
    try {
      await _scannerController.start();
      if (globalFlashEnabled && mounted) {
        await _scannerController.toggleTorch();
      }
    } catch (e) {
      debugPrint('[ScanPage] Error init scanner: $e');
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> fetchKanban(String code) async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final nik = prefs.getString('nik') ?? prefs.getString('email') ?? '';

    final barcode = code.trim();
    debugPrint('[ScanPage] fetchKanban barcode=$barcode | nik=$nik');

    // ── ONLINE DULU: coba ambil data dari server ──────────────────────────
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/scan/get-kanban',
      ).replace(queryParameters: {'barcode': barcode});

      debugPrint('[ScanPage] GET → $uri');
      final response = await ApiClient.get(
        uri,
      ).timeout(const Duration(seconds: 15));
      debugPrint('[ScanPage] GET ← ${response.statusCode}');
      debugPrint('[ScanPage]   body: ${response.body}');

      final data = jsonDecode(response.body);
      if (data['status'] == true &&
          data['data'] is List &&
          (data['data'] as List).isNotEmpty) {
        final kanbanData = data['data'][0] as Map<String, dynamic>;
        final isScanned =
            kanbanData['is_scanned']?.toString().toUpperCase() == 'Y';
        final qty = kanbanData['quantity']?.toString() ?? '';

        if (isScanned) {
          setState(() => _isLoading = false);
          _showSnackbar(
            'Barcode sudah discan sebelumnya',
            color: Colors.orange,
          );
          resetScan();
          return;
        }

        // Langsung POST
        final result = await submitKanban(
          barcode: barcode,
          nik: nik,
          qty: qty,
          kanbanData: kanbanData,
        );

        setState(() => _isLoading = false);

        if (result.isSuccess) {
          _showSnackbar('Berhasil terscan', color: Colors.green);
        } else {
          final isOffline =
              result.message.toLowerCase().contains('lokal') ||
              result.message.toLowerCase().contains('offline');
          _showSnackbar(
            result.message,
            color: isOffline ? Colors.orange : Colors.red,
          );
        }

        resetScan();
        return;
      } else {
        setState(() => _isLoading = false);
        final msg = data['message'] as String? ?? 'Data tidak ditemukan';
        debugPrint('[ScanPage] ✗ get-kanban gagal: $msg');
        _showSnackbar(msg, color: Colors.red);
        resetScan();
        return;
      }
    } on UnauthorizedException {
      setState(() => _isLoading = false);
      return; // sudah di-redirect ke /login oleh ApiClient
    } on ApiResponseException catch (e) {
      debugPrint(
        '[ScanPage] ✗ get-kanban endpoint return HTML HTTP ${e.statusCode}',
      );
      setState(() => _isLoading = false);
      _showSnackbar(
        'Endpoint server tidak ditemukan (HTTP ${e.statusCode})',
        color: Colors.red,
      );
      resetScan();
      return;
    } on SocketException catch (e) {
      debugPrint('[ScanPage] ✗ SocketException – offline: $e');
      // Lanjut ke fallback cache di bawah
    } on TimeoutException catch (e) {
      debugPrint('[ScanPage] ✗ Timeout: $e');
      // Lanjut ke fallback cache
    } catch (e) {
      debugPrint('[ScanPage] ✗ Error tidak terduga: $e');
      setState(() => _isLoading = false);
      _showSnackbar('Terjadi kesalahan koneksi ke server', color: Colors.red);
      resetScan();
      return;
    }

    // ── OFFLINE FALLBACK: simpan barcode ke pending cache ─────────────────
    debugPrint('[ScanPage] Offline – menyimpan barcode ke pending cache');
    await PendingScanService.add(
      barcode: barcode,
      nik: nik,
      // Tidak ada kanbanData karena GET pun gagal
    );
    setState(() => _isLoading = false);
    if (mounted) {
      _showSnackbar('Offline. Barcode disimpan di lokal', color: Colors.orange);
      resetScan();
    }
  }

  void _showSnackbar(String message, {Color color = Colors.blue}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  Future<_ScanResult> submitKanban({
    required String barcode,
    required String nik,
    required String qty,
    Map<String, dynamic>? kanbanData,
  }) async {
    debugPrint(
      '[ScanPage] submitKanban barcode=$barcode | nik=$nik | qty=$qty',
    );

    // ── ONLINE DULU: kirim ke server ─────────────────────────────────────
    try {
      final payload = {'barcode': barcode, 'nik': nik, 'qty': qty};
      debugPrint('[ScanPage] POST scan-kanban payload: $payload');

      final response = await ApiClient.post(
        Uri.parse('${ApiConstants.baseUrl}/scan/scan-kanban'),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      debugPrint('[ScanPage] POST ← ${response.statusCode}');
      debugPrint('[ScanPage]   body: ${response.body}');

      final data = _parseResponse(response.body);
      final msg = data['message'] as String? ?? '';

      // SAP selalu mengembalikan success=false; bedakan berhasil/gagal dari message.
      final isSuccess =
          data['success'] == true ||
          data['status'] == true ||
          msg.toLowerCase().contains('berhasil');

      debugPrint('[ScanPage] submitKanban isSuccess=$isSuccess | msg=$msg');

      return _ScanResult(
        isSuccess: isSuccess,
        message: msg.isEmpty
            ? (isSuccess
                  ? 'GR berhasil diproses.'
                  : 'Gagal mengirim data ke SAP.')
            : msg,
        detail: _buildSapDetail(
          httpStatus: response.statusCode,
          barcode: barcode,
          nik: nik,
          qty: qty,
          params: data['params'],
          source: data['source'],
          errors: data['errors'],
        ),
      );
    } on UnauthorizedException {
      return const _ScanResult(
        isSuccess: false,
        message: 'Sesi habis. Silakan login ulang.',
        detail: 'Token tidak valid (401)',
      );
    } on SocketException catch (e) {
      // ── OFFLINE FALLBACK: simpan ke pending cache ───────────────────────
      debugPrint(
        '[ScanPage] ✗ SocketException – menyimpan ke offline cache: $e',
      );
      await PendingScanService.add(
        barcode: barcode,
        nik: nik,
        qty: qty,
        kanbanData: kanbanData,
      );
      return _ScanResult(
        isSuccess: false,
        message:
            'Tidak ada koneksi. Data disimpan lokal dan akan dikirim saat online.',
        detail: 'Mode offline · barcode=$barcode disimpan ke pending cache',
      );
    } on TimeoutException catch (e) {
      debugPrint('[ScanPage] ✗ Timeout: $e');
      await PendingScanService.add(
        barcode: barcode,
        nik: nik,
        qty: qty,
        kanbanData: kanbanData,
      );
      return _ScanResult(
        isSuccess: false,
        message: 'Koneksi timeout. Data disimpan lokal.',
        detail: 'Timeout · barcode=$barcode',
      );
    } catch (e) {
      debugPrint('[ScanPage] ✗ Error tidak terduga: $e');
      return _ScanResult(
        isSuccess: false,
        message: 'Terjadi kesalahan koneksi ke server.',
        detail: '${e.runtimeType}: $e',
      );
    }
  }

  String _buildSapDetail({
    required int httpStatus,
    required String barcode,
    required String nik,
    required String qty,
    dynamic params,
    dynamic source,
    dynamic errors,
  }) {
    final lines = <String>[
      'HTTP $httpStatus · POST scan-kanban',
      'Barcode : $barcode',
      'NIK     : $nik',
      'QTY     : $qty',
      if (source != null) 'Source  : $source',
      if (params != null) 'Params  : $params',
      if (errors != null) 'Errors  : $errors',
    ];
    return lines.join('\n');
  }

  /// Coba parse JSON dulu; jika gagal, parse PHP var_dump format sebagai fallback.
  Map<String, dynamic> _parseResponse(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return _parsePhpVarDump(body);
    }
  }

  /// Parse PHP var_dump output menjadi Map.
  /// Mendukung bool, string top-level, dan nested array (dikonversi ke Map[String,String]).
  Map<String, dynamic> _parsePhpVarDump(String body) {
    final result = <String, dynamic>{};

    // bool: ["key"]=> \n  bool(true|false)
    final boolRe = RegExp(r'\["(\w+)"\]=>\s*bool\((true|false)\)');
    for (final m in boolRe.allMatches(body)) {
      result[m.group(1)!] = m.group(2) == 'true';
    }

    // string top-level: ["key"]=> \n  string(N) "value"
    final strRe = RegExp(
      r'\["(\w+)"\]=>\s*string\(\d+\)\s*"((?:[^"\\]|\\.)*)"',
    );
    for (final m in strRe.allMatches(body)) {
      result[m.group(1)!] = m.group(2)!;
    }

    // nested array: ["key"]=> \n  array(N) { ... }
    final arrRe = RegExp(
      r'\["(\w+)"\]=>\s*array\(\d+\)\s*\{([^}]*)\}',
      dotAll: true,
    );
    for (final m in arrRe.allMatches(body)) {
      final key = m.group(1)!;
      final inner = m.group(2)!;
      final nested = <String, String>{};
      final innerStr = RegExp(
        r'\["(\w+)"\]=>\s*string\(\d+\)\s*"((?:[^"\\]|\\.)*)"',
      );
      for (final im in innerStr.allMatches(inner)) {
        nested[im.group(1)!] = im.group(2)!;
      }
      result[key] = nested;
    }

    return result;
  }

  void resetScan() {
    setState(() {
      _isScanned = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Scan Kanban',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              globalFlashEnabled ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () async {
              try {
                await _scannerController.toggleTorch();
                if (mounted) {
                  setState(() {
                    globalFlashEnabled = !globalFlashEnabled;
                  });
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kamera belum siap, tunggu sebentar.'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (_isScanned) return;
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final barcode = barcodes.first;
                if (barcode.rawValue != null) {
                  setState(() => _isScanned = true);
                  fetchKanban(barcode.rawValue!);
                }
              }
            },
          ),

          // Scan frame overlay
          _ScanOverlay(),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Mengambil data...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Scan Frame Overlay ───────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  static const _margin = 28.0;
  static const _bracketSize = 48.0;
  static const _bracketThickness = 4.5;
  static const _bracketColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Positioned.fill(
      child: Stack(
        children: [
          // Gradient atas — jaga keterbacaan AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),

          // Gradient bawah — area hint text
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 180,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Corner brackets ──────────────────────────────────────────
          Positioned(
            top: top,
            left: _margin,
            child: _Corner(
              isLeft: true,
              isTop: true,
              size: _bracketSize,
              thickness: _bracketThickness,
              color: _bracketColor,
            ),
          ),
          Positioned(
            top: top,
            right: _margin,
            child: _Corner(
              isLeft: false,
              isTop: true,
              size: _bracketSize,
              thickness: _bracketThickness,
              color: _bracketColor,
            ),
          ),
          Positioned(
            bottom: _margin,
            left: _margin,
            child: _Corner(
              isLeft: true,
              isTop: false,
              size: _bracketSize,
              thickness: _bracketThickness,
              color: _bracketColor,
            ),
          ),
          Positioned(
            bottom: _margin,
            right: _margin,
            child: _Corner(
              isLeft: false,
              isTop: false,
              size: _bracketSize,
              thickness: _bracketThickness,
              color: _bracketColor,
            ),
          ),

          // ── Hint text ────────────────────────────────────────────────
          Positioned(
            bottom: 48 + bottom,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Arahkan kamera ke barcode',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final bool isLeft;
  final bool isTop;
  final double size;
  final double thickness;
  final Color color;

  const _Corner({
    required this.isLeft,
    required this.isTop,
    required this.size,
    required this.thickness,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          isLeft: isLeft,
          isTop: isTop,
          thickness: thickness,
          color: color,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool isLeft;
  final bool isTop;
  final double thickness;
  final Color color;

  const _CornerPainter({
    required this.isLeft,
    required this.isTop,
    required this.thickness,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final x = isLeft ? 0.0 : size.width;
    final y = isTop ? 0.0 : size.height;
    final dx = isLeft ? size.width : -size.width;
    final dy = isTop ? size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.thickness != thickness;
}

// ─── Scan Result Data ─────────────────────────────────────────────────────────

class _ScanResult {
  final bool isSuccess;
  final String message;
  final String detail;
  const _ScanResult({
    required this.isSuccess,
    required this.message,
    required this.detail,
  });
}

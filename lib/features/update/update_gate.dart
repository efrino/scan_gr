import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/app_update_service.dart';
import '../../core/services/pending_scan_service.dart';

/// Lapisan di atas seluruh app (dipasang lewat `MaterialApp.builder`).
/// Cek versi saat app dibuka, saat kembali ke depan, dan berkala selama app
/// terbuka, lalu menampilkan
/// ajakan update (opsional) atau layar wajib update.
///
/// Ditaruh sebagai layer Stack, bukan dialog/route, supaya tidak ikut
/// tertutup saat halaman berganti (misal splash → home).
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

enum _Phase { idle, prompt, downloading, readyToInstall, failed }

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  UpdateCheckResult? _result;
  _Phase _phase = _Phase.idle;
  double? _progress;
  String _source = '';
  String _error = '';
  int _pending = 0;

  /// Versi opsional yang sudah ditunda user; tidak ditawarkan lagi sampai
  /// app dibuka ulang.
  int? _snoozedVersion;

  /// Cek berkala selama app terbuka di layar. Operator sering membiarkan app
  /// terbuka seharian, jadi cek saat dibuka/resume saja tidak cukup.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(ignoreInterval: true);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(AppUpdateService.checkInterval, (_) {
      if (_phase != _Phase.downloading) _check(ignoreInterval: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      if (_phase != _Phase.downloading) _check();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel(); // jangan cek di background
    }
  }

  Future<void> _check({bool ignoreInterval = false}) async {
    final result = await AppUpdateService.check(ignoreInterval: ignoreInterval);
    if (!mounted || result == null) return;

    if (result.kind == UpdateKind.none) {
      setState(() {
        _result = null;
        _phase = _Phase.idle;
      });
      return;
    }
    if (result.kind == UpdateKind.optional &&
        result.latest!.versionCode == _snoozedVersion) {
      return;
    }

    final pending = await PendingScanService.count();
    if (!mounted) return;
    setState(() {
      _result = result;
      _pending = pending;
      if (_phase == _Phase.idle) _phase = _Phase.prompt;
    });
  }

  Future<void> _startUpdate() async {
    final latest = _result!.latest!;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = '';
    });
    try {
      final apk = await AppUpdateService.download(
        latest,
        onProgress: (p, source) {
          if (mounted) {
            setState(() {
              _progress = p;
              _source = source;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.readyToInstall);
      await AppUpdateService.install(apk);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = 'Unduhan gagal. Periksa koneksi lalu coba lagi.';
      });
    }
  }

  void _later() {
    setState(() {
      _snoozedVersion = _result?.latest?.versionCode;
      _result = null;
      _phase = _Phase.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final show = result != null && _phase != _Phase.idle;
    final required = result?.kind == UpdateKind.required;

    return Stack(
      children: [
        widget.child,
        if (show) ...[
          // Wajib update: tutup seluruh layar agar app tidak bisa dipakai.
          Positioned.fill(
            child: ModalBarrier(
              dismissible: false,
              color: Colors.black.withValues(alpha: required ? 0.85 : 0.5),
            ),
          ),
          Center(child: _card(context, result, required)),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, UpdateCheckResult r, bool required) {
    final theme = Theme.of(context);
    final latest = r.latest!;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  required
                      ? Icons.system_update_rounded
                      : Icons.new_releases_rounded,
                  color: required ? Colors.red.shade600 : Colors.blue.shade600,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    required ? 'Update Wajib' : 'Versi Baru Tersedia',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Terpasang ${r.installedName} → terbaru ${latest.versionName}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (required) ...[
              const SizedBox(height: 6),
              const Text(
                'Versi ini sudah tidak didukung. Update untuk melanjutkan scan.',
                style: TextStyle(fontSize: 13),
              ),
            ],
            if ((latest.releaseNotes ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                latest.releaseNotes!,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
            if (_pending > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_pending scan menunggu sinkronisasi. Data ini tetap '
                  'tersimpan setelah update.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ..._phaseContent(required),
          ],
        ),
      ),
    );
  }

  List<Widget> _phaseContent(bool required) {
    switch (_phase) {
      case _Phase.downloading:
        final pct = _progress == null ? '' : ' ${(_progress! * 100).round()}%';
        return [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 8),
          Text(
            'Mengunduh$pct${_source.isEmpty ? '' : ' dari $_source'}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
        ];
      case _Phase.readyToInstall:
        return [
          const Text(
            'Unduhan selesai. Ikuti layar instalasi Android. Jika diminta, '
            'izinkan "Instal aplikasi tak dikenal" untuk GR Scanner.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buttons(primary: 'Buka Installer', required: required),
        ];
      case _Phase.failed:
        return [
          Text(
            _error,
            style: TextStyle(fontSize: 13, color: Colors.red.shade700),
          ),
          const SizedBox(height: 8),
          _buttons(primary: 'Coba Lagi', required: required),
        ];
      case _Phase.prompt:
      case _Phase.idle:
        return [_buttons(primary: 'Update Sekarang', required: required)];
    }
  }

  Widget _buttons({required String primary, required bool required}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!required)
          TextButton(onPressed: _later, child: const Text('Nanti')),
        const SizedBox(width: 8),
        FilledButton(onPressed: _startUpdate, child: Text(primary)),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scan_gr/core/constants/api_constants.dart';
import 'package:scan_gr/core/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final primary = Uri.parse('${ApiConstants.baseUrl}/scan/history?nik=1');
  final local = Uri.parse('${ApiConstants.fallbackBaseUrl}/scan/history?nik=1');
  const ok = '{"status":true,"data":[]}';

  late List<Uri> calls;

  void useServer(http.Response Function(Uri) handler) {
    calls = [];
    ApiClient.client = MockClient((req) async {
      calls.add(req.url);
      return handler(req.url);
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'token': 'abc'});
    ApiClient.resetFallbackState();
  });

  test('server utama sehat: tidak menyentuh server lokal', () async {
    useServer((_) => http.Response(ok, 200));
    final res = await ApiClient.get(primary);
    expect(res.statusCode, 200);
    expect(calls, [primary]);
  });

  test('server utama tidak terjangkau: pindah ke server lokal', () async {
    useServer((u) {
      if (u.host == primary.host) throw const SocketException('down');
      return http.Response(ok, 200);
    });
    final res = await ApiClient.get(primary);
    expect(res.statusCode, 200);
    expect(calls, [primary, local]);
  });

  test('server utama 500: pindah ke server lokal', () async {
    useServer(
      (u) => u.host == primary.host
          ? http.Response('{}', 500)
          : http.Response(ok, 200),
    );
    final res = await ApiClient.get(primary);
    expect(res.statusCode, 200);
    expect(calls.last, local);
  });

  test('server utama 400: tidak pindah (error bisnis, bukan server)', () async {
    useServer((_) => http.Response('{"status":false}', 400));
    final res = await ApiClient.get(primary);
    expect(res.statusCode, 400);
    expect(calls, [primary]);
  });

  test(
    'setelah server utama gagal: request berikutnya langsung ke lokal',
    () async {
      useServer((u) {
        if (u.host == primary.host) throw const SocketException('down');
        return http.Response(ok, 200);
      });
      await ApiClient.get(primary);
      calls.clear();
      await ApiClient.post(primary, body: '{}');
      expect(calls, [local]);
    },
  );

  test(
    'dua server mati: lempar SocketException (masuk antrian offline)',
    () async {
      useServer((_) => throw const SocketException('down'));
      expect(ApiClient.get(primary), throwsA(isA<SocketException>()));
    },
  );

  group('POST tidak idempoten', () {
    test('server utama timeout: tidak dikirim ulang ke server lokal', () async {
      calls = [];
      ApiClient.client = MockClient((req) async {
        calls.add(req.url);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response(ok, 200);
      });
      await expectLater(
        ApiClient.post(
          primary,
          body: '{}',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, [primary]);
    });

    test('server utama 500: tidak dikirim ulang ke server lokal', () async {
      useServer((_) => http.Response('{"status":false}', 500));
      final res = await ApiClient.post(primary, body: '{}');
      expect(res.statusCode, 500);
      expect(calls, [primary]);
    });

    test('server utama tidak terjangkau: pindah ke server lokal', () async {
      useServer((u) {
        if (u.host == primary.host) throw const SocketException('down');
        return http.Response(ok, 200);
      });
      await ApiClient.post(primary, body: '{}');
      expect(calls, [primary, local]);
    });
  });
}

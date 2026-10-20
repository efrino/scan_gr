import 'package:flutter_test/flutter_test.dart';
import 'package:scan_gr/core/services/app_update_service.dart';

void main() {
  const github =
      'https://github.com/efrino/scan_gr/releases/download/v1.0.1/app-release.apk';
  const server =
      'https://mspin.newarmada.biz/portal-supplier/public/apk/scan_gr-1.0.1.apk';

  AppVersionInfo info({String? local}) => AppVersionInfo.fromJson({
    'version_code': 2,
    'version_name': '1.0.1',
    'min_version_code': 1,
    'apk_url': github,
    'apk_url_local': local,
  });

  test('urutan sumber: GitHub, domain server, IP LAN', () {
    expect(info(local: server).downloadUrls, [
      github,
      server,
      'http://192.168.10.55/portal-supplier/public/apk/scan_gr-1.0.1.apk',
    ]);
  });

  test('tanpa apk_url_local: hanya GitHub', () {
    expect(info().downloadUrls, [github]);
    expect(info(local: '').downloadUrls, [github]);
  });

  test('parse angka versi dari JSON', () {
    final v = info(local: server);
    expect(v.versionCode, 2);
    expect(v.minVersionCode, 1);
    expect(v.versionName, '1.0.1');
  });
}

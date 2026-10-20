class ApiConstants {
  /// Server utama (internet, HTTPS).
  static const String baseUrl = 'https://mspin.newarmada.biz/portal-supplier/public/api';

  /// Server lokal (LAN, HTTP). Dipakai otomatis oleh ApiClient jika server
  /// utama tidak terjangkau, timeout, atau error 5xx.
  static const String fallbackBaseUrl = 'http://192.168.10.55/portal-supplier/public/api';
}

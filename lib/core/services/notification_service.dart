import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import 'api_client.dart';
import 'app_update_service.dart';

/// Pesan FCM saat app tertutup. Notifikasi sudah ditampilkan sistem dari
/// payload `notification`, jadi di sini cukup kosong.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// Push notification dari server (gangguan SAP, pengumuman dari CMS).
///
/// - Semua device berlangganan topik [topic], untuk siaran ke seluruh operator.
/// - Token FCM dikirim ke server per device, untuk notifikasi ke device tertentu.
/// - Pesan dengan data `type = sap_status` juga memperbarui [sapStatus] supaya
///   banner di app ikut berubah.
class NotificationService {
  NotificationService._();

  static const topic = 'gr-scanner';
  static const _channel = AndroidNotificationChannel(
    'gr_info',
    'Info GR Scanner',
    description: 'Status server SAP dan pengumuman',
    importance: Importance.high,
  );

  static final _local = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Pesan gangguan SAP yang sedang berlaku, atau null jika normal.
  /// Diisi dari push maupun header `X-System-Status` di respons API.
  static final ValueNotifier<String?> sapStatus = ValueNotifier(null);

  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();

      final fcm = FirebaseMessaging.instance;
      await fcm.subscribeToTopic(topic);
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_applyData);
      // Token registrasi klasik dipakai karena server mengirim lewat FCM HTTP v1
      // `message.token`; API register()/FID belum diperlukan.
      // ignore: deprecated_member_use
      fcm.onTokenRefresh.listen((t) => registerToken(token: t));

      _ready = true;
      debugPrint('[Notif] siap, topik=$topic');
      await registerToken();
    } catch (e) {
      // Tanpa push, app tetap jalan; banner status masih dari header API.
      debugPrint('[Notif] gagal inisialisasi: $e');
    }
  }

  /// App di depan: sistem tidak menampilkan notifikasi FCM, jadi tampilkan
  /// sendiri lewat notifikasi lokal.
  static Future<void> _onForeground(RemoteMessage m) async {
    _applyData(m);
    final n = m.notification;
    if (n == null) return;
    await _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static void _applyData(RemoteMessage m) {
    if (m.data['type'] != 'sap_status') return;
    applySapStatus(m.data['state'], m.data['message']);
  }

  /// [state] `down` menampilkan banner dengan [message]; selain itu menghapusnya.
  static void applySapStatus(String? state, String? message) {
    sapStatus.value = state == 'down'
        ? (message?.isNotEmpty == true
              ? message
              : 'Server SAP sedang gangguan. Scan tetap tersimpan dan dikirim otomatis.')
        : null;
  }

  /// Kirim token FCM ke server agar device ini bisa dikirimi notifikasi
  /// langsung. Hanya saat sudah login; dipanggil ulang setelah login.
  static Future<void> registerToken({String? token}) async {
    if (!_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString('token') ?? '').isEmpty) return;
      // ignore: deprecated_member_use
      token ??= await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.post(
        Uri.parse('${ApiConstants.baseUrl}/app/fcm-token'),
        body: jsonEncode({
          'fcm_token': token,
          ...await AppUpdateService.deviceParams(),
        }),
        timeout: const Duration(seconds: 15),
      );
      debugPrint('[Notif] token terdaftar di server');
    } catch (e) {
      debugPrint('[Notif] daftar token gagal: $e');
    }
  }
}

import 'package:flutter/material.dart';
import 'core/services/api_client.dart';
import 'core/services/notification_service.dart';
import 'shared/widgets/sap_status_banner.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'features/scan/scan_page.dart';
import 'features/history/history_page.dart';
import 'features/update/update_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Tidak ditunggu: app tampil dulu, push siap menyusul.
  NotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mekar Armada Jaya',
      navigatorKey: ApiClient.navigatorKey, // ← wajib agar redirect 401 bekerja
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Cek versi & ajakan update, serta banner gangguan SAP, di atas semua halaman.
      builder: (context, child) =>
          UpdateGate(child: SapStatusBanner(child: child!)),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/scan': (context) => const ScanPage(),
        '/history': (context) => const HistoryPage(),
      },
    );
  }
}

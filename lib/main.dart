import 'package:flutter/material.dart';
import 'core/services/api_client.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'features/scan/scan_page.dart';
import 'features/history/history_page.dart';

void main() {
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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Field label "Username" di UI, tapi API pakai field "email"
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscure = true;
  String? _errorMsg;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Username dan password wajib diisi');
      return;
    }

    setState(() {
      isLoading = true;
      _errorMsg = null;
    });

    // ── Endpoint: POST /api/login  ────────────────────────────────────────
    // Payload: { email, password }
    // Response: { status, message, token, expired_at, user: { nik_user, ... } }
    final uri = Uri.parse('${ApiConstants.baseUrl}/login');
    debugPrint('[Login] POST → $uri');
    debugPrint('[Login]   email: $email');

    try {
      final response = await ApiClient.postNoAuth(
        uri,
        body: jsonEncode({'email': email, 'password': password}),
      );

      debugPrint('[Login] ← status: ${response.statusCode}');
      debugPrint('[Login]   raw body: ${response.body}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // ── Cek status login sukses ─────────────────────────────────────────
      final bool isSuccess = data['status'] == true && data['token'] != null;

      if (!isSuccess) {
        final msg =
            data['message']?.toString() ??
            data['error']?.toString() ??
            'Login gagal. Periksa username & password.';
        setState(() {
          isLoading = false;
          _errorMsg = msg;
        });
        debugPrint('[Login] ✗ gagal: $msg');
        return;
      }

      // ── Ambil token dari root response ──────────────────────────────────
      final token = data['token']?.toString() ?? '';
      debugPrint(
        '[Login] ✓ token: ${token.substring(0, token.length.clamp(0, 16))}...',
      );

      // ── Ambil user info dari data['user'] ───────────────────────────────
      final user = data['user'] is Map<String, dynamic>
          ? data['user'] as Map<String, dynamic>
          : <String, dynamic>{};

      // NIK untuk query API history & scan
      final nik = user['nik_user']?.toString() ?? '';
      // Nama tampil: pic_user > cp_name > email
      final displayName = (user['pic_user']?.toString().isNotEmpty == true)
          ? user['pic_user'].toString()
          : (user['cp_name']?.toString().isNotEmpty == true)
          ? user['cp_name'].toString()
          : email;
      final userEmail = user['email']?.toString() ?? email;
      final companyName =
          user['company_name']?.toString() ?? user['cp_name']?.toString() ?? '';
      final role = user['role']?.toString() ?? 'user';

      debugPrint('[Login] ✓ nik=$nik | name=$displayName | email=$userEmail');

      // ── Simpan ke SharedPreferences ─────────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      await prefs.setString('role', role);
      await prefs.setString('username', displayName);
      await prefs.setString('email', userEmail);
      await prefs.setString('company', companyName);
      await prefs.setString('nik', nik);

      debugPrint('[Login] ✓ sesi tersimpan (nik=$nik) → navigasi ke /home');

      setState(() => isLoading = false);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on ApiResponseException catch (e) {
      debugPrint('[Login] ✗ Server return non-JSON HTTP ${e.statusCode}');
      setState(() {
        isLoading = false;
        _errorMsg = 'Server error (HTTP ${e.statusCode}). Coba lagi.';
      });
    } on SocketException catch (e) {
      debugPrint('[Login] ✗ SocketException: $e');
      setState(() {
        isLoading = false;
        _errorMsg =
            'Tidak dapat terhubung ke server. Periksa koneksi internet.';
      });
    } on http.ClientException catch (e) {
      debugPrint('[Login] ✗ ClientException: $e');
      setState(() {
        isLoading = false;
        _errorMsg = 'Koneksi bermasalah: ${e.message}';
      });
    } catch (e) {
      debugPrint('[Login] ✗ Error: $e');
      setState(() {
        isLoading = false;
        _errorMsg = 'Terjadi kesalahan: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade900, Colors.blue.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo Perusahaan
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.white,
                      backgroundImage: AssetImage('assets/images/maj-gold.jpg'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title Aplikasi
                  const Text(
                    'Mekar Armada Jaya',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'GR Scanning Process',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Login Card
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Login Akun',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Email Field
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: Colors.blue.shade700,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.blue.shade600,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Password Field
                        TextField(
                          controller: passwordController,
                          obscureText: obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => handleLogin(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: Colors.blue.shade700,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: Colors.grey.shade500,
                              ),
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.blue.shade600,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                          ),
                        ),

                        // Error Message
                        if (_errorMsg != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMsg!,
                                    style: TextStyle(
                                      color: Colors.red.shade800,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),

                        // Login Button
                        ElevatedButton(
                          onPressed: isLoading ? null : handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            elevation: 3,
                            shadowColor: Colors.blue.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Text(
                                  'Masuk',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Footer
                  const Text(
                    '© 2026 PT Mekar Armada Jaya',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

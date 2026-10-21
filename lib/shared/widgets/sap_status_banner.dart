import 'package:flutter/material.dart';

import '../../core/services/notification_service.dart';

/// Banner di atas semua halaman selama server SAP gangguan, supaya operator
/// tahu scan yang belum terkirim bukan kesalahan mereka.
class SapStatusBanner extends StatelessWidget {
  final Widget child;
  const SapStatusBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: NotificationService.sapStatus,
      builder: (context, message, _) {
        if (message == null) return child;
        return Column(
          children: [
            Material(
              color: Colors.orange.shade700,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              // Banner sudah memakai ruang status bar.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

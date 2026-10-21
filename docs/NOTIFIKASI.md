# Push Notification (Firebase)

GR Scanner memakai Firebase Cloud Messaging (FCM) untuk pemberitahuan **satu
arah** ke operator: gangguan server SAP dan pengumuman dari admin. Aplikasi
hanya menampilkan notifikasi; tidak ada status atau balasan.

## Gambaran sistem

```
                 ┌──────────── Server 55 (portal-supplier) ────────────┐
 CMS admin ──────► AppRelease::pushSend ─┐                               │
                 │                       ├─► Fcm::send ──────────────────┼──► Firebase (FCM)
 Panggilan SAP ──► M_curl → SapHealth ───┘     (OAuth2 service account)  │        │
                 └────────────────────────────────────────────────────────┘        │
                                                                                    ▼
                                                     Device GR Scanner (topik "gr-scanner"
                                                     atau token per device)
```

- Project Firebase: `gr-scanner-a79c8`
- Package Android: `com.example.scan_gr`
- Topik: `gr-scanner` (semua device berlangganan otomatis)
- Channel Android: `gr_info` ("Info GR Scanner", prioritas tinggi)

## Sumber notifikasi

### 1. Pengumuman manual dari CMS

CMS **Rilis & Versi** → kartu **Notifikasi ke operator**. Butuh izin **Update**
pada menu ini (Set Permission).

- **Kirim ke:** semua device (topik) atau satu device (operator · model device).
  Daftar device hanya berisi device yang sudah mendaftarkan token FCM.
- **Judul** maksimal 100 karakter, **Isi** maksimal 500 karakter.
- Setiap pengiriman dicatat di log server (`Push CMS oleh <email> ...`).

### 2. Gangguan SAP otomatis

Setiap pemanggilan SAP lewat `M_curl::execute()` / `execute_array()` dicatat
oleh `SapHealth::observe()`:

| Kejadian | Dihitung gagal? |
|---|---|
| Balasan berisi "Could not open connection", "connection refused", "timed out", "RFC_COMMUNICATION", "partner not reached" | Ya |
| Balasan bukan JSON / kosong | Ya |
| Pemanggilan lebih dari 30 detik | Ya |
| Penolakan bisnis SAP (mis. "sudah discan") | Tidak, SAP hidup |

- **3 kali gagal beruntun** → satu push "SAP sedang gangguan" ke semua device.
- **Pemanggilan berhasil berikutnya** → satu push "SAP normal kembali".
- Tidak ada push berulang selama gangguan masih berlangsung.
- Penanda gangguan disimpan di cache server dan hilang sendiri setelah 6 jam
  tanpa pemanggilan SAP.

Konstanta bisa diubah di `app/Libraries/SapHealth.php` (`FAIL_THRESHOLD`,
`SLOW_SECONDS`, `MSG_DOWN`, `MSG_UP`).

## Sisi aplikasi

Kode: `lib/core/services/notification_service.dart`.

1. Saat app dibuka: inisialisasi Firebase, minta izin notifikasi (Android 13+),
   buat channel `gr_info`, berlangganan topik `gr-scanner`.
2. Setelah login (dan saat token berubah): kirim token FCM ke
   `POST /api/app/fcm-token` bersama `device_id` dan `device_model`.
3. Menampilkan notifikasi:
   - App tertutup / di background: ditampilkan sistem Android.
   - App sedang dibuka: ditampilkan lewat `flutter_local_notifications`.

Jika operator menolak izin notifikasi, app tetap berjalan normal; hanya
notifikasi yang tidak muncul. Izin bisa diaktifkan lagi di Pengaturan Android →
Aplikasi → GR Scanner → Notifikasi.

## Sisi server

| Komponen | File |
|---|---|
| Kirim ke FCM HTTP v1 | `app/Libraries/Fcm.php` |
| Deteksi gangguan SAP | `app/Libraries/SapHealth.php` (dipanggil dari `app/Models/M_curl.php`) |
| Simpan token device | `AppVersion::fcmToken`, route `POST api/app/fcm-token` (filter `apitoken`) |
| Kirim dari CMS | `AppRelease::pushSend`, route `POST app-release/push-send` |
| Tabel | `app_devices.fcm_token` |

`Fcm::send()` membuat JWT dari service account, menukarnya dengan access token
OAuth2 (di-cache sekitar 55 menit), lalu memanggil
`https://fcm.googleapis.com/v1/projects/gr-scanner-a79c8/messages:send`.

Contoh kirim dari kode backend lain:

```php
use App\Libraries\Fcm;

Fcm::send('Judul', 'Isi pesan');                          // semua device
Fcm::send('Judul', 'Isi pesan', ['type' => 'info'], $fcmToken); // satu device
```

## Kredensial

| File | Lokasi | Catatan |
|---|---|---|
| `google-services.json` | `android/app/` (lokal), secret `GOOGLE_SERVICES_JSON` (CI) | Tidak masuk repo (`.gitignore`). |
| Service account | `/var/www/html/portal-supplier/writable/firebase-service-account.json` | **Rahasia.** Jangan dikirim ke chat, repo, atau email. |

Mengganti service account (mis. bocor atau kedaluwarsa):

1. Firebase Console → Project settings → Service accounts → **Generate new
   private key**.
2. Ganti file di server 55 pada lokasi di atas.
3. Hapus kunci lama di Google Cloud Console → IAM → Service accounts → Keys.

Tidak perlu rilis ulang aplikasi.

## Pemecahan masalah

| Gejala | Cek |
|---|---|
| CMS: "Firebase belum dipasang di server" | File service account tidak ada di `writable/`. |
| CMS: "FCM menolak, cek log server" | Log `writable/logs/log-<tanggal>.log`, cari `FCM:`. |
| Device tidak ada di pilihan "Kirim ke" | Device belum login di app 1.0.8+, atau token gagal terdaftar (logcat: `[Notif]`). |
| Notifikasi tidak muncul di device | Izin notifikasi ditolak, mode hemat baterai, atau app versi lama (sebelum 1.0.8). |
| Notifikasi gangguan SAP tidak terkirim | SAP menggantung tanpa batas waktu (`CURLOPT_TIMEOUT = 0` di `M_curl`); `SapHealth` baru mencatat setelah pemanggilan selesai. |

Cek log device lewat adb:

```bash
adb logcat | findstr "[Notif]"
```

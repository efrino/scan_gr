# Perubahan di Server 55 (portal-supplier) untuk GR Scanner

Periode: 20–21 Oktober 2026. Root aplikasi: `/var/www/html/portal-supplier/`.

Tim yang menyimpan salinan lokal portal-supplier: **ambil file di bawah dari
server (atau dari `backend/portal-supplier/app/` di repo ini) sebelum deploy**,
supaya perubahan ini tidak tertimpa.

## A. File baru (aman, tidak bentrok dengan kode lama)

| File | Fungsi |
|---|---|
| `app/Controllers/AppRelease.php` | CMS menu Rilis & Versi |
| `app/Controllers/AppDownload.php` | Halaman unduh publik `app/download` |
| `app/Controllers/RestAPI/AppVersion.php` | API cek versi, release hook, token FCM |
| `app/Libraries/ApkInfo.php` | Baca versi dari file APK |
| `app/Libraries/GithubRelease.php` | Rilis ke GitHub |
| `app/Libraries/ApiTokens.php` | Token login API per device |
| `app/Libraries/Fcm.php` | Kirim push notification Firebase |
| `app/Libraries/SapHealth.php` | Deteksi gangguan SAP |
| `app/Views/app_release/index.php` | Tampilan CMS Rilis & Versi |
| `app/Views/app_release/download.php` | Tampilan halaman unduh |
| `app/Database/Migrations/2026-10-20-162600_CreateAppVersions.php` | Tabel `app_versions` |
| `app/Database/Migrations/2026-10-20-170000_AddApkUrlLocalToAppVersions.php` | Kolom `apk_url_local` |
| `app/Database/Migrations/2026-10-20-180000_CreateAppDevices.php` | Tabel `app_devices` |
| `app/Database/Migrations/2026-10-20-190000_ConvertAppTimesToWib.php` | Konversi waktu ke WIB |
| `app/Database/Migrations/2026-10-21-090000_FixReleaseNotes104.php` | Perbaikan catatan rilis 1.0.4 |
| `app/Database/Migrations/2026-10-21-140000_CreateApiTokens.php` | Tabel `api_tokens` |
| `app/Database/Migrations/2026-10-21-150000_AddFcmTokenToAppDevices.php` | Kolom `app_devices.fcm_token` |
| `app/Database/Seeds/AppVersionSeeder.php`, `AppVersion101Seeder.php` | Data awal versi |

## B. File lama yang DIUBAH (rawan tertimpa)

| File | Perubahan |
|---|---|
| `app/Config/Routes.php` | Tambah route: grup `app-release/*` (index, qr, wa-status, wa-logout, wa-send-one, push-send, chunk, store, min, toggle), `app/download`, `app/download/apk`, `api/app/version`, `api/app/release-hook`, `api/app/fcm-token` |
| `app/Config/Menu.php` | Tambah menu "Rilis & Versi" (permission `Module.View.AppRelease`) |
| `app/Filters/ApiTokenFilter.php` | Cek token per device (tabel `api_tokens`) dengan fallback ke `users.api_token`; `after()` menambah header `X-App-Latest-Build` dan `X-System-Status` |
| `app/Controllers/RestAPI/AuthController.php` | Login membuat token per device (`device_id`), masa berlaku 30 hari bergeser; logout hanya mencabut token device itu; perbaikan error 500 saat body kosong |
| `app/Models/M_curl.php` | `execute()` dan `execute_array()` mencatat durasi dan hasil ke `SapHealth::observe()` (3 baris tambahan per method) |

## C. Konfigurasi dan file non-kode

| Item | Keterangan |
|---|---|
| `.env` | Tambah kunci `GITHUB_TOKEN`, `GITHUB_REPO`, `RELEASE_HOOK_TOKEN`, `WA_GATEWAY_URL`, `WA_GATEWAY_TOKEN`, `FONNTE_TOKEN` (nilai rahasia, jangan disalin ke repo) |
| `writable/firebase-service-account.json` | Kredensial Firebase (rahasia) |
| `public/apk/` | Salinan APK rilis (folder baru) |
| Database | Tabel baru `app_versions`, `app_devices`, `api_tokens`; data di `users.api_token` tetap dipakai sebagai fallback |

## D. Backup sebelum perubahan

Di `/var/www/backup/`:

- `portal-supplier-appversion-20261020-162506`
- `portal-supplier-cms-20261020-171420`, `-171509`, `-171920`
- `portal-supplier-token-20261021-135023`
- `portal-supplier-push-20261021-144111`
- `portal-supplier-nostatus-20261021-152440`

## E. Cara aman sebelum tim lain deploy

```bash
# Bandingkan salinan lokal dengan server sebelum menimpa
ssh sto55 "cat /var/www/html/portal-supplier/app/Config/Routes.php" > Routes.server.php
diff Routes.server.php app/Config/Routes.php
```

File di bagian B **harus digabung (merge)**, bukan ditimpa.

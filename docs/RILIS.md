# Panduan Rilis GR Scanner

Dokumen ini menjelaskan cara merilis versi baru aplikasi GR Scanner ke semua
device operator, dari perubahan kode sampai device ter-update.

## Ringkasan

| Aksi | Rilis otomatis? |
|---|---|
| `git commit` + `git push` ke `main` | **Tidak.** Kode hanya tersimpan di GitHub. |
| `git push` tag `vX.Y.Z` | **Ya.** GitHub Actions membangun APK dan mendaftarkannya ke server. |
| Upload APK lewat CMS "Rilis & Versi" | Ya, rilis manual dari website. |
| `scripts/release.ps1` | Ya, rilis manual dari PC (cadangan jika Actions bermasalah). |

Pemisahan ini disengaja: tidak setiap commit layak dikirim ke operator. Rilis
terjadi hanya saat tag dibuat.

## Alur rilis normal

```bash
# 1. Simpan perubahan
git add -A
git commit -m "fix: deskripsi perubahan"
git push origin main

# 2. Buat tag dengan catatan rilis (ditampilkan ke operator)
git tag -a v1.1.0 -m "- Perbaikan scan saat koneksi lambat
- Tampilan riwayat lebih rapi"
git push origin v1.1.0
```

Setelah tag di-push:

1. GitHub Actions (`.github/workflows/release.yml`) berjalan, sekitar 10 menit.
   Pantau di tab **Actions** repo `efrino/scan_gr`, atau dengan `gh run watch`.
2. Workflow menjalankan test, membangun APK release bertanda tangan, membuat
   GitHub Release, lalu mendaftarkan versi ke server 55.
3. Device operator menerima dialog update:
   - dalam hitungan detik setelah request API berikutnya (header `X-App-Latest-Build`),
   - paling lambat 5 menit (cek berkala),
   - atau saat aplikasi dibuka.

### Aturan tag dan versi

- Format tag wajib `vX.Y.Z`, contoh `v1.1.0`. Tag lain ditolak workflow.
- `versionName` = nama tag tanpa `v`.
- `versionCode` (build) = build terakhir di server + 1. Tidak perlu diatur manual.
- Naikkan angka sesuai jenis perubahan: `1.0.9` ke `1.0.10` untuk perbaikan,
  `1.1.0` untuk fitur baru.
- Tag yang sudah dipakai tidak bisa dipakai ulang. Untuk mengulang, hapus tag
  dan release di GitHub dulu.

### Catatan rilis

Teks yang dilihat operator diambil berurutan dari:

1. Pesan tag (`git tag -a ... -m "..."`). **Disarankan**, tulis dalam bahasa
   operator, bukan bahasa teknis.
2. Jika tag tanpa pesan: judul commit berawalan `feat:` / `fix:` sejak tag
   sebelumnya, tanpa awalannya.
3. Jika tidak ada: "Perbaikan dan peningkatan stabilitas aplikasi."

Catatan bisa diubah setelah rilis lewat CMS (tabel `app_versions.release_notes`).

### Update wajib atau opsional

Rilis dari tag selalu **wajib** (`min_version_code` = build baru). Device tidak
bisa menunda. Untuk menjadikannya opsional, buka CMS **Rilis & Versi** lalu ubah
"Versi tertua yang boleh dipakai" ke versi sebelumnya.

## Rollback (kembali ke versi sebelumnya)

Android tidak mengizinkan menurunkan `versionCode`. Jadi rollback dilakukan
dengan merilis ulang kode lama sebagai versi baru:

```bash
git checkout -b rollback v1.0.8       # kode versi yang ingin dipakai lagi
git tag -a v1.0.11 -m "- Kembali ke versi stabil sebelumnya"
git push origin v1.0.11
git checkout main
```

Atau, untuk sementara, nonaktifkan versi bermasalah di CMS. Device yang belum
update tidak akan ditawari versi itu.

## Rilis cadangan

### Dari CMS (tanpa GitHub Actions)

CMS **Rilis & Versi** → **Rilis versi baru** → unggah APK release. Versi dan
build dibaca otomatis dari APK. APK harus ditandatangani keystore release
(`scan_gr-release.jks`); APK debug ditolak.

### Dari PC

```powershell
.\scripts\release.ps1 -Version 1.1.0 -Notes "Perbaikan kecil"
.\scripts\release.ps1 -Version 1.1.0 -Notes "Perbaikan kecil" -Optional
```

Butuh `flutter`, `gh` (sudah login), `android/key.properties` + keystore, dan
token rilis (sama dengan `RELEASE_HOOK_TOKEN` di `.env` server; diminta saat
skrip berjalan, tidak disimpan).

## Secrets GitHub Actions

Diatur di **Settings → Secrets and variables → Actions**. Nilainya tidak boleh
ditulis di repo maupun chat.

| Secret | Isi | Cara mengisi ulang |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | File keystore dalam base64 | `[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\261-CPU-TBN\keystores\scan_gr-release.jks")) \| gh secret set ANDROID_KEYSTORE_BASE64` |
| `ANDROID_KEYSTORE_PASSWORD` | Password keystore (store dan key sama) | `gh secret set ANDROID_KEYSTORE_PASSWORD` |
| `ANDROID_KEY_ALIAS` | `scan_gr` | `gh secret set ANDROID_KEY_ALIAS` |
| `RELEASE_HOOK_TOKEN` | Sama dengan `RELEASE_HOOK_TOKEN` di `.env` server 55 | `gh secret set RELEASE_HOOK_TOKEN` |
| `GOOGLE_SERVICES_JSON` | Isi `android/app/google-services.json` | `Get-Content android/app/google-services.json -Raw \| gh secret set GOOGLE_SERVICES_JSON` |

> **Penting:** keystore `scan_gr-release.jks` dan password-nya wajib dibackup di
> tempat aman. Jika hilang, aplikasi tidak bisa di-update lagi; semua device
> harus uninstall dan install ulang.

## Masalah umum

| Gejala | Penyebab dan solusi |
|---|---|
| Workflow gagal di "Siapkan keystore" atau build | Secret keystore salah/kosong. Isi ulang (tabel di atas). |
| Gagal di "Siapkan konfigurasi Firebase" | Secret `GOOGLE_SERVICES_JSON` kosong. |
| Gagal di "Daftarkan ke server" | `RELEASE_HOOK_TOKEN` tidak sama dengan `.env` server, atau server 55 tidak bisa mengunduh dari GitHub. Release GitHub sudah ada; daftarkan manual lewat CMS. |
| Workflow tidak jalan sama sekali | Akun GitHub terkunci (billing) atau tag tidak berformat `vX.Y.Z`. Pakai rilis cadangan. |
| Job "check" melewati rilis | Release dengan tag itu sudah ada (mis. dibuat `release.ps1`). Normal. |
| Device tidak menawarkan update | Versi dinonaktifkan di CMS, atau device versi lama (sebelum 1.0.7) perlu tutup-buka aplikasi. |

## Lokasi penting

| Apa | Di mana |
|---|---|
| Workflow rilis | `.github/workflows/release.yml` |
| Skrip rilis lokal | `scripts/release.ps1` |
| CMS rilis | `https://mspin.newarmada.biz/portal-supplier/public/app-release` |
| Halaman unduh publik | `https://mspin.newarmada.biz/portal-supplier/public/app/download` |
| API versi | `GET /api/app/version`, `POST /api/app/release-hook` |
| Kode backend (cermin) | `backend/portal-supplier/app/` |
| Skrip deploy backend | `backend/deploy/` |

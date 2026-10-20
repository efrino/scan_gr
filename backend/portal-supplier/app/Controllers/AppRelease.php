<?php

namespace App\Controllers;

use App\Libraries\ApkInfo;
use App\Libraries\GithubRelease;
use IonAuth\Libraries\IonAuth;

/**
 * CMS rilis aplikasi GR Scanner (khusus grup admin):
 * daftar versi, rilis APK baru, atur versi minimum, aktif/nonaktif,
 * dan statistik versi terpasang per device.
 */
class AppRelease extends BaseController
{
    private const PACKAGE  = 'com.example.scan_gr';
    private const PLATFORM = 'android';
    private const APK_DIR  = FCPATH . 'apk/';

    protected $ionAuth;

    public function __construct()
    {
        $this->ionAuth = new IonAuth();
        // Zona waktu server UTC; waktu rilis & device ditampilkan dalam WIB.
        date_default_timezone_set('Asia/Jakarta');
    }

    /** Hanya grup admin. Mengembalikan response jika ditolak. */
    private function guard()
    {
        if (! $this->ionAuth->loggedIn()) {
            return redirect()->to(base_url('auth/login'));
        }
        if (! $this->ionAuth->isAdmin()) {
            return $this->response->setStatusCode(403)->setBody(view('template/error_403'));
        }

        return null;
    }

    public function index()
    {
        if ($denied = $this->guard()) {
            return $denied;
        }

        $db = db_connect();

        $versions = $db->table('app_versions')
            ->where('platform', self::PLATFORM)
            ->orderBy('version_code', 'DESC')
            ->get()->getResultArray();

        $production = null;
        foreach ($versions as $v) {
            if ((int) $v['is_active'] === 1) {
                $production = $v;
                break;
            }
        }

        $since = date('Y-m-d H:i:s', strtotime('-30 days'));
        $stats = $db->table('app_devices')
            ->select('version_code, MAX(version_name) AS version_name, COUNT(*) AS total')
            ->where('platform', self::PLATFORM)
            ->where('last_seen >=', $since)
            ->groupBy('version_code')
            ->orderBy('version_code', 'DESC')
            ->get()->getResultArray();

        $devices = $db->table('app_devices')
            ->where('platform', self::PLATFORM)
            ->orderBy('last_seen', 'DESC')
            ->limit(200)
            ->get()->getResultArray();

        $data = [
            'title'         => 'Rilis Aplikasi GR Scanner',
            'ionAuth'       => $this->ionAuth,
            'current_user'  => $this->ionAuth->user()->row(),
            'versions'      => $versions,
            'production'    => $production,
            'stats'         => $stats,
            'devices'       => $devices,
            'githubReady'   => (new GithubRelease())->isConfigured(),
        ];

        return $this->_render_page('app_release/index', $data);
    }

    /** Unggah APK baru: baca versi dari APK, simpan, rilis ke GitHub, daftarkan. */
    public function store()
    {
        if ($denied = $this->guard()) {
            return $denied;
        }

        // APK dikirim bertahap lewat chunk() karena proxy nginx di depan mspin
        // membatasi ukuran request; di sini potongan dirakit jadi satu file.
        try {
            $tmpPath = $this->assembleChunks(
                (string) $this->request->getPost('upload_id'),
                (int) $this->request->getPost('total_chunks'),
                (string) $this->request->getPost('file_name')
            );
        } catch (\Throwable $e) {
            return $this->back('error', $e->getMessage());
        }

        try {
            $apk = ApkInfo::read($tmpPath);
        } catch (\Throwable $e) {
            @unlink($tmpPath);

            return $this->back('error', 'APK tidak bisa dibaca: ' . $e->getMessage());
        }

        if ($apk->package !== self::PACKAGE) {
            @unlink($tmpPath);

            return $this->back('error', "APK ini bukan GR Scanner (package {$apk->package}).");
        }

        $db     = db_connect();
        $latest = $db->table('app_versions')->where('platform', self::PLATFORM)
            ->selectMax('version_code')->get()->getRow()->version_code ?? 0;
        if ($apk->versionCode <= (int) $latest) {
            @unlink($tmpPath);

            return $this->back('error', "versionCode APK ({$apk->versionCode}) harus lebih besar dari versi "
                . "terakhir ({$latest}). Untuk rollback, build ulang kode lama dengan versionCode lebih tinggi.");
        }

        // "" = opsional (pakai minimum yang berlaku), "new" = wajib ke versi ini,
        // angka = wajib untuk versi di bawah build tersebut.
        $minInput = (string) $this->request->getPost('min_version_code');
        $min      = $minInput === 'new' ? $apk->versionCode : (int) $minInput;
        if ($min <= 0) {
            $current = $db->table('app_versions')->where('platform', self::PLATFORM)
                ->where('is_active', 1)->orderBy('version_code', 'DESC')->get(1)->getRow();
            $min = $current ? (int) $current->min_version_code : $apk->versionCode;
        }
        if ($min > $apk->versionCode) {
            @unlink($tmpPath);

            return $this->back('error', 'Versi minimum tidak boleh lebih besar dari versi yang dirilis.');
        }

        $notes = trim((string) $this->request->getPost('release_notes'));

        // Simpan salinan di server (sumber cadangan).
        if (! is_dir(self::APK_DIR)) {
            mkdir(self::APK_DIR, 0775, true);
        }
        $fileName = "scan_gr-{$apk->versionName}-{$apk->versionCode}.apk";
        $path = self::APK_DIR . $fileName;
        if (! @rename($tmpPath, $path)) {
            @unlink($tmpPath);

            return $this->back('error', 'Gagal menyimpan APK ke folder public/apk/ di server. '
                . 'Pastikan folder itu bisa ditulis oleh web server (www-data).');
        }
        @chmod($path, 0644);

        $localUrl = base_url('apk/' . $fileName);
        $sha256   = hash_file('sha256', $path);
        $size     = filesize($path);

        // Rilis ke GitHub (sumber utama). Jika gagal, tetap rilis dari server.
        $apkUrl  = $localUrl;
        $warning = null;
        $github  = new GithubRelease();
        if ($github->isConfigured()) {
            try {
                $apkUrl = $github->publish(
                    "v{$apk->versionName}-{$apk->versionCode}",
                    "GR Scanner {$apk->versionName} (build {$apk->versionCode})",
                    $notes !== '' ? $notes : "Build {$apk->versionCode}.",
                    $path,
                    $fileName
                );
            } catch (\Throwable $e) {
                $warning = 'GitHub gagal, APK diunduh dari server: ' . $e->getMessage();
                log_message('error', '[AppRelease] ' . $e->getMessage());
            }
        } else {
            $warning = 'GITHUB_TOKEN belum diisi, APK hanya diunduh dari server.';
        }

        $db->table('app_versions')->insert([
            'platform'         => self::PLATFORM,
            'version_code'     => $apk->versionCode,
            'version_name'     => $apk->versionName,
            'min_version_code' => $min,
            'apk_url'          => $apkUrl,
            'apk_url_local'    => $localUrl,
            'apk_size'         => $size,
            'apk_sha256'       => $sha256,
            'release_notes'    => $notes !== '' ? $notes : null,
            'is_active'        => 1,
            'released_at'      => date('Y-m-d H:i:s'),
            'created_by'       => $this->ionAuth->user()->row()->username ?? null,
        ]);

        $msg = "Versi {$apk->versionName} (build {$apk->versionCode}) dirilis. Device akan ditawari update saat app dibuka.";
        session()->setFlashdata('success', $msg);
        if ($warning) {
            session()->setFlashdata('warning', $warning);
        }

        return redirect()->to(base_url('app-release'));
    }

    /** Ubah versi minimum (wajib update) pada satu versi. */
    public function setMin(int $id)
    {
        if ($denied = $this->guard()) {
            return $denied;
        }

        $db  = db_connect();
        $row = $db->table('app_versions')->where('id', $id)->get()->getRow();
        if (! $row) {
            return $this->back('error', 'Versi tidak ditemukan.');
        }

        $min = (int) $this->request->getPost('min_version_code');
        if ($min <= 0 || $min > (int) $row->version_code) {
            return $this->back('error', "Versi minimum harus antara 1 dan {$row->version_code}.");
        }

        $db->table('app_versions')->where('id', $id)->update(['min_version_code' => $min]);

        $minName = $db->table('app_versions')->where('platform', $row->platform)
            ->where('version_code', $min)->get()->getRow()->version_name ?? "build {$min}";

        return $this->back('success', "Versi {$row->version_name}: versi tertua yang boleh dipakai sekarang {$minName}.");
    }

    /** Aktif/nonaktifkan versi. Versi aktif tertinggi adalah production. */
    public function toggle(int $id)
    {
        if ($denied = $this->guard()) {
            return $denied;
        }

        $db  = db_connect();
        $row = $db->table('app_versions')->where('id', $id)->get()->getRow();
        if (! $row) {
            return $this->back('error', 'Versi tidak ditemukan.');
        }

        $active = (int) $row->is_active === 1 ? 0 : 1;
        $db->table('app_versions')->where('id', $id)->update(['is_active' => $active]);

        return $this->back('success', "Versi {$row->version_name} " . ($active ? 'diaktifkan.' : 'dinonaktifkan.'));
    }

    // ── Upload bertahap ───────────────────────────────────────────────────────

    private const CHUNK_DIR  = WRITEPATH . 'uploads/apk_chunks/';
    private const CHUNK_MAX  = 900 * 1024;   // di bawah batas 1 MB proxy
    private const CHUNKS_MAX = 200;          // ±128 MB pada 640 KB per potong

    /** Terima satu potongan APK. Dipanggil berurutan oleh JS di halaman CMS. */
    public function chunk()
    {
        if (! $this->ionAuth->loggedIn() || ! $this->ionAuth->isAdmin()) {
            return $this->response->setStatusCode(403)
                ->setJSON(['ok' => false, 'message' => 'Sesi habis atau bukan admin. Muat ulang halaman.']);
        }

        $id    = (string) $this->request->getPost('upload_id');
        $index = (int) $this->request->getPost('index');
        $total = (int) $this->request->getPost('total');
        $part  = $this->request->getFile('chunk');

        if (! preg_match('/^[a-f0-9]{32}$/', $id) || $total < 1 || $total > self::CHUNKS_MAX
            || $index < 0 || $index >= $total) {
            return $this->response->setStatusCode(422)->setJSON(['ok' => false, 'message' => 'Data potongan tidak valid.']);
        }
        if (! $part || ! $part->isValid() || $part->getSize() > self::CHUNK_MAX) {
            return $this->response->setStatusCode(422)->setJSON(['ok' => false, 'message' => 'Potongan gagal diterima.']);
        }

        if ($index === 0) {
            $this->purgeOldChunks();
        }

        $dir = self::CHUNK_DIR . $id . '/';
        if (! is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        $part->move($dir, (string) $index, true);

        return $this->response->setJSON(['ok' => true, 'index' => $index]);
    }

    /** Rakit potongan jadi satu file sementara. Mengembalikan path file. */
    private function assembleChunks(string $id, int $total, string $fileName): string
    {
        if (! preg_match('/^[a-f0-9]{32}$/', $id) || $total < 1 || $total > self::CHUNKS_MAX) {
            throw new \RuntimeException('File APK belum dipilih atau unggahan belum selesai.');
        }
        if (strtolower(pathinfo($fileName, PATHINFO_EXTENSION)) !== 'apk') {
            throw new \RuntimeException('File harus berekstensi .apk.');
        }

        $dir = self::CHUNK_DIR . $id . '/';
        $out = self::CHUNK_DIR . $id . '.apk';
        $fh  = fopen($out, 'wb');
        try {
            for ($i = 0; $i < $total; $i++) {
                if (! is_file($dir . $i)) {
                    throw new \RuntimeException("Unggahan tidak lengkap (potongan {$i} hilang). Coba rilis ulang.");
                }
                fwrite($fh, file_get_contents($dir . $i));
            }
        } catch (\Throwable $e) {
            fclose($fh);
            @unlink($out);
            $this->removeDir($dir);
            throw $e;
        }
        fclose($fh);
        $this->removeDir($dir);

        return $out;
    }

    /** Hapus sisa unggahan yang tidak selesai (lebih dari 1 hari). */
    private function purgeOldChunks(): void
    {
        foreach (glob(self::CHUNK_DIR . '*') ?: [] as $p) {
            if (filemtime($p) < time() - 86400) {
                is_dir($p) ? $this->removeDir($p . '/') : @unlink($p);
            }
        }
    }

    private function removeDir(string $dir): void
    {
        foreach (glob($dir . '*') ?: [] as $f) {
            @unlink($f);
        }
        @rmdir($dir);
    }

    private function back(string $type, string $message)
    {
        session()->setFlashdata($type, $message);

        return redirect()->to(base_url('app-release'));
    }
}

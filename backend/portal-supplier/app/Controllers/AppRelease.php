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
            'downloadUrl'   => base_url('app/download'),
            'fonnteReady'   => env('FONNTE_TOKEN', '') !== '',
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

    // ── Bagikan aplikasi ──────────────────────────────────────────────────────

    /** QR Code link unduh tetap (app/download). ?download=1 untuk unduh PNG. */
    public function qr()
    {
        if ($denied = $this->guard()) {
            return $denied;
        }

        $qr = \Endroid\QrCode\QrCode::create(base_url('app/download'))
            ->setSize(600)
            ->setMargin(24);
        $png = (new \Endroid\QrCode\Writer\PngWriter())->write($qr)->getString();

        $this->response->setHeader('Content-Type', 'image/png')
            ->setHeader('Cache-Control', 'max-age=3600');
        if ($this->request->getGet('download')) {
            $this->response->setHeader('Content-Disposition', 'attachment; filename="qr-gr-scanner.png"');
        }

        return $this->response->setBody($png);
    }

    // ── WhatsApp lewat wa-gateway lokal (127.0.0.1) ───────────────────────

    /** Panggil wa-gateway lokal. @return array{0:int,1:array<string,mixed>} */
    private function gateway(string $method, string $path, ?array $body = null, int $timeout = 15): array
    {
        $ch = curl_init(rtrim((string) env('WA_GATEWAY_URL', 'http://127.0.0.1:3100'), '/') . $path);
        $headers = ['X-Gateway-Token: ' . env('WA_GATEWAY_TOKEN', '')];
        if ($body !== null) {
            $headers[] = 'Content-Type: application/json';
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        }
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_HTTPHEADER     => $headers,
        ]);
        $raw    = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($raw === false) {
            return [0, ['ok' => false, 'error' => 'Gateway WhatsApp tidak berjalan di server.']];
        }

        return [$status, json_decode($raw, true) ?: ['ok' => false, 'error' => 'Respons gateway tidak valid.']];
    }

    /** Status pengirim + QR pairing (data URI PNG) untuk dipoll halaman CMS. */
    public function waStatus()
    {
        if (! $this->ionAuth->loggedIn() || ! $this->ionAuth->isAdmin()) {
            return $this->response->setStatusCode(403)->setJSON(['ok' => false, 'error' => 'Sesi habis. Muat ulang halaman.']);
        }

        [, $s] = $this->gateway('GET', '/status');
        $out = [
            'ok'    => (bool) ($s['ok'] ?? false),
            'state' => $s['state'] ?? 'down',
            'me'    => $s['me'] ?? null,
            'error' => $s['error'] ?? null,
            'qr'    => null,
        ];
        if (! empty($s['qr'])) {
            $qr        = \Endroid\QrCode\QrCode::create($s['qr'])->setSize(320)->setMargin(12);
            $out['qr'] = (new \Endroid\QrCode\Writer\PngWriter())->write($qr)->getDataUri();
        }

        return $this->response->setHeader('Cache-Control', 'no-store')->setJSON($out);
    }

    /** Putuskan WhatsApp pengirim (untuk ganti nomor). */
    public function waLogout()
    {
        if (! $this->ionAuth->loggedIn() || ! $this->ionAuth->isAdmin()) {
            return $this->response->setStatusCode(403)->setJSON(['ok' => false, 'error' => 'Sesi habis. Muat ulang halaman.']);
        }
        [, $res] = $this->gateway('POST', '/logout', []);

        return $this->response->setJSON($res);
    }

    /**
     * Kirim pesan ke SATU nomor. Halaman CMS memanggil ini berurutan per nomor
     * (dengan jeda) supaya tiap request selesai jauh di bawah batas waktu proxy.
     */
    public function waSendOne()
    {
        if (! $this->ionAuth->loggedIn() || ! $this->ionAuth->isAdmin()) {
            return $this->response->setStatusCode(403)->setJSON(['ok' => false, 'error' => 'Sesi habis. Muat ulang halaman.']);
        }

        $message = trim((string) $this->request->getPost('message'));
        [$numbers, $invalid] = self::parseNumbers((string) $this->request->getPost('number'));
        if ($invalid || count($numbers) !== 1) {
            return $this->response->setStatusCode(422)->setJSON(['ok' => false, 'error' => 'Nomor tidak valid']);
        }
        if ($message === '') {
            return $this->response->setStatusCode(422)->setJSON(['ok' => false, 'error' => 'Pesan kosong']);
        }

        // Jalur utama Fonnte (jika FONNTE_TOKEN diisi), cadangan wa-gateway lokal.
        $errors = [];
        if (env('FONNTE_TOKEN', '') !== '') {
            [$ok, $err] = $this->sendFonnte($numbers[0], $message);
            if ($ok) {
                return $this->logWa($numbers[0], 'Fonnte', true);
            }
            $errors[] = 'Fonnte: ' . $err;
        }

        [$status, $res] = $this->gateway('POST', '/send', ['to' => $numbers, 'message' => $message], 45);
        $result = $res['results'][0] ?? ['ok' => false, 'error' => $res['error'] ?? "HTTP {$status}"];
        if ($result['ok']) {
            return $this->logWa($numbers[0], 'nomor cadangan', true);
        }
        $errors[] = 'Nomor cadangan: ' . ($result['error'] ?? 'gagal');

        return $this->logWa($numbers[0], null, false, implode('; ', $errors));
    }

    private function logWa(string $to, ?string $via, bool $ok, ?string $error = null)
    {
        log_message('info', "[AppRelease] WA ke {$to}: " . ($ok ? "terkirim via {$via}" : "gagal ({$error})"));

        return $this->response->setJSON(['ok' => $ok, 'to' => $to, 'via' => $via, 'error' => $error]);
    }

    /** Kirim ke satu nomor lewat Fonnte. @return array{0:bool,1:string} */
    private function sendFonnte(string $to, string $message): array
    {
        $ch = curl_init('https://api.fonnte.com/send');
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT        => 25,
            CURLOPT_HTTPHEADER     => ['Authorization: ' . env('FONNTE_TOKEN')],
            CURLOPT_POSTFIELDS     => ['target' => $to, 'message' => $message, 'countryCode' => '62'],
        ]);
        $body   = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err    = curl_error($ch);
        curl_close($ch);

        if ($body === false) {
            return [false, $err ?: 'tidak bisa menghubungi Fonnte'];
        }
        $res = json_decode($body, true) ?: [];

        return empty($res['status'])
            ? [false, (string) ($res['reason'] ?? "HTTP {$status}")]
            : [true, ''];
    }

    /**
     * Normalisasi nomor ke format 62xxxxxxxxxx. Pemisah: baris baru, koma, titik koma.
     *
     * @return array{0: list<string>, 1: list<string>} [nomor valid, nomor tidak valid]
     */
    public static function parseNumbers(string $raw): array
    {
        $valid = $invalid = [];
        foreach (preg_split('/[\r\n,;]+/', $raw) as $item) {
            $item = trim($item);
            if ($item === '') {
                continue;
            }
            $digits = preg_replace('/\D/', '', $item);
            if (str_starts_with($digits, '0')) {
                $digits = '62' . substr($digits, 1);
            } elseif (str_starts_with($digits, '8')) {
                $digits = '62' . $digits;
            }
            if (preg_match('/^628\d{7,12}$/', $digits)) {
                $valid[$digits] = $digits;
            } else {
                $invalid[] = $item;
            }
        }

        return [array_values($valid), $invalid];
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

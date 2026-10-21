<?php

namespace App\Controllers\RestApi;

use CodeIgniter\RESTful\ResourceController;

/**
 * Info versi aplikasi GR Scanner untuk cek update di client.
 * Publik (tanpa token) karena dipanggil sebelum login.
 */
class AppVersion extends ResourceController
{
    protected $format = 'json';

    public function latest()
    {
        date_default_timezone_set('Asia/Jakarta');
        $platform = $this->request->getGet('platform') ?: 'android';

        try {
            $db  = db_connect();
            $row = $db->table('app_versions')
                ->where('platform', $platform)
                ->where('is_active', 1)
                ->orderBy('version_code', 'DESC')
                ->get(1)
                ->getRowArray();

            $this->recordDevice($platform);

            if (empty($row)) {
                return $this->respond([
                    'status'  => false,
                    'message' => 'Versi aplikasi belum tersedia.',
                ], 404);
            }

            $this->response->setHeader('Cache-Control', 'no-cache');

            return $this->respond([
                'status'  => true,
                'message' => 'Versi aplikasi ditemukan.',
                'data'    => [
                    'platform'         => $row['platform'],
                    'version_code'     => (int) $row['version_code'],
                    'version_name'     => $row['version_name'],
                    'min_version_code' => (int) $row['min_version_code'],
                    'apk_url'          => $row['apk_url'],
                    'apk_url_local'    => $row['apk_url_local'] ?? null,
                    'apk_size'         => $row['apk_size'] !== null ? (int) $row['apk_size'] : null,
                    'apk_sha256'       => $row['apk_sha256'],
                    'release_notes'    => $row['release_notes'],
                    'released_at'      => $row['released_at'],
                ],
            ]);
        } catch (\Throwable $e) {
            log_message('error', '[AppVersion] ' . $e->getMessage());

            return $this->respond([
                'status'  => false,
                'message' => 'Gagal mengambil versi aplikasi.',
            ], 500);
        }
    }

    /**
     * Dipanggil GitHub Actions setelah membuat GitHub Release.
     * Mengunduh salinan APK ke public/apk, memverifikasi isinya, lalu mendaftarkan
     * versi ke app_versions. Dilindungi header X-Release-Token (RELEASE_HOOK_TOKEN di .env).
     */
    public function releaseHook()
    {
        date_default_timezone_set('Asia/Jakarta');

        $expected = (string) env('RELEASE_HOOK_TOKEN', '');
        $given    = (string) $this->request->getHeaderLine('X-Release-Token');
        if ($expected === '' || ! hash_equals($expected, $given)) {
            return $this->respond(['status' => false, 'message' => 'Token rilis tidak valid.'], 401);
        }

        $in   = (array) ($this->request->getJSON(true) ?? []);
        $name = (string) ($in['version_name'] ?? '');
        $code = (int) ($in['version_code'] ?? 0);
        $min  = (int) ($in['min_version_code'] ?? $code);
        $url  = (string) ($in['apk_url'] ?? '');
        $sha  = strtolower((string) ($in['apk_sha256'] ?? ''));
        $size = (int) ($in['apk_size'] ?? 0);

        if (! preg_match('/^\d+\.\d+\.\d+$/', $name) || $code <= 0 || $min <= 0 || $min > $code
            || ! preg_match('#^https://github\.com/efrino/scan_gr/releases/download/#', $url)
            || ! preg_match('/^[a-f0-9]{64}$/', $sha)) {
            return $this->respond(['status' => false, 'message' => 'Data rilis tidak valid.'], 422);
        }

        $db = db_connect();
        if ($db->table('app_versions')->where('platform', 'android')->where('version_code', $code)->countAllResults() > 0) {
            return $this->respond(['status' => true, 'message' => "Build {$code} sudah terdaftar."]);
        }
        $latest = (int) ($db->table('app_versions')->where('platform', 'android')
            ->selectMax('version_code')->get()->getRow()->version_code ?? 0);
        if ($code <= $latest) {
            return $this->respond(['status' => false, 'message' => "Build {$code} harus lebih besar dari {$latest}."], 409);
        }

        // Unduhan ±70 MB bisa lebih lama dari batas proxy; tetap lanjut walau
        // koneksi pemanggil terputus (Actions memastikan hasil lewat api/app/version).
        ignore_user_abort(true);
        set_time_limit(600);

        $dir = FCPATH . 'apk/';
        if (! is_dir($dir)) {
            mkdir($dir, 0777, true);
        }
        $fileName = "scan_gr-{$name}-{$code}.apk";
        $tmp      = $dir . $fileName . '.part';
        $path     = $dir . $fileName;

        try {
            $fh = fopen($tmp, 'wb');
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_FILE           => $fh,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_CONNECTTIMEOUT => 20,
                CURLOPT_TIMEOUT        => 540,
                CURLOPT_USERAGENT      => 'portal-supplier-release-hook',
            ]);
            $ok     = curl_exec($ch);
            $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $err    = curl_error($ch);
            curl_close($ch);
            fclose($fh);

            if (! $ok || $status !== 200) {
                throw new \RuntimeException("Gagal unduh APK dari GitHub (HTTP {$status} {$err}).");
            }
            if ($size > 0 && filesize($tmp) !== $size) {
                throw new \RuntimeException('Ukuran APK tidak cocok.');
            }
            if (hash_file('sha256', $tmp) !== $sha) {
                throw new \RuntimeException('sha256 APK tidak cocok.');
            }
            $apk = \App\Libraries\ApkInfo::read($tmp);
            if ($apk->package !== 'com.example.scan_gr' || $apk->versionCode !== $code || $apk->versionName !== $name) {
                throw new \RuntimeException("Isi APK ({$apk->package} {$apk->versionName}/{$apk->versionCode}) tidak sesuai data rilis.");
            }
            rename($tmp, $path);
            @chmod($path, 0644);
        } catch (\Throwable $e) {
            @unlink($tmp);
            log_message('error', '[ReleaseHook] ' . $e->getMessage());

            return $this->respond(['status' => false, 'message' => $e->getMessage()], 502);
        }

        $db->table('app_versions')->insert([
            'platform'         => 'android',
            'version_code'     => $code,
            'version_name'     => $name,
            'min_version_code' => $min,
            'apk_url'          => $url,
            'apk_url_local'    => base_url('apk/' . $fileName),
            'apk_size'         => filesize($path),
            'apk_sha256'       => $sha,
            'release_notes'    => trim((string) ($in['release_notes'] ?? '')) ?: null,
            'is_active'        => 1,
            'released_at'      => date('Y-m-d H:i:s'),
            'created_by'       => 'github-actions',
        ]);

        return $this->respond(['status' => true, 'message' => "Versi {$name} (build {$code}) terdaftar."], 201);
    }

    /**
     * Catat versi terpasang per device untuk statistik di CMS.
     * Gagal mencatat tidak boleh menggagalkan cek versi.
     */
    /**
     * POST /api/app/fcm-token (butuh token login)
     * Simpan token FCM device agar CMS bisa mengirim notifikasi ke device tertentu.
     */
    public function fcmToken()
    {
        $json     = $this->request->getJSON(true) ?? [];
        $deviceId = trim((string) ($json['device_id'] ?? ''));
        $fcm      = trim((string) ($json['fcm_token'] ?? ''));
        if (! preg_match('/^[A-Za-z0-9-]{8,64}$/', $deviceId) || $fcm === '' || strlen($fcm) > 255) {
            return $this->respond(['status' => false, 'message' => 'device_id / fcm_token tidak valid.'], 422);
        }

        $user = $this->request->apiUser ?? [];
        $now  = date('Y-m-d H:i:s');
        $data = [
            'fcm_token'    => $fcm,
            'nik'          => mb_substr((string) ($user['nik_user'] ?? ''), 0, 50) ?: null,
            'device_model' => mb_substr(trim((string) ($json['device_model'] ?? '')), 0, 100) ?: null,
            'ip_address'   => $this->request->getIPAddress(),
            'last_seen'    => $now,
        ];

        $db = db_connect();
        // Token FCM yang sama tidak boleh menempel di device lain (app di-reinstall).
        $db->table('app_devices')->where('fcm_token', $fcm)->where('device_id !=', $deviceId)->update(['fcm_token' => null]);
        if ($db->table('app_devices')->where('device_id', $deviceId)->countAllResults() > 0) {
            $db->table('app_devices')->where('device_id', $deviceId)->update($data);
        } else {
            $db->table('app_devices')->insert($data + [
                'device_id' => $deviceId, 'platform' => 'android', 'version_code' => 0, 'first_seen' => $now,
            ]);
        }

        return $this->respond(['status' => true, 'message' => 'Token notifikasi tersimpan.']);
    }

    private function recordDevice(string $platform): void
    {
        $deviceId = trim((string) $this->request->getGet('device_id'));
        $code     = (int) $this->request->getGet('current_version_code');
        if ($deviceId === '' || $code <= 0 || ! preg_match('/^[A-Za-z0-9-]{8,64}$/', $deviceId)) {
            return;
        }

        try {
            $now  = date('Y-m-d H:i:s');
            $data = [
                'platform'     => $platform,
                'nik'          => mb_substr(trim((string) $this->request->getGet('nik')), 0, 50) ?: null,
                'device_model' => mb_substr(trim((string) $this->request->getGet('device_model')), 0, 100) ?: null,
                'version_code' => $code,
                'version_name' => mb_substr(trim((string) $this->request->getGet('current_version_name')), 0, 20) ?: null,
                'ip_address'   => $this->request->getIPAddress(),
                'last_seen'    => $now,
            ];

            $table = db_connect()->table('app_devices');
            if ($table->where('device_id', $deviceId)->countAllResults() > 0) {
                db_connect()->table('app_devices')->where('device_id', $deviceId)->update($data);
            } else {
                db_connect()->table('app_devices')->insert($data + ['device_id' => $deviceId, 'first_seen' => $now]);
            }
        } catch (\Throwable $e) {
            log_message('error', '[AppVersion] gagal catat device: ' . $e->getMessage());
        }
    }
}

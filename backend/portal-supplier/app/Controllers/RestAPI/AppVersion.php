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
     * Catat versi terpasang per device untuk statistik di CMS.
     * Gagal mencatat tidak boleh menggagalkan cek versi.
     */
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

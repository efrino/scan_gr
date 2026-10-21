<?php

namespace App\Filters;

use App\Libraries\ApiTokens;
use App\Libraries\SapHealth;
use App\Models\M_auth;
use CodeIgniter\Filters\FilterInterface;
use CodeIgniter\HTTP\RequestInterface;
use CodeIgniter\HTTP\ResponseInterface;

class ApiTokenFilter implements FilterInterface
{
    public function before(RequestInterface $request, $arguments = null)
    {
        $authHeader = $request->getHeaderLine('Authorization');

        if (!$authHeader || !str_starts_with($authHeader, 'Bearer ')) {
            return service('response')
                ->setStatusCode(401)
                ->setJSON([
                    'status'  => false,
                    'message' => 'Token tidak ditemukan.',
                ]);
        }

        $token     = substr($authHeader, 7);
        $userModel = new M_auth();

        // Token per device (tabel api_tokens), masa berlaku bergeser.
        $row = ApiTokens::verify($token);
        if ($row) {
            $user = $userModel->find($row['user_id']);
            if ($user) {
                $request->apiUser = $user;
                return;
            }
        }

        // Token lama di users.api_token: tetap diterima sampai kedaluwarsa,
        // supaya device yang login sebelum perubahan ini tidak terlempar.
        $user = $userModel->where('api_token', $token)->first();

        if (!$user) {
            return service('response')
                ->setStatusCode(401)
                ->setJSON([
                    'status'  => false,
                    'message' => 'Token tidak valid.',
                ]);
        }

        // Cek apakah token sudah expired
        if ($user['api_token_expiry'] && strtotime($user['api_token_expiry']) < time()) {
            // Hapus token yang expired
            $userModel->update($user['id'], [
                'api_token'        => null,
                'api_token_expiry' => null,
            ]);

            return service('response')
                ->setStatusCode(401)
                ->setJSON([
                    'status'  => false,
                    'message' => 'Token sudah expired, silakan login kembali.',
                ]);
        }

        $request->apiUser = $user;
    }

    /**
     * Sisipkan status SAP dan build GR Scanner terbaru di setiap respons API, supaya app tahu
     * ada update tanpa menunggu jadwal cek versi. Di-cache 60 detik.
     */
    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        // Status SAP untuk banner di app (gangguan dideteksi SapHealth).
        $response->setHeader('X-System-Status', SapHealth::isDown() ? 'sap=down' : 'sap=ok');

        $latest = cache('app_latest_build_android');
        if ($latest === null) {
            try {
                $row = db_connect()->table('app_versions')
                    ->select('version_code')
                    ->where('platform', 'android')
                    ->where('is_active', 1)
                    ->orderBy('version_code', 'DESC')
                    ->get(1)->getRowArray();
                $latest = (int) ($row['version_code'] ?? 0);
                cache()->save('app_latest_build_android', $latest, 60);
            } catch (\Throwable $e) {
                return $response;
            }
        }
        if ($latest > 0) {
            $response->setHeader('X-App-Latest-Build', (string) $latest);
        }
        return $response;
    }
}

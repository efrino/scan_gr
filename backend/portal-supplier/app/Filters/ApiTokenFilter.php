<?php

namespace App\Filters;

use App\Libraries\ApiTokens;
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

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        //
    }
}

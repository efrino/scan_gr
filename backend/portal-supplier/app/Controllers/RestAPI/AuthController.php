<?php

namespace App\Controllers\RestApi;

use App\Libraries\ApiTokens;
use App\Models\M_auth;
use CodeIgniter\RESTful\ResourceController;

class AuthController extends ResourceController
{
    protected $format = 'json';

    public function login()
    {
        $json     = $this->request->getJSON();
        $email    = $json->email ?? null;
        $password = $json->password ?? null;

        if (!$email || !$password) {
            return $this->respond([
                'status'  => false,
                'message' => 'Email dan password wajib diisi.',
            ], 422);
        }

        $userModel = new M_auth();
        $user      = $userModel->where('email', $email)->first();

        if (!$user || !password_verify($password, $user['password'])) {
            return $this->respond([
                'status'  => false,
                'message' => 'Email atau password salah.',
            ], 401);
        }

        // Token per device: login di device lain tidak membuang sesi device ini.
        // App lama belum mengirim device_id; pakai sidik jari IP + User-Agent.
        $deviceId = trim((string) ($json?->device_id ?? ''));
        if ($deviceId === '') {
            $deviceId = 'legacy-' . substr(hash('sha256', $this->request->getIPAddress() . '|' . $this->request->getUserAgent()), 0, 32);
        }
        $deviceModel = isset($json?->device_model) ? substr((string) $json->device_model, 0, 100) : null;

        [$token, $expiry] = ApiTokens::issue(
            (int) $user['id'],
            substr($deviceId, 0, 64),
            $deviceModel,
            $this->request->getIPAddress()
        );

        unset($user['password'], $user['api_token'], $user['api_token_expiry']);

        return $this->respond([
            'status'     => true,
            'message'    => 'Login berhasil.',
            'token'      => $token,
            'expired_at' => $expiry,
            'user'       => $user,
        ], 200);
    }

    public function me()
    {
        $user = $this->request->apiUser;
        unset($user['password'], $user['api_token'], $user['api_token_expiry']);

        return $this->respond([
            'status' => true,
            'user'   => $user,
        ], 200);
    }

    public function logout()
    {
        // Cabut token device ini saja; device lain tetap login.
        $token = substr($this->request->getHeaderLine('Authorization'), 7);
        ApiTokens::revoke($token);

        $user = $this->request->apiUser;
        if (($user['api_token'] ?? null) === $token) {
            (new M_auth())->update($user['id'], [
                'api_token'        => null,
                'api_token_expiry' => null,
            ]);
        }

        return $this->respond([
            'status'  => true,
            'message' => 'Logout berhasil.',
        ], 200);
    }
}

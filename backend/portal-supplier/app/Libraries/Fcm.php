<?php

namespace App\Libraries;

/**
 * Kirim push notification lewat Firebase Cloud Messaging HTTP v1.
 *
 * Kredensial: service account JSON di writable/firebase-service-account.json
 * (tidak masuk repo). Access token OAuth2 dibuat dari JWT yang ditandatangani
 * kunci service account, lalu di-cache sampai mendekati kedaluwarsa.
 */
class Fcm
{
    /** Topik yang diikuti semua device GR Scanner. */
    public const TOPIC = 'gr-scanner';

    private const SCOPE     = 'https://www.googleapis.com/auth/firebase.messaging';
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';
    private const CACHE_KEY = 'fcm_access_token';

    private static function account(): ?array
    {
        $file = WRITEPATH . 'firebase-service-account.json';
        if (! is_file($file)) {
            return null;
        }
        $json = json_decode((string) file_get_contents($file), true);
        return is_array($json) && isset($json['private_key'], $json['client_email'], $json['project_id'])
            ? $json
            : null;
    }

    public static function configured(): bool
    {
        return self::account() !== null;
    }

    private static function b64url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function accessToken(array $sa): ?string
    {
        $cached = cache(self::CACHE_KEY);
        if (is_string($cached) && $cached !== '') {
            return $cached;
        }

        $now    = time();
        $header = self::b64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
        $claims = self::b64url(json_encode([
            'iss'   => $sa['client_email'],
            'scope' => self::SCOPE,
            'aud'   => self::TOKEN_URL,
            'iat'   => $now,
            'exp'   => $now + 3600,
        ]));
        $input = $header . '.' . $claims;
        if (! openssl_sign($input, $sig, $sa['private_key'], 'sha256WithRSAEncryption')) {
            log_message('error', 'FCM: gagal menandatangani JWT');
            return null;
        }

        $res = self::post(self::TOKEN_URL, http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $input . '.' . self::b64url($sig),
        ]), ['Content-Type: application/x-www-form-urlencoded']);

        $token = $res['body']['access_token'] ?? null;
        if (! $token) {
            log_message('error', 'FCM: access token gagal, HTTP ' . $res['code']);
            return null;
        }
        cache()->save(self::CACHE_KEY, $token, (int) ($res['body']['expires_in'] ?? 3600) - 300);
        return $token;
    }

    private static function post(string $url, string $body, array $headers): array
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT        => 15,
        ]);
        $raw  = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return ['code' => $code, 'body' => json_decode((string) $raw, true) ?: []];
    }

    /**
     * Kirim ke topik (semua device) atau ke satu token device.
     * [data] hanya boleh berisi string. Mengembalikan true jika diterima FCM.
     */
    public static function send(string $title, string $body, array $data = [], ?string $deviceToken = null): bool
    {
        $sa = self::account();
        if (! $sa) {
            log_message('error', 'FCM: service account belum dipasang');
            return false;
        }
        $access = self::accessToken($sa);
        if (! $access) {
            return false;
        }

        $message = [
            'notification' => ['title' => $title, 'body' => $body],
            'data'         => array_map('strval', $data),
            'android'      => [
                'priority'     => 'high',
                'notification' => ['channel_id' => 'gr_info'],
            ],
        ];
        $message[$deviceToken ? 'token' : 'topic'] = $deviceToken ?: self::TOPIC;

        $res = self::post(
            'https://fcm.googleapis.com/v1/projects/' . $sa['project_id'] . '/messages:send',
            json_encode(['message' => $message]),
            ['Content-Type: application/json', 'Authorization: Bearer ' . $access]
        );

        if ($res['code'] !== 200) {
            log_message('error', 'FCM: kirim gagal HTTP ' . $res['code'] . ' ' . json_encode($res['body']['error']['message'] ?? ''));
            if ($res['code'] === 401) {
                cache()->delete(self::CACHE_KEY);
            }
            return false;
        }
        return true;
    }
}

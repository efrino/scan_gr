<?php

namespace App\Libraries;

/**
 * Token API per device dengan masa berlaku bergeser (sliding expiry).
 *
 * - Satu token per pasangan user + device; login ulang di device yang sama
 *   mengganti token device itu saja.
 * - Masa berlaku diperpanjang setiap token dipakai, jadi operator yang aktif
 *   tidak pernah terlempar ke halaman login.
 * - Hanya hash SHA-256 yang disimpan.
 */
class ApiTokens
{
    /** Token kedaluwarsa jika tidak dipakai selama ini. */
    public const IDLE_DAYS = 30;

    /** Perpanjangan ditulis paling sering sekali per interval ini (detik). */
    private const TOUCH_INTERVAL = 3600;

    private const TABLE = 'api_tokens';

    public static function hash(string $token): string
    {
        return hash('sha256', $token);
    }

    private static function expiry(): string
    {
        return date('Y-m-d H:i:s', strtotime('+' . self::IDLE_DAYS . ' days'));
    }

    /**
     * Buat token baru untuk device. Mengembalikan [token asli, expires_at].
     */
    public static function issue(int $userId, string $deviceId, ?string $deviceModel, ?string $ip): array
    {
        $db    = db_connect();
        $token = bin2hex(random_bytes(32));
        $now   = date('Y-m-d H:i:s');
        $exp   = self::expiry();

        // Bersihkan token kedaluwarsa milik user ini sekalian.
        $db->table(self::TABLE)
            ->where('user_id', $userId)
            ->groupStart()
                ->where('device_id', $deviceId)
                ->orWhere('expires_at <', $now)
            ->groupEnd()
            ->delete();

        $db->table(self::TABLE)->insert([
            'user_id'      => $userId,
            'device_id'    => $deviceId,
            'device_model' => $deviceModel,
            'token_hash'   => self::hash($token),
            'ip_address'   => $ip,
            'created_at'   => $now,
            'last_used_at' => $now,
            'expires_at'   => $exp,
        ]);

        return [$token, $exp];
    }

    /**
     * Cari token yang masih berlaku dan perpanjang masa berlakunya.
     * Mengembalikan baris api_tokens atau null.
     */
    public static function verify(string $token): ?array
    {
        $db  = db_connect();
        $row = $db->table(self::TABLE)
            ->where('token_hash', self::hash($token))
            ->get()->getRowArray();

        if (! $row) {
            return null;
        }

        if (strtotime($row['expires_at']) < time()) {
            $db->table(self::TABLE)->where('id', $row['id'])->delete();
            return null;
        }

        if (time() - strtotime((string) $row['last_used_at']) >= self::TOUCH_INTERVAL) {
            $db->table(self::TABLE)->where('id', $row['id'])->update([
                'last_used_at' => date('Y-m-d H:i:s'),
                'expires_at'   => self::expiry(),
            ]);
        }

        return $row;
    }

    /** Cabut satu token (logout device ini saja). */
    public static function revoke(string $token): void
    {
        db_connect()->table(self::TABLE)
            ->where('token_hash', self::hash($token))
            ->delete();
    }
}

<?php

namespace App\Libraries;

/**
 * Pantau kesehatan koneksi ke SAP dari hasil setiap pemanggilan M_curl.
 *
 * - Gagal beruntun sebanyak FAIL_THRESHOLD: status jadi "down" dan semua
 *   operator dikirimi push notification.
 * - Satu pemanggilan berhasil saat "down": status kembali "ok" dan dikirimi
 *   push pemulihan.
 * - Status juga dikirim ke app lewat header X-System-Status (ApiTokenFilter).
 *
 * Status disimpan di cache CodeIgniter, jadi berlaku lintas request.
 */
class SapHealth
{
    public const FAIL_THRESHOLD = 3;

    /** Pemanggilan lebih lama dari ini dihitung gagal (detik). */
    public const SLOW_SECONDS = 30;

    /** Status "down" otomatis dilupakan jika tidak ada pemanggilan sama sekali. */
    private const STATE_TTL = 6 * 3600;

    private const KEY_STATE = 'sap_health_state';
    private const KEY_FAILS = 'sap_health_fails';

    public const MSG_DOWN = 'Server SAP sedang gangguan. Scan tetap tersimpan di perangkat dan akan terkirim otomatis.';
    public const MSG_UP   = 'Server SAP sudah normal kembali. Antrian scan sedang dikirim.';

    public static function isDown(): bool
    {
        return cache(self::KEY_STATE) === 'down';
    }

    /**
     * Catat hasil satu pemanggilan SAP. Tidak pernah melempar exception agar
     * tidak mengganggu proses pemanggil.
     */
    public static function observe($response, float $seconds): void
    {
        try {
            if (self::isFailure($response, $seconds)) {
                $fails = (int) cache(self::KEY_FAILS) + 1;
                cache()->save(self::KEY_FAILS, $fails, 3600);
                if ($fails >= self::FAIL_THRESHOLD && ! self::isDown()) {
                    self::setDown(true, 'otomatis');
                }
                return;
            }
            cache()->delete(self::KEY_FAILS);
            if (self::isDown()) {
                self::setDown(false, 'otomatis');
            }
        } catch (\Throwable $e) {
            log_message('error', 'SapHealth: ' . $e->getMessage());
        }
    }

    /**
     * Hanya kegagalan koneksi yang dihitung. Penolakan bisnis dari SAP
     * (mis. "sudah discan") berarti SAP justru sedang hidup.
     */
    private static function isFailure($response, float $seconds): bool
    {
        if ($seconds >= self::SLOW_SECONDS || ! is_array($response)) {
            return true;
        }
        $msg = strtolower((string) ($response['message'] ?? ''));
        foreach (['could not open connection', 'connection refused', 'timed out', 'rfc_communication', 'partner not reached'] as $sign) {
            if (str_contains($msg, $sign)) {
                return true;
            }
        }
        return false;
    }

    /** Ubah status dan kirim push. Dipakai otomatis maupun dari CMS. */
    public static function setDown(bool $down, string $by): void
    {
        if ($down) {
            cache()->save(self::KEY_STATE, 'down', self::STATE_TTL);
        } else {
            cache()->delete(self::KEY_STATE);
            cache()->delete(self::KEY_FAILS);
        }
        log_message('notice', 'SapHealth: status ' . ($down ? 'DOWN' : 'OK') . " ($by)");

        Fcm::send(
            $down ? 'SAP sedang gangguan' : 'SAP normal kembali',
            $down ? self::MSG_DOWN : self::MSG_UP,
            [
                'type'    => 'sap_status',
                'state'   => $down ? 'down' : 'ok',
                'message' => $down ? self::MSG_DOWN : self::MSG_UP,
            ]
        );
    }
}

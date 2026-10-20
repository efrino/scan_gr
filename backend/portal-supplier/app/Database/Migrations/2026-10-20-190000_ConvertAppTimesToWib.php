<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

/**
 * Sebelum perbaikan zona waktu, sebagian waktu tersimpan dalam UTC:
 * rilis build 2 dan 3, serta semua catatan device. Geser ke WIB (+7 jam).
 * Rilis build 1 sudah diisi dalam WIB sejak awal.
 */
class ConvertAppTimesToWib extends Migration
{
    public function up()
    {
        $this->db->query(
            "UPDATE app_versions SET released_at = DATE_ADD(released_at, INTERVAL 7 HOUR)
             WHERE platform = 'android' AND version_code IN (2, 3)"
        );
        $this->db->query(
            'UPDATE app_devices SET last_seen = DATE_ADD(last_seen, INTERVAL 7 HOUR),
                                    first_seen = DATE_ADD(first_seen, INTERVAL 7 HOUR)'
        );
    }

    public function down()
    {
        $this->db->query(
            "UPDATE app_versions SET released_at = DATE_SUB(released_at, INTERVAL 7 HOUR)
             WHERE platform = 'android' AND version_code IN (2, 3)"
        );
        $this->db->query(
            'UPDATE app_devices SET last_seen = DATE_SUB(last_seen, INTERVAL 7 HOUR),
                                    first_seen = DATE_SUB(first_seen, INTERVAL 7 HOUR)'
        );
    }
}

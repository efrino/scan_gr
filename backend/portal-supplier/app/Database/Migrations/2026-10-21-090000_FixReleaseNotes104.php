<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

/**
 * Rilis 1.0.4 (build 5) tercatat dengan daftar commit teknis sebagai catatan rilis
 * (bug workflow CI). Ganti dengan catatan yang dipahami operator.
 */
class FixReleaseNotes104 extends Migration
{
    private const NOTES = "- Aplikasi mengecek pembaruan otomatis tiap 15 menit selama terbuka\n"
        . '- Perbaikan stabilitas';

    public function up()
    {
        $this->db->table('app_versions')
            ->where('platform', 'android')
            ->where('version_code', 5)
            ->update(['release_notes' => self::NOTES]);
    }

    public function down()
    {
        // Catatan lama (daftar commit) sengaja tidak dikembalikan.
    }
}

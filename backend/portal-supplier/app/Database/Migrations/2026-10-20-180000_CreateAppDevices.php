<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

/**
 * Versi GR Scanner terakhir yang dilaporkan tiap device saat cek update.
 * Satu baris per device (device_id dibuat app, disimpan di device).
 */
class CreateAppDevices extends Migration
{
    public function up()
    {
        $this->forge->addField([
            'id'           => ['type' => 'INT', 'unsigned' => true, 'auto_increment' => true],
            'device_id'    => ['type' => 'VARCHAR', 'constraint' => 64],
            'platform'     => ['type' => 'VARCHAR', 'constraint' => 20, 'default' => 'android'],
            'nik'          => ['type' => 'VARCHAR', 'constraint' => 50, 'null' => true],
            'device_model' => ['type' => 'VARCHAR', 'constraint' => 100, 'null' => true],
            'version_code' => ['type' => 'INT', 'unsigned' => true],
            'version_name' => ['type' => 'VARCHAR', 'constraint' => 20, 'null' => true],
            'ip_address'   => ['type' => 'VARCHAR', 'constraint' => 45, 'null' => true],
            'first_seen'   => ['type' => 'DATETIME', 'null' => true],
            'last_seen'    => ['type' => 'DATETIME', 'null' => true],
        ]);
        $this->forge->addPrimaryKey('id');
        $this->forge->addUniqueKey('device_id', 'uq_device_id');
        $this->forge->addKey('last_seen');
        $this->forge->createTable('app_devices', true, ['ENGINE' => 'InnoDB']);
    }

    public function down()
    {
        $this->forge->dropTable('app_devices', true);
    }
}

<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

/**
 * Token FCM per device untuk push notification ke device tertentu.
 */
class AddFcmTokenToAppDevices extends Migration
{
    public function up()
    {
        $this->forge->addColumn('app_devices', [
            'fcm_token' => ['type' => 'VARCHAR', 'constraint' => 255, 'null' => true, 'after' => 'device_model'],
        ]);
    }

    public function down()
    {
        $this->forge->dropColumn('app_devices', 'fcm_token');
    }
}

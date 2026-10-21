<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

/**
 * Token API per device. Sebelumnya token disimpan di users.api_token (satu
 * token per akun), sehingga login di device lain membuang sesi device lama.
 * Token disimpan sebagai hash SHA-256, bukan teks asli.
 */
class CreateApiTokens extends Migration
{
    public function up()
    {
        $this->forge->addField([
            'id'           => ['type' => 'INT', 'unsigned' => true, 'auto_increment' => true],
            'user_id'      => ['type' => 'INT', 'unsigned' => true],
            'device_id'    => ['type' => 'VARCHAR', 'constraint' => 64],
            'device_model' => ['type' => 'VARCHAR', 'constraint' => 100, 'null' => true],
            'token_hash'   => ['type' => 'CHAR', 'constraint' => 64],
            'ip_address'   => ['type' => 'VARCHAR', 'constraint' => 45, 'null' => true],
            'created_at'   => ['type' => 'DATETIME', 'null' => true],
            'last_used_at' => ['type' => 'DATETIME', 'null' => true],
            'expires_at'   => ['type' => 'DATETIME'],
        ]);
        $this->forge->addPrimaryKey('id');
        $this->forge->addUniqueKey('token_hash', 'uq_token_hash');
        $this->forge->addUniqueKey(['user_id', 'device_id'], 'uq_user_device');
        $this->forge->addKey('expires_at');
        $this->forge->createTable('api_tokens', true, ['ENGINE' => 'InnoDB']);
    }

    public function down()
    {
        $this->forge->dropTable('api_tokens', true);
    }
}

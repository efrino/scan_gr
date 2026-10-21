<?php

namespace App\Controllers;

use CodeIgniter\Controller;

/**
 * Halaman unduh GR Scanner untuk dibagikan (QR / WhatsApp). Publik, tanpa login.
 * Link tetap: selalu menunjuk versi Production terbaru di app_versions.
 */
class AppDownload extends Controller
{
    private function production(): ?array
    {
        return db_connect()->table('app_versions')
            ->where('platform', 'android')
            ->where('is_active', 1)
            ->orderBy('version_code', 'DESC')
            ->get(1)->getRowArray() ?: null;
    }

    /** Halaman info + tombol unduh. */
    public function index()
    {
        $v = $this->production();

        return view('app_release/download', ['v' => $v]);
    }

    /** Langsung ke file APK. ?src=server untuk salinan di server ini. */
    public function apk()
    {
        $v = $this->production();
        if (! $v) {
            return $this->response->setStatusCode(404)->setBody('Aplikasi belum tersedia.');
        }

        $url = $this->request->getGet('src') === 'server' && ! empty($v['apk_url_local'])
            ? $v['apk_url_local']
            : $v['apk_url'];

        return redirect()->to($url);
    }
}

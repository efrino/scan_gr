<?php

namespace App\Libraries;

use RuntimeException;

/**
 * Buat GitHub Release dan unggah APK sebagai asset.
 *
 * Konfigurasi di .env:
 *   GITHUB_TOKEN = token fine-grained, izin "Contents: Read and write" ke repo
 *   GITHUB_REPO  = efrino/scan_gr
 */
class GithubRelease
{
    private string $token;
    private string $repo;

    public function __construct()
    {
        $this->token = (string) env('GITHUB_TOKEN', '');
        $this->repo  = (string) env('GITHUB_REPO', 'efrino/scan_gr');
    }

    public function isConfigured(): bool
    {
        return $this->token !== '' && $this->repo !== '';
    }

    /**
     * @return string URL unduh asset (browser_download_url)
     */
    public function publish(string $tag, string $title, string $notes, string $apkPath, string $assetName): string
    {
        if (! $this->isConfigured()) {
            throw new RuntimeException('GITHUB_TOKEN belum diisi di .env server.');
        }

        [$status, $release] = $this->request('POST', "https://api.github.com/repos/{$this->repo}/releases", [
            'tag_name'         => $tag,
            'target_commitish' => 'main',
            'name'             => $title,
            'body'             => $notes,
        ]);
        if ($status !== 201 || empty($release['upload_url'])) {
            $msg = $release['message'] ?? "HTTP {$status}";
            if (! empty($release['errors'][0]['code'])) {
                $msg .= ' (' . $release['errors'][0]['code'] . ')';
            }
            throw new RuntimeException("Gagal membuat release {$tag}: {$msg}");
        }

        $uploadUrl = preg_replace('/\{.*\}$/', '', $release['upload_url'])
            . '?name=' . rawurlencode($assetName);
        [$status, $asset] = $this->request('POST', $uploadUrl, null, $apkPath);
        if ($status !== 201 || empty($asset['browser_download_url'])) {
            $msg = $asset['message'] ?? "HTTP {$status}";
            throw new RuntimeException("Release {$tag} dibuat, tapi unggah APK gagal: {$msg}");
        }

        return $asset['browser_download_url'];
    }

    /**
     * @return array{0:int,1:array<string,mixed>}
     */
    private function request(string $method, string $url, ?array $json, ?string $file = null): array
    {
        $headers = [
            'Accept: application/vnd.github+json',
            'Authorization: Bearer ' . $this->token,
            'X-GitHub-Api-Version: 2022-11-28',
            'User-Agent: portal-supplier-app-release',
        ];

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 15,
            CURLOPT_TIMEOUT        => 600,
        ]);

        if ($file !== null) {
            $fh = fopen($file, 'rb');
            $headers[] = 'Content-Type: application/vnd.android.package-archive';
            $headers[] = 'Content-Length: ' . filesize($file);
            curl_setopt_array($ch, [
                CURLOPT_UPLOAD     => true,
                CURLOPT_INFILE     => $fh,
                CURLOPT_INFILESIZE => filesize($file),
            ]);
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');
        } elseif ($json !== null) {
            $headers[] = 'Content-Type: application/json';
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($json));
        }
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

        $body   = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error  = curl_error($ch);
        curl_close($ch);
        if (isset($fh)) {
            fclose($fh);
        }

        if ($body === false) {
            throw new RuntimeException('Tidak bisa menghubungi GitHub: ' . $error);
        }

        return [$status, json_decode($body, true) ?? []];
    }
}

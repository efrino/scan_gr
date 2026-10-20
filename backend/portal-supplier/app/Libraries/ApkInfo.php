<?php

namespace App\Libraries;

use RuntimeException;
use ZipArchive;

/**
 * Baca package, versionCode, dan versionName dari AndroidManifest.xml
 * (format binary XML) di dalam file APK. Tanpa aapt.
 */
class ApkInfo
{
    public string $package = '';
    public int $versionCode = 0;
    public string $versionName = '';

    public static function read(string $apkPath): self
    {
        $zip = new ZipArchive();
        if ($zip->open($apkPath) !== true) {
            throw new RuntimeException('File bukan APK yang valid.');
        }
        $xml = $zip->getFromName('AndroidManifest.xml');
        $zip->close();
        if ($xml === false) {
            throw new RuntimeException('AndroidManifest.xml tidak ditemukan di APK.');
        }

        $info = new self();
        $info->parse($xml);
        if ($info->versionCode <= 0) {
            throw new RuntimeException('versionCode tidak terbaca dari APK.');
        }

        return $info;
    }

    private function parse(string $b): void
    {
        $len     = strlen($b);
        $strings = [];
        $pos     = 8; // lewati header file XML

        while ($pos + 8 <= $len) {
            $type       = $this->u16($b, $pos);
            $headerSize = $this->u16($b, $pos + 2);
            $size       = $this->u32($b, $pos + 4);
            if ($size < 8) {
                break;
            }

            if ($type === 0x0001) {
                $strings = $this->stringPool($b, $pos);
            } elseif ($type === 0x0102) {
                $name = $strings[$this->u32($b, $pos + 20)] ?? '';
                if ($name === 'manifest') {
                    $this->manifestAttributes($b, $pos, $headerSize, $strings);

                    return;
                }
            }
            $pos += $size;
        }
    }

    private function manifestAttributes(string $b, int $chunk, int $headerSize, array $strings): void
    {
        $ext       = $chunk + $headerSize;
        $attrStart = $this->u16($b, $ext + 8);
        $attrSize  = $this->u16($b, $ext + 10);
        $attrCount = $this->u16($b, $ext + 12);

        for ($i = 0; $i < $attrCount; $i++) {
            $a        = $ext + $attrStart + $i * $attrSize;
            $name     = $strings[$this->u32($b, $a + 4)] ?? '';
            $rawValue = $this->u32($b, $a + 8);
            $dataType = ord($b[$a + 15]);
            $data     = $this->u32($b, $a + 16);

            $string = $rawValue !== 0xFFFFFFFF ? ($strings[$rawValue] ?? null)
                : ($dataType === 0x03 ? ($strings[$data] ?? null) : null);

            switch ($name) {
                case 'versionCode':
                    $this->versionCode = $string !== null ? (int) $string : $data;
                    break;
                case 'versionName':
                    $this->versionName = (string) ($string ?? $data);
                    break;
                case 'package':
                    $this->package = (string) $string;
                    break;
            }
        }
    }

    /** @return list<string> */
    private function stringPool(string $b, int $chunk): array
    {
        $count        = $this->u32($b, $chunk + 8);
        $utf8         = ($this->u32($b, $chunk + 16) & 0x100) !== 0;
        $stringsStart = $chunk + $this->u32($b, $chunk + 20);
        $offsets      = $chunk + $this->u16($b, $chunk + 2);

        $out = [];
        for ($i = 0; $i < $count; $i++) {
            $p = $stringsStart + $this->u32($b, $offsets + $i * 4);
            if ($utf8) {
                $p += (ord($b[$p]) & 0x80) ? 2 : 1;           // panjang karakter
                $n  = ord($b[$p]);
                if ($n & 0x80) {
                    $n = (($n & 0x7F) << 8) | ord($b[$p + 1]);
                    $p += 2;
                } else {
                    $p += 1;
                }
                $out[] = substr($b, $p, $n);
            } else {
                $n = $this->u16($b, $p);
                if ($n & 0x8000) {
                    $n = (($n & 0x7FFF) << 16) | $this->u16($b, $p + 2);
                    $p += 4;
                } else {
                    $p += 2;
                }
                $out[] = mb_convert_encoding(substr($b, $p, $n * 2), 'UTF-8', 'UTF-16LE');
            }
        }

        return $out;
    }

    private function u16(string $b, int $p): int
    {
        return unpack('v', $b, $p)[1];
    }

    private function u32(string $b, int $p): int
    {
        return unpack('V', $b, $p)[1];
    }
}

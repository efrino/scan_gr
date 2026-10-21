<?php
$esc = static fn ($s) => esc((string) ($s ?? ''));
$apk = base_url('app/download/apk');
?><!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Unduh GR Scanner</title>
  <meta name="robots" content="noindex">
  <?php if ($v): ?>
    <!-- Unduhan mulai otomatis saat link/QR dibuka; halaman tetap tampil untuk cara pasang. -->
    <meta http-equiv="refresh" content="1;url=<?= $apk ?>">
  <?php endif ?>
  <style>
    :root { --bg: #f2f5f9; --card: #fff; --fg: #1d2733; --muted: #5f6b7a; --accent: #1565c0; --line: #dde3ea; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--fg);
           font: 15px/1.5 -apple-system, "Segoe UI", Roboto, "Source Sans Pro", sans-serif; }
    main { max-width: 440px; margin: 0 auto; padding: 28px 16px 40px; }
    .card { background: var(--card); border-radius: 16px; padding: 24px 20px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
    .head { display: flex; gap: 14px; align-items: center; }
    .head img { width: 56px; height: 56px; border-radius: 14px; }
    h1 { font-size: 20px; margin: 0; }
    .meta { color: var(--muted); font-size: 13px; margin-top: 2px; }
    .btn { display: block; text-align: center; text-decoration: none; border-radius: 12px;
           padding: 14px; font-weight: 600; margin-top: 20px; background: var(--accent); color: #fff; }
    .btn.alt { background: transparent; color: var(--accent); border: 1px solid var(--line); margin-top: 10px; font-weight: 500; }
    h2 { font-size: 14px; margin: 24px 0 8px; }
    ol { margin: 0; padding-left: 20px; color: var(--muted); font-size: 14px; }
    ol li { margin-bottom: 6px; }
    .notes { white-space: pre-line; font-size: 14px; color: var(--muted); border-top: 1px solid var(--line); margin-top: 20px; padding-top: 14px; }
    .auto { margin-top: 18px; padding: 10px 12px; border-radius: 10px; background: #e8f1fb; color: #0d47a1; font-size: 14px; }
    footer { text-align: center; color: var(--muted); font-size: 12px; margin-top: 18px; }
  </style>
</head>
<body>
<main>
  <div class="card">
    <div class="head">
      <img src="<?= base_url('dist/img/default-png.png') ?>" alt="">
      <div>
        <h1>GR Scanner</h1>
        <div class="meta">
          <?php if ($v): ?>
            Versi <?= $esc($v['version_name']) ?>
            <?php if (! empty($v['apk_size'])): ?> · <?= number_format($v['apk_size'] / 1048576, 1) ?> MB<?php endif ?>
            · Android
          <?php else: ?>
            Belum tersedia
          <?php endif ?>
        </div>
      </div>
    </div>

    <?php if ($v): ?>
      <div class="auto">⬇️ Unduhan dimulai otomatis… Jika tidak mulai, tekan tombol di bawah.</div>
      <a class="btn" href="<?= $apk ?>">Unduh APK</a>
      <a class="btn alt" href="<?= $apk ?>?src=server">Unduhan lambat? Unduh dari server kantor</a>

      <h2>Cara memasang</h2>
      <ol>
        <li>Tunggu unduhan selesai <?php if (! empty($v["apk_size"])): ?>(sekitar <?= number_format($v["apk_size"] / 1048576, 0) ?> MB)<?php endif ?>.</li>
        <li>Buka file <em>scan_gr-<?= $esc($v['version_name']) ?>…apk</em> dari notifikasi atau folder Download.</li>
        <li>Jika muncul peringatan, izinkan <strong>Instal aplikasi tak dikenal</strong> untuk browser/WhatsApp, lalu tekan <strong>Instal</strong>.</li>
        <li>Sudah punya versi lama? Cukup pasang di atasnya, data scan tidak hilang.</li>
      </ol>

      <?php if (! empty($v['release_notes'])): ?>
        <div class="notes"><strong>Yang baru:</strong>
<?= $esc($v['release_notes']) ?></div>
      <?php endif ?>
    <?php endif ?>
  </div>
  <footer>PT Mekar Armada Jaya · IT Department</footer>
</main>
</body>
</html>

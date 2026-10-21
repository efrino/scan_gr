<?= $this->extend('template/default') ?>

<?= $this->section('content') ?>
<?php
$esc = static fn ($v) => esc((string) ($v ?? ''));
$totalDevices = array_sum(array_column($stats, 'total'));
$prodCode = $production ? (int) $production['version_code'] : null;
$prodMin = $production ? (int) $production['min_version_code'] : null;

// Nama versi per build, untuk menampilkan versi minimum sebagai nama, bukan angka.
$nameByCode = [];
foreach ($versions as $v) {
    $nameByCode[(int) $v['version_code']] = $v['version_name'];
}
ksort($nameByCode);
$label = static fn (int $code) => isset($nameByCode[$code])
    ? $nameByCode[$code] . ' (build ' . $code . ')'
    : 'build ' . $code;
?>
<section class="content">
  <div class="container-fluid">

    <?php foreach (['success' => 'success', 'warning' => 'warning', 'error' => 'danger'] as $key => $cls): ?>
      <?php if (session()->getFlashdata($key)): ?>
        <div class="alert alert-<?= $cls ?> alert-dismissible fade show">
          <?= $esc(session()->getFlashdata($key)) ?>
          <button type="button" class="close" data-dismiss="alert">&times;</button>
        </div>
      <?php endif ?>
    <?php endforeach ?>

    <!-- Ringkasan -->
    <div class="row">
      <div class="col-md-4">
        <div class="info-box">
          <span class="info-box-icon bg-primary"><i class="fas fa-mobile-alt"></i></span>
          <div class="info-box-content">
            <span class="info-box-text">Versi production</span>
            <span class="info-box-number">
              <?= $production ? $esc($production['version_name']) . ' <small class="text-muted">build ' . $prodCode . '</small>' : '<span class="text-muted">belum ada</span>' ?>
            </span>
          </div>
        </div>
      </div>
      <div class="col-md-4">
        <div class="info-box">
          <span class="info-box-icon bg-danger"><i class="fas fa-lock"></i></span>
          <div class="info-box-content">
            <span class="info-box-text">Versi tertua yang masih boleh dipakai</span>
            <span class="info-box-number"><?= $prodMin !== null ? $esc($label($prodMin)) : '-' ?></span>
          </div>
        </div>
      </div>
      <div class="col-md-4">
        <div class="info-box">
          <span class="info-box-icon bg-success"><i class="fas fa-tablet-alt"></i></span>
          <div class="info-box-content">
            <span class="info-box-text">Device aktif (30 hari)</span>
            <span class="info-box-number"><?= $totalDevices ?></span>
          </div>
        </div>
      </div>
    </div>

    <div class="row">
      <!-- Rilis baru -->
      <div class="col-lg-5">
        <div class="card card-primary card-outline">
          <div class="card-header"><h3 class="card-title">Rilis versi baru</h3></div>
          <?php if (! $can['create']): ?>
          <div class="card-body text-muted small">
            <i class="fas fa-lock"></i> Anda tidak punya izin merilis versi baru.
            Minta admin menambahkan izin <strong>Create</strong> pada menu <strong>Rilis &amp; Versi</strong>
            (Authorization → Set Permission).
          </div>
          <?php else: ?>
          <form action="<?= base_url('app-release/store') ?>" method="post" id="release-form"
                data-chunk-url="<?= base_url('app-release/chunk') ?>">
            <?= csrf_field() ?>
            <input type="hidden" name="upload_id" id="upload_id">
            <input type="hidden" name="total_chunks" id="total_chunks">
            <input type="hidden" name="file_name" id="file_name">
            <div class="card-body">
              <div class="form-group">
                <label for="apk">File APK release</label>
                <input type="file" class="form-control-file" id="apk" accept=".apk" required>
                <small class="form-text text-muted">
                  Versi dan build dibaca otomatis dari APK. Build harus lebih besar dari versi terakhir.
                </small>
                <div id="upload-progress" class="mt-2" hidden>
                  <div class="progress progress-sm"><div class="progress-bar" id="upload-bar" style="width: 0%"></div></div>
                  <small class="text-muted" id="upload-text">Mengunggah...</small>
                </div>
                <div class="text-danger small mt-2" id="upload-error" hidden></div>
              </div>
              <div class="form-group">
                <label for="min_version_code">Sifat update</label>
                <select class="form-control" id="min_version_code" name="min_version_code">
                  <option value="">Opsional: device boleh menunda update</option>
                  <?php foreach (array_reverse($nameByCode, true) as $code => $name):
                    if ($prodMin !== null && $code <= $prodMin) continue; ?>
                    <option value="<?= $code ?>">Wajib untuk versi di bawah <?= $esc($name) ?></option>
                  <?php endforeach ?>
                  <option value="new">Wajib untuk semua device (versi yang dirilis ini)</option>
                </select>
                <small class="form-text text-muted">
                  Wajib = app di device terkunci sampai diupdate. Antrian scan tetap aman.
                </small>
              </div>
              <div class="form-group">
                <label for="release_notes">Catatan rilis</label>
                <textarea class="form-control" id="release_notes" name="release_notes" rows="4"
                          placeholder="Tampil di dialog update, satu perubahan per baris."></textarea>
              </div>
              <p class="mb-0 small <?= $githubReady ? 'text-success' : 'text-warning' ?>">
                <i class="fab fa-github"></i>
                <?= $githubReady
                    ? 'APK otomatis dirilis ke GitHub dan disalin ke server ini.'
                    : 'GITHUB_TOKEN belum diisi di .env. APK hanya disimpan di server ini.' ?>
              </p>
            </div>
            <div class="card-footer text-right">
              <button type="submit" class="btn btn-primary" id="release-submit">
                <i class="fas fa-upload"></i> Rilis
              </button>
            </div>
          </form>
          <?php endif ?>
        </div>
      </div>

      <!-- Statistik -->
      <div class="col-lg-7">
        <div class="card card-outline card-success">
          <div class="card-header"><h3 class="card-title">Versi terpasang di device (30 hari terakhir)</h3></div>
          <div class="card-body">
            <?php if (empty($stats)): ?>
              <p class="text-muted mb-0">Belum ada device yang melapor. Device tercatat saat app versi 1.0.2 ke atas melakukan cek update.</p>
            <?php else: ?>
              <?php foreach ($stats as $s):
                $code = (int) $s['version_code'];
                $pct = $totalDevices ? round($s['total'] / $totalDevices * 100) : 0;
                $bar = $prodCode !== null && $code >= $prodCode ? 'bg-success'
                    : ($prodMin !== null && $code < $prodMin ? 'bg-danger' : 'bg-warning');
              ?>
                <div class="mb-3">
                  <div class="d-flex justify-content-between small">
                    <span><strong><?= $esc($s['version_name'] ?: '-') ?></strong> build <?= $code ?></span>
                    <span><?= (int) $s['total'] ?> device · <?= $pct ?>%</span>
                  </div>
                  <div class="progress progress-sm">
                    <div class="progress-bar <?= $bar ?>" style="width: <?= $pct ?>%"></div>
                  </div>
                </div>
              <?php endforeach ?>
              <p class="small text-muted mb-0">
                <span class="text-success">■</span> terbaru
                <span class="text-warning ml-2">■</span> perlu update
                <span class="text-danger ml-2">■</span> di bawah versi minimum
              </p>
            <?php endif ?>
          </div>
        </div>
      </div>
    </div>

    <!-- Bagikan aplikasi -->
    <?php
    // Format WhatsApp: *tebal*, _miring_, ~coret~, ```monospace```.
    $verName    = $production ? $production['version_name'] : '';
    $waTemplate = "📲 *GR Scanner" . ($verName ? " v{$verName}" : '') . "*\n"
        . "_Aplikasi scan GR – PT Mekar Armada Jaya_\n\n"
        . "Halo! Silakan pasang aplikasi *GR Scanner* versi terbaru di HP Android Anda.\n\n"
        . "🔗 *Link unduh:*\n"
        . $downloadUrl . "\n\n"
        . "*Cara pasang:*\n"
        . "1️⃣ Buka link di atas lewat HP\n"
        . "2️⃣ Tekan *Unduh APK*\n"
        . "3️⃣ Jika diminta, izinkan _\"Instal aplikasi tak dikenal\"_\n"
        . "4️⃣ Tekan *Instal*, lalu login seperti biasa\n\n"
        . "💡 _Sudah punya versi lama? Pasang saja di atasnya, data scan tidak hilang._\n\n"
        . "— _IT Department_";
    ?>
    <style>
      .wa-chips { display: flex; flex-wrap: wrap; gap: 6px; min-height: 38px; padding: 6px; border: 1px solid #ced4da; border-radius: 6px; background: #fff; }
      .wa-chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 6px 3px 10px; border-radius: 16px; background: #e8f5e9; color: #1b5e20; font-size: 13px; font-variant-numeric: tabular-nums; }
      .wa-chip.bad { background: #fdecea; color: #b71c1c; }
      .wa-chip button { border: 0; background: transparent; color: inherit; line-height: 1; padding: 0 4px; font-size: 16px; cursor: pointer; }
      .wa-chips .wa-empty { color: #8a94a0; font-size: 13px; align-self: center; padding-left: 4px; }
      .wa-toolbar .btn { min-width: 34px; }
      .wa-preview-wrap { background: #e5ddd5; border-radius: 8px; padding: 12px; height: 100%; }
      .wa-bubble { background: #dcf8c6; border-radius: 8px 0 8px 8px; padding: 8px 10px; font-size: 13.5px; line-height: 1.45; white-space: normal; word-break: break-word; box-shadow: 0 1px 1px rgba(0,0,0,.12); max-width: 100%; }
      .wa-bubble code { background: rgba(0,0,0,.06); color: inherit; padding: 0 3px; border-radius: 3px; }
      .wa-bubble a { color: #0b66c3; }
    </style>
    <div class="card card-outline card-info">
      <div class="card-header"><h3 class="card-title">Bagikan aplikasi</h3></div>
      <div class="card-body">
        <div class="row">
          <div class="col-md-4 text-center mb-3">
            <img src="<?= base_url('app-release/qr') ?>" alt="QR Code link unduh GR Scanner"
                 style="width: 100%; max-width: 220px; border: 1px solid #e3e6ea; border-radius: 8px">
            <div class="mt-2">
              <a href="<?= base_url('app-release/qr?download=1') ?>" class="btn btn-sm btn-outline-secondary">
                <i class="fas fa-download"></i> Unduh QR (PNG)
              </a>
            </div>
            <small class="form-text text-muted">Link tetap: QR ini berlaku untuk semua versi berikutnya.</small>
          </div>
          <div class="col-md-8">
            <div class="form-group">
              <label for="share_link">Link unduh</label>
              <div class="input-group">
                <input type="text" class="form-control" id="share_link" value="<?= $esc($downloadUrl) ?>" readonly>
                <div class="input-group-append">
                  <button type="button" class="btn btn-outline-secondary" id="copy_link">Salin</button>
                  <a class="btn btn-outline-secondary" href="<?= $esc($downloadUrl) ?>" target="_blank" rel="noopener">Buka</a>
                </div>
              </div>
            </div>

            <!-- Pengirim WhatsApp (wa-gateway) -->
            <div class="border rounded p-2 mb-3" id="wa-sender" data-fonnte="<?= $fonnteReady ? '1' : '0' ?>"
                 data-can-send="<?= $can['update'] ? '1' : '0' ?>" data-can-link="<?= $can['delete'] ? '1' : '0' ?>"
                 data-status-url="<?= base_url('app-release/wa-status') ?>"
                 data-logout-url="<?= base_url('app-release/wa-logout') ?>"
                 data-send-url="<?= base_url('app-release/wa-send-one') ?>">
              <div class="d-flex align-items-center flex-wrap small" style="gap: 6px 14px">
                <span><i class="fab fa-whatsapp text-success"></i> <strong>Fonnte</strong>
                  <?= $fonnteReady
                      ? '<span class="badge badge-success">Aktif</span>'
                      : '<span class="badge badge-secondary">Token belum diisi</span>' ?></span>
                <span><strong>Nomor cadangan</strong> <span id="wa-state" class="badge badge-secondary">Memeriksa...</span></span>
                <span class="ml-auto">
                  <button type="button" class="btn btn-xs btn-link p-0" id="wa-link-toggle" hidden>Tautkan nomor cadangan</button>
                  <button type="button" class="btn btn-xs btn-link text-danger p-0" id="wa-logout" hidden>Putuskan</button>
                </span>
              </div>
              <div id="wa-qr-box" class="text-center mt-2" hidden>
                <img id="wa-qr" alt="QR tautkan WhatsApp pengirim" style="width: 220px; max-width: 100%">
                <div class="small text-muted">
                  Di HP pengirim: WhatsApp → <strong>Perangkat tertaut</strong> → <strong>Tautkan perangkat</strong>, lalu scan QR ini.
                  Pakai nomor khusus, bukan nomor pribadi.
                </div>
              </div>
            </div>

            <form id="wa-form" onsubmit="return false">
              <div class="form-group">
                <label for="wa-num-input" class="d-flex justify-content-between">
                  <span>Penerima</span>
                  <span class="text-muted font-weight-normal small"><span id="wa-count">0</span>/20 nomor</span>
                </label>
                <div class="input-group">
                  <div class="input-group-prepend"><span class="input-group-text">+62</span></div>
                  <input type="tel" class="form-control" id="wa-num-input" inputmode="numeric" autocomplete="off"
                         placeholder="812 3456 7890, tekan Enter">
                  <div class="input-group-append">
                    <button type="button" class="btn btn-outline-primary" id="wa-num-add"><i class="fas fa-plus"></i> Tambah</button>
                  </div>
                </div>
                <div class="wa-chips mt-2" id="wa-chips"><span class="wa-empty">Belum ada penerima.</span></div>
                <small class="form-text text-muted">
                  Ketik nomor lalu Enter. Bisa tempel beberapa nomor sekaligus (pisahkan koma atau baris).
                  Awalan 0, 62, atau +62 otomatis dirapikan.
                </small>
                <textarea id="wa_numbers" name="wa_numbers" hidden></textarea>
              </div>
              <div class="form-group">
                <label for="wa_message">Pesan</label>
                <div class="row">
                  <div class="col-lg-7 mb-2">
                    <div class="btn-group btn-group-sm wa-toolbar mb-1" role="group" aria-label="Format pesan">
                      <button type="button" class="btn btn-outline-secondary" data-wrap="*" title="Tebal"><b>B</b></button>
                      <button type="button" class="btn btn-outline-secondary" data-wrap="_" title="Miring"><i>I</i></button>
                      <button type="button" class="btn btn-outline-secondary" data-wrap="~" title="Coret"><s>S</s></button>
                      <button type="button" class="btn btn-outline-secondary" data-wrap="```" title="Monospace"><code>{}</code></button>
                      <button type="button" class="btn btn-outline-secondary" id="wa-reset" title="Kembalikan template">Template</button>
                    </div>
                    <textarea class="form-control" id="wa_message" name="wa_message" rows="14"
                              data-template="<?= $esc($waTemplate) ?>"><?= $esc($waTemplate) ?></textarea>
                    <small class="form-text text-muted">Pilih teks lalu tekan B / I / S. Format: *tebal*, _miring_, ~coret~.</small>
                  </div>
                  <div class="col-lg-5 mb-2">
                    <div class="small text-muted mb-1">Pratinjau di WhatsApp</div>
                    <div class="wa-preview-wrap"><div class="wa-bubble" id="wa-preview"></div></div>
                  </div>
                </div>
              </div>
              <div class="d-flex flex-wrap justify-content-end" style="gap: 8px">
                <button type="button" class="btn btn-outline-success" id="wa_open">
                  <i class="fab fa-whatsapp"></i> Buka di WhatsApp saya
                </button>
                <button type="button" class="btn btn-success" id="wa_send" disabled<?= $can['update'] ? '' : ' hidden' ?>>
                  <i class="fab fa-whatsapp"></i> Kirim otomatis
                </button>
              </div>
              <ul class="list-unstyled small mt-2 mb-0" id="wa-results"></ul>
            </form>
          </div>
        </div>
      </div>
    </div>

    <!-- Daftar versi -->
    <div class="card">
      <div class="card-header"><h3 class="card-title">Daftar versi</h3></div>
      <div class="card-body p-0 table-responsive">
        <table class="table table-sm table-hover mb-0">
          <thead>
            <tr>
              <th>Versi</th>
              <th>Build</th>
              <th>Versi tertua yang boleh dipakai</th>
              <th>Status</th>
              <th>Dirilis</th>
              <th>Unduhan</th>
              <th class="text-right">Aksi</th>
            </tr>
          </thead>
          <tbody>
          <?php if (empty($versions)): ?>
            <tr><td colspan="7" class="text-center text-muted py-4">Belum ada versi.</td></tr>
          <?php endif ?>
          <?php foreach ($versions as $v):
            $isProd = $production && (int) $v['id'] === (int) $production['id'];
          ?>
            <tr>
              <td>
                <strong><?= $esc($v['version_name']) ?></strong>
                <?php if (! empty($v['release_notes'])): ?>
                  <div class="small text-muted" style="white-space: pre-line; max-width: 320px"><?= $esc($v['release_notes']) ?></div>
                <?php endif ?>
              </td>
              <td><?= (int) $v['version_code'] ?></td>
              <td>
                <form action="<?= base_url('app-release/min/' . (int) $v['id']) ?>" method="post" class="form-inline">
                  <?= csrf_field() ?>
                  <select name="min_version_code" class="form-control form-control-sm" onchange="this.form.submit()"
                          <?= $can['update'] ? '' : 'disabled title="Butuh izin Update"' ?>
                          aria-label="Versi tertua yang boleh dipakai untuk <?= $esc($v['version_name']) ?>">
                    <?php foreach ($nameByCode as $code => $name):
                      if ($code > (int) $v['version_code']) continue; ?>
                      <option value="<?= $code ?>" <?= $code === (int) $v['min_version_code'] ? 'selected' : '' ?>>
                        <?= $esc($name) ?><?= $code === array_key_first($nameByCode) ? ' (semua boleh)' : '' ?>
                      </option>
                    <?php endforeach ?>
                  </select>
                </form>
              </td>
              <td>
                <?php if ($isProd): ?>
                  <span class="badge badge-primary">Production</span>
                <?php elseif ((int) $v['is_active'] === 1): ?>
                  <span class="badge badge-light">Aktif</span>
                <?php else: ?>
                  <span class="badge badge-secondary">Nonaktif</span>
                <?php endif ?>
              </td>
              <td class="small"><?= $esc($v['released_at']) ?><br><span class="text-muted"><?= $esc($v['created_by']) ?></span></td>
              <td class="small">
                <a href="<?= $esc($v['apk_url']) ?>" target="_blank" rel="noopener">Utama</a>
                <?php if (! empty($v['apk_url_local'])): ?>
                  · <a href="<?= $esc($v['apk_url_local']) ?>" target="_blank" rel="noopener">Server</a>
                <?php endif ?>
                <?php if (! empty($v['apk_size'])): ?>
                  <br><span class="text-muted"><?= number_format($v['apk_size'] / 1048576, 1) ?> MB</span>
                <?php endif ?>
              </td>
              <td class="text-right">
                <?php if ((int) $v['is_active'] === 1 ? $can['delete'] : $can['update']): ?>
                <form action="<?= base_url('app-release/toggle/' . (int) $v['id']) ?>" method="post" class="d-inline"
                      onsubmit="return confirm(<?= $esc(json_encode((int) $v['is_active'] === 1
                          ? 'Nonaktifkan versi ' . $v['version_name'] . '? Device yang sudah memasang versi ini tidak akan diturunkan versinya.'
                          : 'Aktifkan lagi versi ' . $v['version_name'] . '?')) ?>)">
                  <?= csrf_field() ?>
                  <button type="submit" class="btn btn-sm <?= (int) $v['is_active'] === 1 ? 'btn-outline-danger' : 'btn-outline-success' ?>">
                    <?= (int) $v['is_active'] === 1 ? 'Nonaktifkan' : 'Aktifkan' ?>
                  </button>
                </form>
                <?php endif ?>
              </td>
            </tr>
          <?php endforeach ?>
          </tbody>
        </table>
      </div>
      <div class="card-footer small text-muted">
        Production = versi aktif dengan build tertinggi. Android tidak bisa menurunkan versi tanpa uninstall,
        jadi rollback dilakukan dengan merilis ulang kode lama memakai build lebih tinggi.
      </div>
    </div>

    <!-- Device -->
    <div class="card collapsed-card">
      <div class="card-header">
        <h3 class="card-title">Device (<?= count($devices) ?> terakhir)</h3>
        <div class="card-tools">
          <button type="button" class="btn btn-tool" data-card-widget="collapse"><i class="fas fa-plus"></i></button>
        </div>
      </div>
      <div class="card-body p-0 table-responsive">
        <table class="table table-sm table-striped mb-0">
          <thead>
            <tr><th>NIK</th><th>Model</th><th>Versi</th><th>IP</th><th>Terakhir cek</th><th>Pertama</th></tr>
          </thead>
          <tbody>
          <?php foreach ($devices as $d):
            $code = (int) $d['version_code'];
            $badge = $prodCode !== null && $code >= $prodCode ? 'success'
                : ($prodMin !== null && $code < $prodMin ? 'danger' : 'warning');
          ?>
            <tr>
              <td><?= $esc($d['nik'] ?: '-') ?></td>
              <td class="small"><?= $esc($d['device_model'] ?: '-') ?></td>
              <td><span class="badge badge-<?= $badge ?>"><?= $esc($d['version_name'] ?: '?') ?> (<?= $code ?>)</span></td>
              <td class="small"><?= $esc($d['ip_address']) ?></td>
              <td class="small"><?= $esc($d['last_seen']) ?></td>
              <td class="small text-muted"><?= $esc($d['first_seen']) ?></td>
            </tr>
          <?php endforeach ?>
          </tbody>
        </table>
      </div>
    </div>

  </div>
</section>

<script>
  // Bagikan: salin link & buka WhatsApp admin (wa.me) untuk nomor pertama.
  (function () {
    var link = document.getElementById('share_link');
    document.getElementById('copy_link').addEventListener('click', function () {
      var btn = this;
      var done = function () { btn.textContent = 'Tersalin'; setTimeout(function () { btn.textContent = 'Salin'; }, 1500); };
      if (navigator.clipboard) {
        navigator.clipboard.writeText(link.value).then(done, function () { link.select(); document.execCommand('copy'); done(); });
      } else { link.select(); document.execCommand('copy'); done(); }
    });

    function normalize(raw) {
      var d = raw.replace(/\D/g, '');
      if (d.indexOf('0') === 0) d = '62' + d.slice(1);
      else if (d.indexOf('8') === 0) d = '62' + d;
      return /^628\d{7,12}$/.test(d) ? d : null;
    }

    // ── Penerima: input +62 menjadi chip ──
    var numInput = document.getElementById('wa-num-input');
    var chipsBox = document.getElementById('wa-chips');
    var hidden = document.getElementById('wa_numbers');
    var countEl = document.getElementById('wa-count');
    var recipients = [];   // { raw, num|null }

    function pretty(n) {   // 6289534697512 -> +62 895-3469-7512
      var r = n.slice(2);
      return '+62 ' + r.slice(0, 3) + '-' + r.slice(3, 7) + (r.length > 7 ? '-' + r.slice(7) : '');
    }

    function renderChips() {
      chipsBox.innerHTML = '';
      if (!recipients.length) {
        chipsBox.innerHTML = '<span class="wa-empty">Belum ada penerima.</span>';
      }
      recipients.forEach(function (r, i) {
        var chip = document.createElement('span');
        chip.className = 'wa-chip' + (r.num ? '' : ' bad');
        chip.title = r.num ? '' : 'Nomor tidak valid';
        chip.appendChild(document.createTextNode(r.num ? pretty(r.num) : r.raw + ' (tidak valid)'));
        var x = document.createElement('button');
        x.type = 'button';
        x.setAttribute('aria-label', 'Hapus ' + (r.num ? pretty(r.num) : r.raw));
        x.innerHTML = '&times;';
        x.addEventListener('click', function () { recipients.splice(i, 1); renderChips(); });
        chip.appendChild(x);
        chipsBox.appendChild(chip);
      });
      var valid = recipients.filter(function (r) { return r.num; }).map(function (r) { return r.num; });
      hidden.value = valid.join('\n');
      countEl.textContent = valid.length;
      countEl.parentNode.className = 'small font-weight-normal ' + (valid.length > 20 ? 'text-danger' : 'text-muted');
    }

    function addNumbers(text) {
      text.split(/[\n,;]+/).forEach(function (raw) {
        raw = raw.trim();
        if (raw.replace(/\D/g, '').length < 3) return;
        var digits = raw.replace(/\D/g, '');
        // Kolom diawali +62, jadi "8123..." berarti nomor lokal.
        var num = normalize(/^(0|62|\+)/.test(raw.replace(/\s/g, '')) ? digits : '62' + digits);
        if (num && recipients.some(function (r) { return r.num === num; })) return;
        recipients.push({ raw: raw, num: num });
      });
      numInput.value = '';
      renderChips();
    }

    numInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); addNumbers(numInput.value); }
      if (e.key === 'Backspace' && !numInput.value && recipients.length) { recipients.pop(); renderChips(); }
    });
    numInput.addEventListener('paste', function (e) {
      var t = (e.clipboardData || window.clipboardData).getData('text');
      if (/[\n,;]/.test(t)) { e.preventDefault(); addNumbers(t); }
    });
    numInput.addEventListener('blur', function () { if (numInput.value.trim()) addNumbers(numInput.value); });
    document.getElementById('wa-num-add').addEventListener('click', function () { addNumbers(numInput.value); numInput.focus(); });

    // ── Pesan: toolbar format WhatsApp + pratinjau ──
    var msgEl = document.getElementById('wa_message');
    var preview = document.getElementById('wa-preview');

    function waToHtml(text) {
      var h = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      h = h.replace(/```([\s\S]+?)```/g, '<code>$1</code>')
           .replace(/(^|[\s(])\*(\S(?:[^*\n]*\S)?)\*(?=[\s).,!?:]|$)/gm, '$1<b>$2</b>')
           .replace(/(^|[\s(])_(\S(?:[^_\n]*\S)?)_(?=[\s).,!?:]|$)/gm, '$1<i>$2</i>')
           .replace(/(^|[\s(])~(\S(?:[^~\n]*\S)?)~(?=[\s).,!?:]|$)/gm, '$1<s>$2</s>')
           .replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>');
      return h.replace(/\n/g, '<br>');
    }
    function updatePreview() { preview.innerHTML = waToHtml(msgEl.value); }

    document.querySelectorAll('.wa-toolbar [data-wrap]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var m = btn.dataset.wrap, s = msgEl.selectionStart, e = msgEl.selectionEnd, v = msgEl.value;
        var sel = v.slice(s, e) || 'teks';
        msgEl.value = v.slice(0, s) + m + sel + m + v.slice(e);
        msgEl.focus();
        msgEl.setSelectionRange(s + m.length, s + m.length + sel.length);
        updatePreview();
      });
    });
    document.getElementById('wa-reset').addEventListener('click', function () {
      if (msgEl.value !== msgEl.dataset.template && !confirm('Ganti pesan dengan template awal?')) return;
      msgEl.value = msgEl.dataset.template;
      updatePreview();
    });
    msgEl.addEventListener('input', updatePreview);
    updatePreview();
    renderChips();

    document.getElementById('wa_open').addEventListener('click', function () {
      var lines = document.getElementById('wa_numbers').value.split(/[\n,;]+/)
        .map(function (s) { return s.trim(); }).filter(function (s) { return s.replace(/\D/g, '').length > 2; });
      var msg = encodeURIComponent(document.getElementById('wa_message').value);
      if (!lines.length) {
        window.open('https://wa.me/?text=' + msg, '_blank');   // pilih kontak di WhatsApp
        return;
      }
      var num = normalize(lines[0]);
      if (!num) { alert('Nomor tidak valid: ' + lines[0]); return; }
      if (lines.length > 1) alert('Buka WhatsApp hanya untuk satu nomor (' + lines[0] + '). Untuk banyak nomor pakai Kirim otomatis.');
      window.open('https://wa.me/' + num + '?text=' + msg, '_blank');
    });

    // ── Pengirim WhatsApp (wa-gateway) ──
    var box = document.getElementById('wa-sender');
    var badge = document.getElementById('wa-state');
    var qrBox = document.getElementById('wa-qr-box');
    var qrImg = document.getElementById('wa-qr');
    var logoutBtn = document.getElementById('wa-logout');
    var sendBtn = document.getElementById('wa_send');
    var results = document.getElementById('wa-results');
    var csrfInput = document.querySelector('input[type=hidden][name^=csrf]');
    var linkToggle = document.getElementById('wa-link-toggle');
    var connected = false, busy = false, timer = null, qrOpen = false;
    var fonnte = box.dataset.fonnte === '1';
    var canSend = box.dataset.canSend === '1', canLink = box.dataset.canLink === '1';

    function post(url, data) {
      var fd = new FormData();
      if (csrfInput) fd.append(csrfInput.name, csrfInput.value);
      Object.keys(data || {}).forEach(function (k) { fd.append(k, data[k]); });
      return fetch(url, { method: 'POST', body: fd, credentials: 'same-origin' })
        .then(function (r) { return r.json(); });
    }

    function render(s) {
      connected = s.state === 'open';
      var map = {
        open: ['badge-success', 'Terhubung' + (s.me ? ' sebagai +' + s.me : '')],
        qr: ['badge-warning', 'Belum ditautkan'],
        connecting: ['badge-info', 'Menyambung...'],
        closed: ['badge-secondary', 'Terputus'],
        down: ['badge-danger', s.error || 'Gateway tidak berjalan']
      };
      var m = map[s.state] || map.down;
      badge.className = 'badge ' + m[0];
      badge.textContent = m[1];
      if (connected) qrOpen = false;
      qrBox.hidden = !(qrOpen && s.qr);
      if (s.qr && qrOpen) qrImg.src = s.qr;
      linkToggle.hidden = !canLink || connected || s.state === 'down';
      linkToggle.textContent = qrOpen ? 'Tutup QR' : 'Tautkan nomor cadangan';
      logoutBtn.hidden = !canLink || !connected;
      sendBtn.disabled = !canSend || !(connected || fonnte) || busy;
    }

    function poll() {
      fetch(box.dataset.statusUrl, { credentials: 'same-origin' })
        .then(function (r) { return r.json(); })
        .then(render)
        .catch(function () { render({ state: 'down', error: 'Gagal memeriksa gateway' }); })
        .finally(function () {
          clearTimeout(timer);
          // Cepat hanya saat QR dibuka (QR berganti ±20 detik); selain itu cek status sesekali.
          timer = setTimeout(poll, qrOpen && !connected ? 4000 : 30000);
        });
    }
    poll();

    linkToggle.addEventListener('click', function () {
      qrOpen = !qrOpen;
      poll();
    });

    logoutBtn.addEventListener('click', function () {
      if (!confirm('Putuskan WhatsApp pengirim? Perlu scan QR lagi untuk mengirim.')) return;
      post(box.dataset.logoutUrl).finally(function () { setTimeout(poll, 1500); });
    });

    sendBtn.addEventListener('click', async function () {
      if (numInput.value.trim()) addNumbers(numInput.value);
      if (recipients.some(function (r) { return !r.num; })) { alert('Hapus dulu nomor yang ditandai merah (tidak valid).'); return; }
      var lines = document.getElementById('wa_numbers').value.split(/[\n,;]+/)
        .map(function (s) { return s.trim(); }).filter(function (s) { return s.replace(/\D/g, '').length > 2; });
      var msg = document.getElementById('wa_message').value.trim();
      var nums = [], bad = [];
      lines.forEach(function (l) { var n = normalize(l); n ? (nums.indexOf(n) < 0 && nums.push(n)) : bad.push(l); });
      if (bad.length) { alert('Nomor tidak valid: ' + bad.join(', ')); return; }
      if (!nums.length) { alert('Isi minimal satu nomor WhatsApp.'); return; }
      if (nums.length > 20) { alert('Maksimal 20 nomor sekali kirim.'); return; }
      if (!msg) { alert('Pesan kosong.'); return; }

      busy = true;
      sendBtn.disabled = true;
      results.innerHTML = '';
      var okCount = 0;
      for (var i = 0; i < nums.length; i++) {
        var li = document.createElement('li');
        li.textContent = pretty(nums[i]) + ': mengirim...';
        results.appendChild(li);
        try {
          var r = await post(box.dataset.sendUrl, { number: nums[i], message: msg });
          li.textContent = pretty(nums[i]) + ': ' + (r.ok ? 'terkirim via ' + r.via : 'gagal (' + (r.error || 'tidak diketahui') + ')');
          li.className = r.ok ? 'text-success' : 'text-danger';
          if (r.ok) okCount++;
        } catch (e) {
          li.textContent = pretty(nums[i]) + ': gagal (koneksi)';
          li.className = 'text-danger';
        }
        // Jeda acak 3–6 detik antar nomor untuk mengurangi risiko diblokir WhatsApp.
        if (i < nums.length - 1) await new Promise(function (r) { setTimeout(r, 3000 + Math.random() * 3000); });
      }
      var sum = document.createElement('li');
      sum.innerHTML = '<strong>Selesai: ' + okCount + ' dari ' + nums.length + ' terkirim.</strong>';
      results.appendChild(sum);
      busy = false;
      sendBtn.disabled = !canSend || !(connected || fonnte);
    });
  })();

  // Proxy nginx di depan mspin menolak request > 1 MB, jadi APK dikirim per
  // potongan 640 KB ke app-release/chunk, lalu form dikirim tanpa file.
  (function () {
    var CHUNK = 640 * 1024;
    var form = document.getElementById('release-form');
    if (!form) return;   // tanpa izin Create: form rilis tidak ditampilkan
    var input = document.getElementById('apk');
    var btn = document.getElementById('release-submit');
    var box = document.getElementById('upload-progress');
    var bar = document.getElementById('upload-bar');
    var text = document.getElementById('upload-text');
    var err = document.getElementById('upload-error');
    var csrf = form.querySelector('input[type=hidden][name^=csrf]');
    var sending = false;

    function randomId() {
      var a = new Uint8Array(16);
      crypto.getRandomValues(a);
      return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    }

    async function sendChunk(id, index, total, blob) {
      for (var attempt = 1; attempt <= 3; attempt++) {
        var fd = new FormData();
        if (csrf) fd.append(csrf.name, csrf.value);
        fd.append('upload_id', id);
        fd.append('index', index);
        fd.append('total', total);
        fd.append('chunk', blob, 'part');
        try {
          var res = await fetch(form.dataset.chunkUrl, { method: 'POST', body: fd, credentials: 'same-origin' });
          var body = await res.json().catch(function () { return {}; });
          if (res.ok && body.ok) return;
          if (res.status === 403 || res.status === 422) throw new Error(body.message || ('HTTP ' + res.status));
        } catch (e) {
          if (attempt === 3 || /admin|tidak valid/.test(e.message)) throw e;
        }
        await new Promise(function (r) { setTimeout(r, 1000 * attempt); });
      }
      throw new Error('Potongan ' + (index + 1) + ' gagal dikirim.');
    }

    form.addEventListener('submit', async function (ev) {
      if (form.dataset.ready === '1') return;   // potongan sudah terkirim, kirim form
      ev.preventDefault();
      if (sending) return;

      var file = input.files[0];
      if (!file) return;
      sending = true;
      err.hidden = true;
      btn.disabled = true;
      box.hidden = false;

      var id = randomId();
      var total = Math.ceil(file.size / CHUNK);
      try {
        for (var i = 0; i < total; i++) {
          await sendChunk(id, i, total, file.slice(i * CHUNK, (i + 1) * CHUNK));
          var pct = Math.round((i + 1) / total * 100);
          bar.style.width = pct + '%';
          text.textContent = 'Mengunggah ' + pct + '% (' + (file.size / 1048576).toFixed(1) + ' MB)';
        }
      } catch (e) {
        sending = false;
        btn.disabled = false;
        box.hidden = true;
        err.textContent = 'Unggahan gagal: ' + e.message;
        err.hidden = false;
        return;
      }

      document.getElementById('upload_id').value = id;
      document.getElementById('total_chunks').value = total;
      document.getElementById('file_name').value = file.name;
      text.textContent = 'Unggahan selesai. Memproses rilis dan mengirim ke GitHub...';
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Merilis...';
      input.disabled = true;           // file tidak ikut terkirim lagi
      form.dataset.ready = '1';
      form.submit();
    });
  })();
</script>
<?= $this->endSection() ?>

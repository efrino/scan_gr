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
                <form action="<?= base_url('app-release/toggle/' . (int) $v['id']) ?>" method="post" class="d-inline"
                      onsubmit="return confirm(<?= $esc(json_encode((int) $v['is_active'] === 1
                          ? 'Nonaktifkan versi ' . $v['version_name'] . '? Device yang sudah memasang versi ini tidak akan diturunkan versinya.'
                          : 'Aktifkan lagi versi ' . $v['version_name'] . '?')) ?>)">
                  <?= csrf_field() ?>
                  <button type="submit" class="btn btn-sm <?= (int) $v['is_active'] === 1 ? 'btn-outline-danger' : 'btn-outline-success' ?>">
                    <?= (int) $v['is_active'] === 1 ? 'Nonaktifkan' : 'Aktifkan' ?>
                  </button>
                </form>
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
  // Proxy nginx di depan mspin menolak request > 1 MB, jadi APK dikirim per
  // potongan 640 KB ke app-release/chunk, lalu form dikirim tanpa file.
  (function () {
    var CHUNK = 640 * 1024;
    var form = document.getElementById('release-form');
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

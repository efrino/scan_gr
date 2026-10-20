<?= $this->extend('template/default') ?>

<?= $this->section('content') ?>
<?php
$esc = static fn ($v) => esc((string) ($v ?? ''));
$totalDevices = array_sum(array_column($stats, 'total'));
$prodCode = $production ? (int) $production['version_code'] : null;
$prodMin = $production ? (int) $production['min_version_code'] : null;
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
            <span class="info-box-text">Wajib update di bawah</span>
            <span class="info-box-number"><?= $prodMin !== null ? 'build ' . $prodMin : '-' ?></span>
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
          <form action="<?= base_url('app-release/store') ?>" method="post" enctype="multipart/form-data" id="release-form">
            <?= csrf_field() ?>
            <div class="card-body">
              <div class="form-group">
                <label for="apk">File APK release</label>
                <input type="file" class="form-control-file" id="apk" name="apk" accept=".apk" required>
                <small class="form-text text-muted">
                  Versi dan build dibaca otomatis dari APK. Build harus lebih besar dari versi terakhir.
                  Maks. <?= $esc($maxUploadSize) ?>.
                </small>
              </div>
              <div class="form-group">
                <label for="min_version_code">Wajib update untuk build di bawah</label>
                <input type="number" min="1" class="form-control" id="min_version_code" name="min_version_code"
                       placeholder="<?= $prodMin !== null ? 'Kosongkan = tetap build ' . $prodMin : 'Kosongkan = build APK ini' ?>">
                <small class="form-text text-muted">
                  Kosongkan jika update opsional. Isi dengan build APK ini untuk memaksa semua device update.
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
              <th>Wajib update di bawah</th>
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
                  <input type="number" name="min_version_code" min="1" max="<?= (int) $v['version_code'] ?>"
                         value="<?= (int) $v['min_version_code'] ?>" class="form-control form-control-sm" style="width: 80px"
                         aria-label="Versi minimum untuk <?= $esc($v['version_name']) ?>">
                  <button class="btn btn-sm btn-outline-secondary ml-1" type="submit">Simpan</button>
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
  // Unggah APK ±70 MB butuh waktu; cegah klik ganda.
  document.getElementById('release-form').addEventListener('submit', function () {
    var btn = document.getElementById('release-submit');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Mengunggah & merilis...';
  });
</script>
<?= $this->endSection() ?>

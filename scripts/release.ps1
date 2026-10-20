<#
.SYNOPSIS
  Rilis GR Scanner dari PC ini (cadangan jika GitHub Actions tidak jalan).

.DESCRIPTION
  Langkah sama dengan .github/workflows/release.yml:
  test -> build APK bertanda tangan -> GitHub Release -> daftarkan ke server.
  Butuh: flutter, gh (sudah login), android/key.properties + keystore release,
  dan token rilis (sama dengan RELEASE_HOOK_TOKEN di .env server).

.EXAMPLE
  .\scripts\release.ps1 -Version 1.0.3 -Notes "Cek update berkala tiap 15 menit"

.EXAMPLE
  .\scripts\release.ps1 -Version 1.0.4 -Notes "Perbaikan kecil" -Optional
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$Notes,
    # Default update wajib. -Optional = device boleh menunda.
    [switch]$Optional
)

$ErrorActionPreference = 'Stop'
$Repo       = 'efrino/scan_gr'
$Api        = 'https://mspin.newarmada.biz/portal-supplier/public/api/app'
$Tag        = "v$Version"
$Root       = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "GAGAL: $text" -ForegroundColor Red; exit 1 }

# ── Pemeriksaan awal ─────────────────────────────────────────────────────────
Step 'Pemeriksaan awal'
if (git status --porcelain) { Fail 'Ada perubahan belum di-commit. Commit atau stash dulu.' }
if ((git rev-parse --abbrev-ref HEAD) -ne 'main') { Fail 'Jalankan dari branch main.' }
git fetch -q origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { Fail 'Branch main lokal belum sama dengan origin/main (pull/push dulu).' }
if (-not (Test-Path 'android/key.properties')) { Fail 'android/key.properties tidak ada; APK tidak bisa ditandatangani keystore release.' }
# PowerShell 5.1 menganggap stderr program yang dialihkan sebagai error fatal saat
# ErrorActionPreference = Stop, padahal "release not found" adalah hasil yang diharapkan.
$ErrorActionPreference = 'Continue'
gh release view $Tag -R $Repo 2>&1 | Out-Null
$exists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = 'Stop'
if ($exists) { Fail "Release $Tag sudah ada di GitHub." }

$token = $env:RELEASE_HOOK_TOKEN
if (-not $token) {
    $secure = Read-Host 'Token rilis (RELEASE_HOOK_TOKEN)' -AsSecureString
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
if (-not $token) { Fail 'Token rilis kosong.' }

$latest = (Invoke-RestMethod "$Api/version").data.version_code
$Code   = [int]$latest + 1
$File   = "scan_gr-$Version-$Code.apk"
$Min    = if ($Optional) { $null } else { $Code }
Write-Host "Versi $Version, build $Code (server sekarang build $latest), update $(if ($Optional) { 'opsional' } else { 'WAJIB' })"

# ── Test & build ─────────────────────────────────────────────────────────────
Step 'Test'
flutter test
if ($LASTEXITCODE -ne 0) { Fail 'Test gagal.' }

Step 'Build APK'
flutter build apk --release --build-name=$Version --build-number=$Code
if ($LASTEXITCODE -ne 0) { Fail 'Build gagal.' }
$out = "build/app/outputs/flutter-apk/$File"
Copy-Item 'build/app/outputs/flutter-apk/app-release.apk' $out -Force

$bt = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" | Sort-Object Name | Select-Object -Last 1
$cert = & "$($bt.FullName)\apksigner.bat" verify --print-certs $out | Select-String 'certificate DN'
if ($cert -match 'Android Debug') { Fail 'APK ditandatangani debug key, bukan keystore release.' }
$sha  = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $out).Length
Write-Host "$File  $([math]::Round($size / 1MB, 1)) MB  sha256 $sha"

# ── GitHub Release ───────────────────────────────────────────────────────────
Step "GitHub Release $Tag"
gh release create $Tag $out -R $Repo --target main --title "GR Scanner $Version (build $Code)" --notes $Notes
if ($LASTEXITCODE -ne 0) { Fail 'Gagal membuat GitHub Release.' }
git fetch -q origin --tags

# ── Daftarkan ke server ──────────────────────────────────────────────────────
Step 'Daftarkan ke server'
$body = @{
    version_name     = $Version
    version_code     = $Code
    min_version_code = $(if ($Min) { $Min } else { [int](Invoke-RestMethod "$Api/version").data.min_version_code })
    apk_url          = "https://github.com/$Repo/releases/download/$Tag/$File"
    apk_sha256       = $sha
    apk_size         = $size
    release_notes    = $Notes
    tag              = $Tag
} | ConvertTo-Json
try {
    $res = Invoke-RestMethod -Method Post "$Api/release-hook" -ContentType 'application/json' `
        -Headers @{ 'X-Release-Token' = $token } -Body $body -TimeoutSec 120
    Write-Host $res.message
} catch {
    # Proxy bisa memutus respons saat server masih mengunduh APK; hasil dicek di bawah.
    Write-Host "Respons server: $($_.Exception.Message)" -ForegroundColor Yellow
}

for ($i = 1; $i -le 20; $i++) {
    $now = [int](Invoke-RestMethod "$Api/version").data.version_code
    if ($now -eq $Code) {
        Write-Host "`nSelesai. Server memakai $Version (build $Code). Device akan ditawari update." -ForegroundColor Green
        exit 0
    }
    Write-Host "Menunggu server ($i/20), sekarang build $now"
    Start-Sleep -Seconds 15
}
Fail "GitHub Release dibuat, tapi server belum mendaftarkan build $Code. Daftarkan lewat CMS app-release."

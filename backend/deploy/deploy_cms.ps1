$ErrorActionPreference = 'Stop'
$B = 'D:\Efrino\Flutter\scan_gr\backend'
$A = "$B\portal-supplier\app"
ssh sto55 'rm -rf /tmp/cms; mkdir -p /tmp/cms'
scp "$A\Libraries\ApkInfo.php" "$A\Libraries\GithubRelease.php" "$A\Controllers\AppRelease.php" "$A\Controllers\RestAPI\AppVersion.php" "$A\Views\app_release\index.php" "$A\Database\Migrations\2026-10-20-180000_CreateAppDevices.php" "$B\deploy\deploy_cms.sh" sto55:/tmp/cms/
ssh sto55 'sh /tmp/cms/deploy_cms.sh'

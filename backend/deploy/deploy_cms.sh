#!/bin/sh
# Pasang CMS rilis aplikasi di portal-supplier (server 55).
# Jalankan di server setelah file diunggah ke /tmp/cms/.
set -e
R=/var/www/html/portal-supplier
SRC=/tmp/cms
TS=$(date +%Y%m%d-%H%M%S)
BAK=/var/www/backup/portal-supplier-cms-$TS

echo "== backup ke $BAK"
mkdir -p "$BAK"
cp -p "$R/app/Config/Routes.php" "$R/app/Config/Menu.php" "$BAK/"
cp -p "$R/app/Controllers/RestAPI/AppVersion.php" "$BAK/AppVersion.php"

echo "== salin file"
mkdir -p "$R/app/Libraries" "$R/app/Views/app_release"
cp "$SRC/ApkInfo.php" "$SRC/GithubRelease.php" "$R/app/Libraries/"
cp "$SRC/AppRelease.php" "$R/app/Controllers/AppRelease.php"
cp "$SRC/AppVersion.php" "$R/app/Controllers/RestAPI/AppVersion.php"
cp "$SRC/index.php" "$R/app/Views/app_release/index.php"
cp "$SRC/2026-10-20-180000_CreateAppDevices.php" "$R/app/Database/Migrations/"

echo "== route & menu"
python3 - "$R" <<'EOF'
import sys
root = sys.argv[1]

p = root + "/app/Config/Routes.php"
s = open(p).read()
if "AppRelease::index" not in s:
    anchor = "// REST API Routes\n"
    assert s.count(anchor) == 1, "anchor Routes.php tidak ditemukan"
    block = (
        "// CMS rilis aplikasi GR Scanner (admin)\n"
        "$routes->group('app-release', ['namespace' => 'App\\Controllers'], function ($routes) {\n"
        "    $routes->get('/', 'AppRelease::index');\n"
        "    $routes->post('chunk', 'AppRelease::chunk');\n"
        "    $routes->post('store', 'AppRelease::store');\n"
        "    $routes->post('min/(:num)', 'AppRelease::setMin/$1');\n"
        "    $routes->post('toggle/(:num)', 'AppRelease::toggle/$1');\n"
        "});\n\n"
    )
    s = s.replace(anchor, block + anchor, 1)
    open(p, "w").write(s)
    print("route ditambah")

p = root + "/app/Config/Menu.php"
s = open(p).read()
if "'app_release'" not in s:
    anchor = "        'legal_documents' => ["
    assert s.count(anchor) == 1, "anchor Menu.php tidak ditemukan"
    block = (
        "        'app_release' => [\n"
        "            'header_label'  => 'Aplikasi GR Scanner',\n"
        "            'icon'          => 'fas fa-mobile-alt',\n"
        "            'manage_release' => [\n"
        "                'label'      => 'Rilis & Versi',\n"
        "                'url'        => 'app-release',\n"
        "                'permission' => ['Module.View.AppRelease', 'child' => ['Create', 'Update', 'Delete']],\n"
        "            ],\n"
        "        ],\n\n"
    )
    s = s.replace(anchor, block + anchor, 1)
    open(p, "w").write(s)
    print("menu ditambah")
EOF

echo "== cek sintaks"
for f in app/Libraries/ApkInfo.php app/Libraries/GithubRelease.php app/Controllers/AppRelease.php \
         app/Controllers/RestAPI/AppVersion.php app/Views/app_release/index.php \
         app/Config/Routes.php app/Config/Menu.php; do
    php -l "$R/$f" >/dev/null && echo "ok  $f"
done

cd "$R"
echo "== migrasi"
php spark migrate -n App
php spark routes 2>/dev/null | grep -i "app-release\|app/version"

echo "== uji baca APK"
php -r '
require "vendor/autoload.php";
require "app/Libraries/ApkInfo.php";
foreach (glob("public/apk/*.apk") as $f) {
    $i = App\Libraries\ApkInfo::read($f);
    echo basename($f), ": ", $i->package, " ", $i->versionName, " (", $i->versionCode, ")\n";
}'

rm -rf "$SRC"
echo "== selesai. Backup: $BAK"

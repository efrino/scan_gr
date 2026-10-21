#!/bin/sh
# Pasang push notification (FCM) di portal-supplier.
# Unggah dulu file ke /tmp/push/, lalu jalankan skrip ini di server 55.
set -e
R=/var/www/html/portal-supplier
SRC=/tmp/push
BAK=/var/www/backup/portal-supplier-push-$(date +%Y%m%d-%H%M%S)

test -f "$R/writable/firebase-service-account.json" || { echo "service account Firebase belum ada"; exit 1; }

echo "== backup ke $BAK"
mkdir -p "$BAK"
cp -p "$R/app/Config/Routes.php" "$R/app/Filters/ApiTokenFilter.php" \
      "$R/app/Controllers/AppRelease.php" "$R/app/Controllers/RestAPI/AppVersion.php" \
      "$R/app/Views/app_release/index.php" "$BAK/"

echo "== salin file"
cp "$SRC/Fcm.php" "$R/app/Libraries/"
cp "$SRC/2026-10-21-150000_AddFcmTokenToAppDevices.php" "$R/app/Database/Migrations/"
cp "$SRC/AppRelease.php" "$R/app/Controllers/AppRelease.php"
cp "$SRC/AppVersion.php" "$R/app/Controllers/RestAPI/AppVersion.php"
cp "$SRC/index.php" "$R/app/Views/app_release/index.php"
(cd "$R" && php spark migrate)

echo "== route"
python3 - "$R" <<'EOF'
import sys
root = sys.argv[1]

p = root + "/app/Config/Routes.php"
s = open(p).read()
if "AppRelease::pushSend" not in s:
    anchor = "    $routes->post('wa-send-one', 'AppRelease::waSendOne');\n"
    assert s.count(anchor) == 1, "anchor wa-send-one tidak ditemukan"
    s = s.replace(anchor, anchor
        + "    $routes->post('push-send', 'AppRelease::pushSend');\n", 1)
    print("route CMS ditambah")
if "AppVersion::fcmToken" not in s:
    anchor = "    $routes->get('app/version', 'AppVersion::latest');\n"
    assert s.count(anchor) == 1, "anchor app/version tidak ditemukan"
    s = s.replace(anchor, anchor
        + "    $routes->post('app/fcm-token', 'AppVersion::fcmToken', ['filter' => 'apitoken']);\n", 1)
    print("route fcm-token ditambah")
open(p, "w").write(s)

EOF

echo "== filter"
cp "$SRC/ApiTokenFilter.php" "$R/app/Filters/"

for f in app/Config/Routes.php app/Filters/ApiTokenFilter.php app/Controllers/AppRelease.php \
         app/Controllers/RestAPI/AppVersion.php app/Libraries/Fcm.php; do
  php -l "$R/$f" >/dev/null || { echo "SYNTAX ERROR $f, kembalikan dari $BAK"; exit 1; }
done

rm -rf "$SRC"
echo "== selesai. Backup: $BAK"

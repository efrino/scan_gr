#!/bin/sh
# Pasang token API per device di portal-supplier (server 55).
# Unggah dulu file ke /tmp/tok/, lalu jalankan skrip ini di server.
set -e
R=/var/www/html/portal-supplier
SRC=/tmp/tok
BAK=/var/www/backup/portal-supplier-token-$(date +%Y%m%d-%H%M%S)

echo "== backup ke $BAK"
mkdir -p "$BAK"
cp -p "$R/app/Filters/ApiTokenFilter.php" "$R/app/Controllers/RestAPI/AuthController.php" "$BAK/"

echo "== tabel api_tokens"
cp "$SRC/ApiTokens.php" "$R/app/Libraries/"
cp "$SRC/2026-10-21-140000_CreateApiTokens.php" "$R/app/Database/Migrations/"
(cd "$R" && php spark migrate)

echo "== filter & login"
cp "$SRC/ApiTokenFilter.php" "$R/app/Filters/"
cp "$SRC/AuthController.php" "$R/app/Controllers/RestAPI/"
php -l "$R/app/Filters/ApiTokenFilter.php"
php -l "$R/app/Controllers/RestAPI/AuthController.php"

rm -rf "$SRC"
echo "== selesai. Kembalikan dengan: cp $BAK/ApiTokenFilter.php $R/app/Filters/ && cp $BAK/AuthController.php $R/app/Controllers/RestAPI/"

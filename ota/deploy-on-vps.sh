#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:?用法：deploy-on-vps.sh <上传暂存目录>}"
TARGET_DIR="/var/www/ke-ota"
SITE="/etc/nginx/sites-enabled/gude"
SNIPPET="/etc/nginx/snippets/ke-ota.conf"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="/root/ota-deploy-backups/$STAMP"
EXPECTED_IPA_SHA256="b16d37c0c2f85643bf9864ac5e662b3d2f5e03ee26b905d2a279b259a73d94f0"
INSTALL_URL="https://jiagude.love/ios/2c9715755397490791ffbe1568d2b914/"

for file in index.html manifest.plist KeApp.ipa nginx-location.conf; do
    test -f "$SOURCE_DIR/$file"
done
test -f "$SITE"
test "$(sha256sum "$SOURCE_DIR/KeApp.ipa" | awk '{print $1}')" = "$EXPECTED_IPA_SHA256"

install -d -m 0755 "$TARGET_DIR" "$BACKUP_DIR" /etc/nginx/snippets
cp -a "$SITE" "$BACKUP_DIR/gude.before"
if test -f "$SNIPPET"; then
    cp -a "$SNIPPET" "$BACKUP_DIR/ke-ota.conf.before"
fi
for file in index.html manifest.plist KeApp.ipa; do
    if test -f "$TARGET_DIR/$file"; then
        cp -a "$TARGET_DIR/$file" "$BACKUP_DIR/$file.before"
    fi
done

rollback() {
    cp -a "$BACKUP_DIR/gude.before" "$SITE"
    if test -f "$BACKUP_DIR/ke-ota.conf.before"; then
        cp -a "$BACKUP_DIR/ke-ota.conf.before" "$SNIPPET"
    else
        rm -f "$SNIPPET"
    fi
    for file in index.html manifest.plist KeApp.ipa; do
        if test -f "$BACKUP_DIR/$file.before"; then
            cp -a "$BACKUP_DIR/$file.before" "$TARGET_DIR/$file"
        fi
    done
    nginx -t && systemctl reload nginx || true
}
trap rollback ERR

install -m 0644 "$SOURCE_DIR/index.html" "$TARGET_DIR/index.html"
install -m 0644 "$SOURCE_DIR/manifest.plist" "$TARGET_DIR/manifest.plist"
install -m 0644 "$SOURCE_DIR/KeApp.ipa" "$TARGET_DIR/KeApp.ipa"
install -m 0644 "$SOURCE_DIR/nginx-location.conf" "$SNIPPET"

if ! grep -Fq 'include /etc/nginx/snippets/ke-ota.conf;' "$SITE"; then
    awk '
        { print }
        /^[[:space:]]*client_max_body_size[[:space:]]+30m;/ {
            print "    include /etc/nginx/snippets/ke-ota.conf;"
        }
    ' "$SITE" > "$SITE.new"
    test "$(grep -Fc 'include /etc/nginx/snippets/ke-ota.conf;' "$SITE.new")" -eq 1
    mv "$SITE.new" "$SITE"
fi

nginx -t
systemctl reload nginx

test "$(sha256sum "$TARGET_DIR/KeApp.ipa" | awk '{print $1}')" = "$EXPECTED_IPA_SHA256"

# graceful reload 完成前，极短时间内仍可能命中旧 worker；最多等十秒。
READY=0
for _ in $(seq 1 10); do
    if curl -fsS "$INSTALL_URL" | grep -Fq '安装柯'; then
        READY=1
        break
    fi
    sleep 1
done
test "$READY" -eq 1
curl -fsS "${INSTALL_URL}manifest.plist" | grep -Fq 'love.jiagude.ke'
test "$(curl -fsSIL -o /dev/null -w '%{http_code}' "${INSTALL_URL}KeApp.ipa")" = "200"

trap - ERR
echo "OTA_DEPLOY_OK $INSTALL_URL"

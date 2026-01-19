#!/bin/bash
set -e

XUI_DIR=/usr/local/x-ui
BASE_DIR=/usr/local
SERVICE_DIR=/etc/systemd/system
API=https://api.github.com/repos/MHSanaei/3x-ui/releases/latest

apt install -y -q curl tar ca-certificates socat

cd "$BASE_DIR"

TAG=$(curl -s "$API" | sed -n 's/.*"tag_name": "\(.*\)".*/\1/p')
echo "Installing x-ui $TAG"

curl -fSL \
  -o x-ui.tar.gz \
  "https://github.com/MHSanaei/3x-ui/releases/download/$TAG/x-ui-linux-amd64.tar.gz"

systemctl stop x-ui 2>/dev/null || true
rm -rf "$XUI_DIR"

tar zxf x-ui.tar.gz && rm -f x-ui.tar.gz
cd x-ui
chmod +x x-ui x-ui.sh bin/xray-linux-amd64

curl -fSL \
  -o /usr/bin/x-ui \
  https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
chmod +x /usr/bin/x-ui

./x-ui setting -username admin -password PassWord -port 8000 -webBasePath x-ui
./x-ui migrate

install -m 644 x-ui.service.debian "$SERVICE_DIR/x-ui.service"
systemctl daemon-reload
systemctl enable --now x-ui

echo "Done: http://IP:8000/x-ui"

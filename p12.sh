mkdir -p /etc/ocserv/certs && cd /etc/ocserv/certs

while true; do
  read -r -p "请输入到期日期（格式 YYYYMMDD，直接回车默认 20391231）: " TARGET_DATE
  TARGET_DATE="${TARGET_DATE:-20391231}"
  if [[ ! "$TARGET_DATE" =~ ^[0-9]{8}$ ]]; then
    echo "格式错误，请输入 8 位数字（YYYYMMDD）。"
    continue
  fi
  FORMATTED_DATE="${TARGET_DATE:0:4}-${TARGET_DATE:4:2}-${TARGET_DATE:6:2}"
  TARGET_TS=$(date -d "$FORMATTED_DATE 23:59:59" +%s 2>/dev/null)
  if [ -z "$TARGET_TS" ]; then
    echo "无效日期（$FORMATTED_DATE），请重新输入。"
    continue
  fi
  NOW_TS=$(date +%s)
  DIFF_SEC=$((TARGET_TS - NOW_TS))
  if [ "$DIFF_SEC" -le 86400 ]; then
    echo "输入日期需晚于今天，请重新输入。"
    continue
  fi
  EXP_DAYS=$(( (DIFF_SEC + 86399) / 86400 ))
  echo "到期日期 $FORMATTED_DATE 已换算为：${EXP_DAYS} 天"
  break
done

cat > ca.tmpl << EOF
cn = "Connect"
organization = "Connect"
serial = 1
expiration_days = ${EXP_DAYS}
ca
signing_key
cert_signing_key
crl_signing_key
EOF

cat > server.tmpl << EOF
cn = "Connect"
organization = "Connect"
serial = 2
expiration_days = ${EXP_DAYS}
signing_key
encryption_key
tls_www_server
EOF

cat > user.tmpl << EOF
cn = "Connect"
unit = "Connect"
expiration_days = ${EXP_DAYS}
signing_key
tls_www_client
EOF

certtool --generate-privkey --outfile ca-key.pem && \
certtool --generate-privkey --outfile server-key.pem && \
certtool --generate-privkey --outfile user-key.pem && \
certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem && \
certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem && \
certtool --generate-certificate --load-privkey user-key.pem --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem --template user.tmpl --outfile user-cert.pem && \
certtool --to-p12 --load-privkey user-key.pem --pkcs-cipher aes-256 --load-certificate user-cert.pem --outfile user.p12 --outder && \
chmod 600 /etc/ocserv/certs/*-key.pem && \
(command -v zip >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq zip)) && \
rm -f /etc/ocserv/certs/ocserv-certs.zip && \
zip -rq /etc/ocserv/certs/ocserv-certs.zip /etc/ocserv/certs && \
mkdir -p /var/www/html && \
cp /etc/ocserv/certs/ocserv-certs.zip /etc/ocserv/certs/user.p12 /etc/ocserv/certs/ca-cert.pem /var/www/html/ && \
chmod 644 /var/www/html/ocserv-certs.zip /var/www/html/user.p12 /var/www/html/ca-cert.pem

SERVER_IP=$(curl -4s --max-time 5 ifconfig.me || curl -4s --max-time 5 api.ipify.org || echo "x.x.x.x")
echo "请下载以下文件："
echo "http://${SERVER_IP}/ocserv-certs.zip"
echo "http://${SERVER_IP}/user.p12"
echo "http://${SERVER_IP}/ca-cert.pem"

while true; do
  read -r -p "是否已下载并保存完毕？确认删除 /var/www/html/ 下的相关文件请输入 YES: " CONFIRM_DEL
  if [ "$CONFIRM_DEL" = "YES" ] || [ "$CONFIRM_DEL" = "yes" ]; then
    rm -f /var/www/html/ocserv-certs.zip /var/www/html/user.p12 /var/www/html/ca-cert.pem
    echo "已删除 /var/www/html/ 下的 ocserv-certs.zip、user.p12、ca-cert.pem。"
    break
  else
    echo "未删除，请下载保存完成后输入 YES 确认删除。"
  fi
done

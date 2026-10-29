#!/bin/sh
# nginx :$PORT returns 200 on / for PaaS health; proxies WS path to xray :8081
set -eu
: "${UUID:?UUID env required}"
: "${WSPATH:?WSPATH env required}"
case "$WSPATH" in /*) ;; *) WSPATH="/$WSPATH" ;; esac
PUBLIC_PORT="${PORT:-8080}"
XRAY_PORT=8081
export PORT="$XRAY_PORT"
CFG=/tmp/c.json
cat > "$CFG" <<JSON
{
  "log": { "loglevel": "${LOGLEVEL:-warning}" },
  "dns": { "servers": ["https+local://1.1.1.1/dns-query", "https+local://8.8.8.8/dns-query"], "queryStrategy": "UseIPv4" },
  "inbounds": [{
    "listen": "127.0.0.1", "port": ${XRAY_PORT}, "protocol": "vless",
    "settings": { "clients": [ { "id": "${UUID}" } ], "decryption": "none" },
    "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${WSPATH}" } },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIPv4" } },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": { "domainStrategy": "IPIfNonMatch", "rules": [
    { "type": "field", "domain": ["geosite:private"], "outboundTag": "block" },
    { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
    { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" }
  ]}
}
JSON
mkdir -p /run/nginx /var/lib/nginx/tmp /var/log/nginx
cat > /etc/nginx/http.d/default.conf <<NGX
server {
  listen ${PUBLIC_PORT};
  server_name _;
  location = / {
    default_type text/plain;
    return 200 'ok\n';
  }
  location ${WSPATH} {
    proxy_pass http://127.0.0.1:${XRAY_PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location / {
    default_type text/plain;
    return 200 'ok\n';
  }
}
NGX
/usr/local/bin/xray run -c "$CFG" &
XR=$!
nginx -g 'daemon off;' &
NG=$!
trap 'kill $XR $NG 2>/dev/null; wait' TERM INT
echo "cover+xray public=${PUBLIC_PORT} xray=${XRAY_PORT} path=${WSPATH}"
wait -n $XR $NG
kill $XR $NG 2>/dev/null || true
wait || true
exit 1

#!/bin/sh
# Non-root-safe: nginx temps under /tmp; GET / → 200; WSPATH → xray :8081
set -eu
: "${UUID:?UUID env required}"
: "${WSPATH:?WSPATH env required}"
case "$WSPATH" in /*) ;; *) WSPATH="/$WSPATH" ;; esac
PUBLIC_PORT="${PORT:-8080}"
XRAY_PORT=8081
CFG=/tmp/c.json
NGX_CONF=/tmp/nginx-default.conf
NGX_MAIN=/tmp/nginx.conf
mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi /tmp/nginx/logs
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
cat > "$NGX_MAIN" <<'MAIN'
worker_processes 1;
error_log /tmp/nginx/logs/error.log warn;
pid /tmp/nginx.pid;
events { worker_connections 1024; }
http {
  access_log off;
  client_body_temp_path /tmp/nginx/client_body;
  proxy_temp_path /tmp/nginx/proxy;
  fastcgi_temp_path /tmp/nginx/fastcgi;
  uwsgi_temp_path /tmp/nginx/uwsgi;
  scgi_temp_path /tmp/nginx/scgi;
  include /tmp/nginx-default.conf;
}
MAIN
cat > "$NGX_CONF" <<NGX
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
nginx -c "$NGX_MAIN" -g 'daemon off;' &
NG=$!
trap 'kill $XR $NG 2>/dev/null; wait' TERM INT
echo "cover+xray public=${PUBLIC_PORT} xray=${XRAY_PORT} path=${WSPATH} uid=$(id -u)"
# wait for listen
i=0
while [ $i -lt 30 ]; do
  if wget -q -O - "http://127.0.0.1:${PUBLIC_PORT}/" 2>/dev/null | grep -q ok; then
    echo "health local ok"
    break
  fi
  i=$((i+1)); sleep 0.2
done
wait -n $XR $NG
kill $XR $NG 2>/dev/null || true
wait || true
exit 1

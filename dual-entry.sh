#!/bin/sh
set -eu
: "${UUID:?UUID env required}"
: "${WSPATH:?WSPATH env required}"
case "$WSPATH" in /*) ;; *) WSPATH="/$WSPATH" ;; esac
export WSPATH
PUBLIC_PORT="${PORT:-8080}"
XRAY_PORT=8081
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
/usr/local/bin/xray run -c "$CFG" &
XR=$!
PORT="$PUBLIC_PORT" python3 /cover.py &
CV=$!
trap 'kill $XR $CV 2>/dev/null; wait' TERM INT
echo "cover+xray public=${PUBLIC_PORT} xray=${XRAY_PORT} path=${WSPATH} uid=$(id -u)"
i=0
while [ $i -lt 40 ]; do
  if wget -q -O - "http://127.0.0.1:${PUBLIC_PORT}/" 2>/dev/null | grep -q ok; then
    echo "health local ok"; break
  fi
  i=$((i+1)); sleep 0.25
done
wait -n $XR $CV
kill $XR $CV 2>/dev/null || true
wait || true
exit 1

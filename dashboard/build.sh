#!/bin/bash
# ugly-forge Dashboard bauen, starten und Cloudflare Tunnel konfigurieren

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
if [ ! -d "$STACK_DIR" ]; then STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"; fi

CLIENT_DIR="$FORGE_DIR/dashboard/client"
DASHBOARD_DIR="$FORGE_DIR/dashboard"
STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
STACK_ENV="$STACK_DIR/.env"
NGINX_CONF="$STACK_DIR/nginx/conf.d/default.conf"

if [ ! -f "$STACK_ENV" ]; then
  echo "FEHLER: .env nicht gefunden: $STACK_ENV"; exit 1
fi
set +e
export $(grep -v '^#' "$STACK_ENV" | grep -v '^$' | xargs 2>/dev/null)
set -e

if [ -z "$CF_TOKEN" ] || [ -z "$CF_ZONE_ID" ]; then
  echo "FEHLER: CF_TOKEN oder CF_ZONE_ID fehlt in .env"; exit 1
fi

echo "Baue ugly-forge Dashboard..."

# 1. npm install + React Build (immer -- nie ueberspringen)
echo "npm install..."
npm --prefix "$CLIENT_DIR" install
echo "Vite build..."
npm --prefix "$CLIENT_DIR" run build

# 2. Docker Image
echo "Docker build..."
docker build -t forge-dashboard:latest "$DASHBOARD_DIR"

# 3. forge-dashboard in docker-compose.yml pruefen
if grep -q 'forge-dashboard' "$STACK_COMPOSE" 2>/dev/null; then
  echo "  v forge-dashboard bereits in docker-compose.yml"
else
  echo "  ! forge-dashboard fehlt -- bootstrap.sh ausfuehren"
fi

# 4. nginx
if grep -q 'dashboard.beautymolt.com' "$NGINX_CONF" 2>/dev/null; then
  echo "  v dashboard.beautymolt.com bereits in nginx/conf.d/default.conf"
else
  cat >> "$NGINX_CONF" << 'NGINXEOF'
server {
    listen 80;
    server_name dashboard.beautymolt.com;
    location / {
        proxy_pass http://forge-dashboard:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
NGINXEOF
  echo "  + dashboard.beautymolt.com eingetragen"
fi

docker compose -f "$STACK_COMPOSE" restart nginx
echo "  + nginx neu gestartet"

# 5. Dashboard neu starten (alten Container zuerst entfernen)
echo "Starte forge-dashboard..."
docker rm -f forge-dashboard 2>/dev/null || true
docker compose -f "$STACK_COMPOSE" up -d forge-dashboard
sleep 3

# 6. DNS CNAME
set +e
echo ""
echo "Setze Cloudflare DNS CNAME..."

PAYLOAD=$(echo "$CLOUDFLARE_TUNNEL_TOKEN" | cut -d'.' -f2)
PADDED=$(echo "$PAYLOAD" | sed 's/-/+/g; s/_/\//g')
while [ $((${#PADDED} % 4)) -ne 0 ]; do PADDED="${PADDED}="; done
DECODED=$(echo "$PADDED" | base64 -d 2>/dev/null)
TUNNEL_ID=$(echo "$DECODED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('t',''))" 2>/dev/null)

if [ -z "$TUNNEL_ID" ]; then
  echo "  FEHLER: Tunnel ID nicht lesbar"; exit 1
fi
echo "  Tunnel ID: $TUNNEL_ID"

DNS_CHECK=$(curl -s \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=dashboard.beautymolt.com" \
  -H "Authorization: Bearer $CF_TOKEN")
DNS_COUNT=$(echo "$DNS_CHECK" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('result') or []))" 2>/dev/null)

if [ "$DNS_COUNT" = "0" ]; then
  DNS=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"CNAME\",\"proxied\":true,\"name\":\"dashboard.beautymolt.com\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\"}")
  if echo "$DNS" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
    echo "  + DNS CNAME gesetzt"
  else
    echo "  FEHLER DNS: $DNS"; exit 1
  fi
else
  echo "  v DNS CNAME bereits vorhanden"
fi

echo ""
echo "Dashboard laeuft!"
curl -s http://localhost:3001/api/health && echo ""
echo "  Public: https://dashboard.beautymolt.com"

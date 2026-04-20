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

# Werte aus .env laden
if [ ! -f "$STACK_ENV" ]; then
  echo "FEHLER: .env nicht gefunden: $STACK_ENV"
  exit 1
fi
set +e
export $(grep -v '^#' "$STACK_ENV" | grep -v '^$' | xargs 2>/dev/null)
set -e

# Pruefen welche CF-Variablen vorhanden sind
if [ -z "$CF_TOKEN" ] || [ -z "$CF_ZONE_ID" ]; then
  echo "FEHLER: CF_TOKEN oder CF_ZONE_ID fehlt in .env"
  exit 1
fi

echo "Baue ugly-forge Dashboard..."

# 1. npm install + React Build
if [ ! -d "$CLIENT_DIR/node_modules" ]; then
  echo "npm install..."
  npm --prefix "$CLIENT_DIR" install
fi
echo "Vite build..."
npm --prefix "$CLIENT_DIR" run build

# 2. Docker Image
echo "Docker build..."
docker build -t forge-dashboard:latest "$DASHBOARD_DIR"

# 3. forge-dashboard Service in docker-compose.yml eintragen
if grep -q 'forge-dashboard' "$STACK_COMPOSE" 2>/dev/null; then
  echo "  v forge-dashboard bereits in docker-compose.yml"
else
  MERGE_SCRIPT="/tmp/dc_merge_$$.py"
  cat > "$MERGE_SCRIPT" << PYEOF
import re

path = "$STACK_COMPOSE"
forge_db = "$FORGE_DIR/db"

with open(path) as f:
    content = f.read()

service = f"""
  forge-dashboard:
    image: forge-dashboard:latest
    container_name: forge-dashboard
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - {forge_db}:/home/node/forge-db:ro
    environment:
      - PORT=3001
      - DB_PATH=/home/node/forge-db/projects.db
    networks:
      - ugly-net
"""

content = re.sub(r'\nvolumes:', service + '\nvolumes:', content, count=1)

with open(path, 'w') as f:
    f.write(content)
print("forge-dashboard unter services: eingetragen")
PYEOF

  python3 "$MERGE_SCRIPT"
  rm -f "$MERGE_SCRIPT"
  echo "  + forge-dashboard in docker-compose.yml eingetragen"
fi

# 4. nginx Config kopieren + neu starten
if [ -d "$STACK_DIR/nginx/conf.d" ]; then
  cp "$DASHBOARD_DIR/nginx.conf" "$STACK_DIR/nginx/conf.d/forge-dashboard.conf"
  echo "  + nginx Config kopiert"
  docker compose -f "$STACK_COMPOSE" restart nginx
fi

# 5. Dashboard starten
echo "Starte forge-dashboard..."
docker compose -f "$STACK_COMPOSE" up -d forge-dashboard
sleep 3

# 6. Cloudflare Tunnel konfigurieren
set +e
echo ""
echo "Konfiguriere Cloudflare Tunnel..."

# Account ID und Tunnel ID aus CLOUDFLARE_TUNNEL_TOKEN extrahieren
# Der Token ist ein JWT: header.payload.signature (base64url kodiert)
if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
  PAYLOAD=$(echo "$CLOUDFLARE_TUNNEL_TOKEN" | cut -d'.' -f2)
  # base64url -> base64 padding hinzufuegen
  PADDED=$(echo "$PAYLOAD" | sed 's/-/+/g; s/_/\//g')
  while [ $((${#PADDED} % 4)) -ne 0 ]; do PADDED="${PADDED}="; done
  DECODED=$(echo "$PADDED" | base64 -d 2>/dev/null)
  ACCOUNT_ID=$(echo "$DECODED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('a',''))" 2>/dev/null)
  TUNNEL_ID=$(echo "$DECODED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('t',''))" 2>/dev/null)
fi

if [ -z "$ACCOUNT_ID" ] || [ -z "$TUNNEL_ID" ]; then
  echo "  FEHLER: Konnte Account ID / Tunnel ID nicht aus CLOUDFLARE_TUNNEL_TOKEN lesen"
  echo "  Versuche via API mit CF_TOKEN..."

  # Fallback: via CF_TOKEN (braucht Account:Read Permission)
  CF_ACCOUNTS=$(curl -s "https://api.cloudflare.com/client/v4/accounts" \
    -H "Authorization: Bearer $CF_TOKEN")
  echo "  CF API Antwort: $CF_ACCOUNTS"
  exit 1
fi

echo "  Account ID: $ACCOUNT_ID"
echo "  Tunnel ID:  $TUNNEL_ID"

# Bestehende Ingress-Regeln holen
CF_CONFIG=$(curl -s \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CF_TOKEN")

# Neue Config bauen: bestehende Regeln + dashboard + catch-all
NEW_CONFIG=$(echo "$CF_CONFIG" | python3 -c "
import json, sys
data = json.load(sys.stdin)
rules = data.get('result', {}).get('config', {}).get('ingress', [])
rules = [r for r in rules if r.get('hostname')]
hostnames = [r.get('hostname') for r in rules]
if 'dashboard.beautymolt.com' not in hostnames:
    rules.append({'hostname': 'dashboard.beautymolt.com', 'service': 'http://forge-dashboard:3001'})
rules.append({'service': 'http_status:404'})
print(json.dumps({'config': {'ingress': rules}}))
" 2>&1)

if [ $? -ne 0 ]; then
  echo "  FEHLER beim Erstellen der Config: $NEW_CONFIG"
  exit 1
fi

# Tunnel Config updaten
UPDATE=$(curl -s -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$NEW_CONFIG")

if echo "$UPDATE" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
  echo "  + Tunnel Ingress-Regel hinzugefuegt"
else
  echo "  FEHLER beim Tunnel Update: $UPDATE"
  exit 1
fi

# DNS CNAME erstellen falls nicht vorhanden
DNS_CHECK=$(curl -s \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=dashboard.beautymolt.com" \
  -H "Authorization: Bearer $CF_TOKEN")

DNS_COUNT=$(echo "$DNS_CHECK" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('result',[])))" 2>/dev/null)

if [ "$DNS_COUNT" = "0" ]; then
  DNS=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"CNAME\",\"proxied\":true,\"name\":\"dashboard.beautymolt.com\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\"}")

  if echo "$DNS" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
    echo "  + DNS CNAME erstellt: dashboard.beautymolt.com -> $TUNNEL_ID.cfargotunnel.com"
  else
    echo "  FEHLER DNS CNAME: $DNS"
    exit 1
  fi
else
  echo "  v DNS CNAME bereits vorhanden"
fi

echo ""
echo "Dashboard laeuft!"
curl -s http://localhost:3001/api/health && echo ""
echo "  Public: https://dashboard.beautymolt.com"

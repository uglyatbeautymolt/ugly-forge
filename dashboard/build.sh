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
export $(grep -v '^#' "$STACK_ENV" | grep -v '^$' | xargs)

# CF_TOKEN und CF_ZONE_ID pruefen
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
echo ""
echo "Konfiguriere Cloudflare Tunnel..."

# Account ID holen
ACCOUNT_ID=$(curl -s "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $CF_TOKEN" | \
  python3 -c "import json,sys; data=json.load(sys.stdin); print(data['result'][0]['id'])" 2>/dev/null)

if [ -z "$ACCOUNT_ID" ]; then
  echo "  FEHLER: Account ID konnte nicht abgerufen werden"
  exit 1
fi
echo "  Account ID: $ACCOUNT_ID"

# Tunnel ID holen (erster aktiver Tunnel)
TUNNEL_ID=$(curl -s "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel?is_deleted=false" \
  -H "Authorization: Bearer $CF_TOKEN" | \
  python3 -c "import json,sys; data=json.load(sys.stdin); print(data['result'][0]['id'])" 2>/dev/null)

if [ -z "$TUNNEL_ID" ]; then
  echo "  FEHLER: Tunnel ID konnte nicht abgerufen werden"
  exit 1
fi
echo "  Tunnel ID: $TUNNEL_ID"

# Bestehende Ingress-Regeln holen
EXISTING_INGRESS=$(curl -s \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CF_TOKEN" | \
  python3 -c "
import json,sys
data = json.load(sys.stdin)
rules = data.get('result', {}).get('config', {}).get('ingress', [])
# Catch-all entfernen (wird neu hinzugefuegt)
rules = [r for r in rules if r.get('hostname')]
print(json.dumps(rules))
" 2>/dev/null)

# Neue Config: bestehende Regeln + dashboard + catch-all
NEW_CONFIG=$(python3 -c "
import json
existing = json.loads('$EXISTING_INGRESS') if '$EXISTING_INGRESS' else []
# dashboard Regel hinzufuegen falls nicht vorhanden
ids = [r.get('hostname') for r in existing]
if 'dashboard.beautymolt.com' not in ids:
    existing.append({'hostname': 'dashboard.beautymolt.com', 'service': 'http://forge-dashboard:3001'})
# Catch-all immer am Ende
existing.append({'service': 'http_status:404'})
print(json.dumps({'config': {'ingress': existing}}))
")

# Tunnel Config updaten
UPDATE_RESULT=$(curl -s -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$NEW_CONFIG")

if echo "$UPDATE_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
  echo "  + Tunnel Ingress-Regel hinzugefuegt"
else
  echo "  FEHLER beim Tunnel Update:"
  echo "$UPDATE_RESULT"
  exit 1
fi

# DNS CNAME erstellen (falls nicht vorhanden)
DNS_CHECK=$(curl -s \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=dashboard.beautymolt.com" \
  -H "Authorization: Bearer $CF_TOKEN")

DNS_COUNT=$(echo "$DNS_CHECK" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('result', [])))" 2>/dev/null)

if [ "$DNS_COUNT" = "0" ]; then
  DNS_RESULT=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"CNAME\",\"proxied\":true,\"name\":\"dashboard.beautymolt.com\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\"}")

  if echo "$DNS_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
    echo "  + DNS CNAME erstellt: dashboard.beautymolt.com"
  else
    echo "  FEHLER beim DNS CNAME:"
    echo "$DNS_RESULT"
    exit 1
  fi
else
  echo "  v DNS CNAME bereits vorhanden"
fi

echo ""
echo "Dashboard laeuft!"
curl -s http://localhost:3001/api/health && echo ""
echo "  Public: https://dashboard.beautymolt.com"

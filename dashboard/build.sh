#!/bin/bash
# ugly-forge Dashboard bauen und starten

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
if [ ! -d "$STACK_DIR" ]; then STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"; fi

CLIENT_DIR="$FORGE_DIR/dashboard/client"
DASHBOARD_DIR="$FORGE_DIR/dashboard"
STACK_COMPOSE="$STACK_DIR/docker-compose.yml"

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

# 3. forge-dashboard Service in docker-compose.yml eintragen (korrekt unter services:)
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

# Einfuegen vor 'volumes:' auf Root-Level (nicht unter services:)
content = re.sub(r'\nvolumes:', service + '\nvolumes:', content, count=1)

with open(path, 'w') as f:
    f.write(content)
print("forge-dashboard unter services: eingetragen")
PYEOF

  python3 "$MERGE_SCRIPT"
  rm -f "$MERGE_SCRIPT"
  echo "  + forge-dashboard in docker-compose.yml eingetragen"
fi

# 4. nginx Config in den nginx-Container kopieren
if [ -d "$STACK_DIR/nginx/conf.d" ]; then
  cp "$DASHBOARD_DIR/nginx.conf" "$STACK_DIR/nginx/conf.d/forge-dashboard.conf"
  echo "  + nginx Config kopiert"
  docker compose -f "$STACK_COMPOSE" restart nginx
fi

# 5. Dashboard starten
echo "Starte forge-dashboard..."
docker compose -f "$STACK_COMPOSE" up -d forge-dashboard

sleep 3
echo ""
echo "Dashboard laeuft!"
curl -s http://localhost:3001/api/health && echo ""
echo "  Lokal:  http://localhost:3001"
echo "  Public: https://dashboard.beautymolt.com"

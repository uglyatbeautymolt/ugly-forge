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
NGINX_DIR="$STACK_DIR/nginx/conf.d"

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
  # Python fuer praezises YAML-Einfuegen unter services:
  python3 - << PYEOF
import re

path = "$STACK_COMPOSE"
with open(path, 'r') as f:
    content = f.read()

service_block = """
  forge-dashboard:
    image: forge-dashboard:latest
    container_name: forge-dashboard
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - $FORGE_DIR/db:/home/node/forge-db:ro
    environment:
      - PORT=3001
      - DB_PATH=/home/node/forge-db/projects.db
"""

# Einfuegen nach der letzten Service-Definition (vor networks: oder am Ende)
if 'networks:' in content:
    content = content.replace('\nnetworks:', service_block + '\nnetworks:', 1)
elif 'volumes:' in content:
    content = content.replace('\nvolumes:', service_block + '\nvolumes:', 1)
else:
    content = content.rstrip() + service_block

with open(path, 'w') as f:
    f.write(content)

print("forge-dashboard Service eingetragen")
PYEOF
  echo "  + forge-dashboard in docker-compose.yml eingetragen"
fi

# 4. nginx Config fuer den nginx-Container einrichten
# nginx laeuft als Docker-Container -- Config ins gemountete Verzeichnis kopieren
NGINX_CONF_FOUND=0

# Suche nginx conf.d Verzeichnis (verschiedene moegliche Pfade)
for dir in "$STACK_DIR/nginx/conf.d" "$STACK_DIR/nginx" "$STACK_DIR/config/nginx/conf.d" "$STACK_DIR/data/nginx/conf.d"; do
  if [ -d "$dir" ]; then
    cp "$DASHBOARD_DIR/nginx.conf" "$dir/forge-dashboard.conf"
    echo "  + nginx Config kopiert nach: $dir/forge-dashboard.conf"
    NGINX_CONF_FOUND=1
    break
  fi
done

if [ $NGINX_CONF_FOUND -eq 0 ]; then
  echo "  ! nginx conf.d Verzeichnis nicht gefunden"
  echo "    Bitte manuell kopieren in das nginx-Konfigverzeichnis deines Stacks"
  echo "    Quelle: $DASHBOARD_DIR/nginx.conf"
  echo "    Dann nginx Container neu starten: docker compose restart nginx"
fi

# 5. Dashboard starten
echo "Starte forge-dashboard..."
docker compose -f "$STACK_COMPOSE" up -d forge-dashboard

echo ""
echo "Dashboard laeuft!"
echo "  Lokal: http://$(hostname -I | awk '{print $1}'):3001"
echo ""
echo "Zum Testen: curl http://localhost:3001/api/health"

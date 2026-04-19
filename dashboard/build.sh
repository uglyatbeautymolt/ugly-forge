#!/bin/bash
# ugly-forge Dashboard bauen und starten
# Ausfuehren aus beliebigem Verzeichnis

set -e

# FORGE_DIR = ugly-forge/ (ein Level ueber dashboard/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
if [ ! -d "$STACK_DIR" ]; then STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"; fi

CLIENT_DIR="$FORGE_DIR/dashboard/client"
DASHBOARD_DIR="$FORGE_DIR/dashboard"
STACK_COMPOSE="$STACK_DIR/docker-compose.yml"

echo "Baue ugly-forge Dashboard..."
echo "  FORGE_DIR:    $FORGE_DIR"
echo "  CLIENT_DIR:   $CLIENT_DIR"
echo "  DASHBOARD_DIR: $DASHBOARD_DIR"
echo ""

# 1. npm install falls noetig
if [ ! -d "$CLIENT_DIR/node_modules" ]; then
  echo "npm install..."
  npm --prefix "$CLIENT_DIR" install
fi

# 2. React Build
echo "Vite build..."
npm --prefix "$CLIENT_DIR" run build

# 3. Docker Image
echo "Docker build..."
docker build -t forge-dashboard:latest "$DASHBOARD_DIR"

# 4. docker-compose.yml ergaenzen falls noetig
if grep -q 'forge-dashboard' "$STACK_COMPOSE" 2>/dev/null; then
  echo "  v forge-dashboard bereits in docker-compose.yml"
else
  cat >> "$STACK_COMPOSE" << COMPOSE

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
COMPOSE
  echo "  + forge-dashboard in docker-compose.yml eingetragen"
fi

# 5. Container starten
echo "Starte forge-dashboard..."
docker compose -f "$STACK_COMPOSE" up -d forge-dashboard

echo ""
echo "Dashboard laeuft!"
echo "  Lokal:  http://localhost:3001"
echo "  Prod:   https://dashboard.beautymolt.com (nach nginx-Config)"
echo ""
echo "nginx-Config: cp $DASHBOARD_DIR/nginx.conf /etc/nginx/conf.d/forge-dashboard.conf"

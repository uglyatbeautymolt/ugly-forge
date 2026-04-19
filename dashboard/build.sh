#!/bin/bash
# Nur das Dashboard bauen und starten
# Ausgeführt aus ugly-forge/ Verzeichnis

set -e

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
if [ ! -d "$STACK_DIR" ]; then STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"; fi

echo "🦞📊 Baue ugly-forge Dashboard..."

# 1. React Client bauen
cd "$FORGE_DIR/dashboard/client"
if [ ! -d node_modules ]; then
  echo "📦 npm install..."
  npm install
fi
echo "🛠 Vite build..."
npm run build
cd "$FORGE_DIR"

# 2. Docker Image bauen
echo "🐳 Docker build..."
docker build -t forge-dashboard:latest "$FORGE_DIR/dashboard"

# 3. Docker Compose Service ergänzen (falls nicht vorhanden)
STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
if ! grep -q 'forge-dashboard' "$STACK_COMPOSE" 2>/dev/null; then
  echo "⚠️  Bitte docker-compose.yml manuell ergänzen:"
  echo "   Vorlage: $FORGE_DIR/dashboard/docker-compose.fragment.yml"
fi

echo ""
echo "✅ Dashboard gebaut!"
echo "   Starte mit: docker compose -f $STACK_COMPOSE up -d forge-dashboard"
echo "   Erreichbar: http://localhost:3001"
echo "   Prod:       http://dashboard.beautymolt.com (nach nginx-Konfiguration)"

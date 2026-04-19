#!/bin/bash
# ugly-forge uninstall.sh
# Deaktiviert die Softwareschmiede — ugly-stack bleibt unverändert

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"

if [ ! -d "$STACK_DIR" ]; then
  STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
fi

echo -e "${COLOR_YELLOW}🦞 ugly-forge Deinstallation...${COLOR_NC}"
echo ""

# Volume Mount entfernen
echo -e "${COLOR_YELLOW}[1/3] Entferne Volume Mount...${COLOR_NC}"
sed -i "/ugly-forge\/workspace/d" "$STACK_DIR/docker-compose.yml"
echo -e "${COLOR_GREEN}✅ Volume Mount entfernt${COLOR_NC}"

# OpenClaw neu starten
echo -e "${COLOR_YELLOW}[2/3] Starte OpenClaw neu...${COLOR_NC}"
docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw
echo -e "${COLOR_GREEN}✅ OpenClaw neugestartet${COLOR_NC}"

# Archivierung anbieten
echo -e "${COLOR_YELLOW}[3/3] Datenbank archivieren?${COLOR_NC}"
read -p "projects.db nach ~/ugly-forge-backup.db kopieren? (j/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Jj]$ ]]; then
  cp "$FORGE_DIR/db/projects.db" ~/ugly-forge-backup.db
  echo -e "${COLOR_GREEN}✅ Backup gespeichert: ~/ugly-forge-backup.db${COLOR_NC}"
fi

echo ""
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ ugly-forge deinstalliert${COLOR_NC}"
echo -e "${COLOR_GREEN}ugly-stack läuft unverändert weiter.${COLOR_NC}"
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo ""

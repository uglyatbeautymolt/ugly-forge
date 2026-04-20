#!/bin/bash
# Repariert die docker-compose.yml und startet forge-dashboard
# Einmalig ausfuehren um den falsch platzierten forge-dashboard Block zu korrigieren

set -e

COMPOSE="/home/alex/ugly-stack/docker-compose.yml"
FORGE_DB="/home/alex/ugly-forge/db"

echo "Repariere docker-compose.yml..."

python3 << PYEOF
import re

path = "$COMPOSE"
with open(path) as f:
    content = f.read()

# 1. Kaputten Block unter networks: entfernen
content = re.sub(r'\n\n  forge-dashboard:[\s\S]*$', '', content)

# 2. Korrekt unter services: vor volumes: einfuegen (falls noch nicht vorhanden)
if 'forge-dashboard:' not in content:
    service = """\n  forge-dashboard:
    image: forge-dashboard:latest
    container_name: forge-dashboard
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - $FORGE_DB:/home/node/forge-db:ro
    environment:
      - PORT=3001
      - DB_PATH=/home/node/forge-db/projects.db
    networks:
      - ugly-net

"""
    content = content.replace('\nvolumes:', service + 'volumes:')
    print("forge-dashboard Service unter services: eingetragen")
else:
    print("forge-dashboard bereits korrekt vorhanden")

with open(path, 'w') as f:
    f.write(content)
print("docker-compose.yml repariert")
PYEOF

# Validieren
echo "Validiere..."
docker compose -f "$COMPOSE" config --quiet && echo "VALID"

# Dashboard starten
echo "Starte forge-dashboard..."
docker compose -f "$COMPOSE" up -d forge-dashboard

# Health check
sleep 3
curl -s http://localhost:3001/api/health && echo ""
echo "Dashboard laeuft auf http://localhost:3001"

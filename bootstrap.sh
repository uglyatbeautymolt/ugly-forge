#!/bin/bash
# ugly-forge bootstrap.sh
# Idempotent -- kann beliebig oft ausgefuehrt werden
# Ausfuehren als normaler User -- sudo wird intern verwendet wenn noetig

set -e

COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$FORGE_DIR")"

STACK_DIR="$PARENT_DIR/VPS_Bootstrap"
if [ ! -d "$STACK_DIR" ]; then
  STACK_DIR="$PARENT_DIR/ugly-stack"
fi

OC_DATA="$STACK_DIR/openclaw-data"
OC_WORKSPACE="$OC_DATA/workspace"
OC_SKILLS="$OC_DATA/skills"
OC_CONFIG="$OC_DATA/openclaw.json"

echo -e "${COLOR_BLUE}ugly-forge Bootstrap startet...${COLOR_NC}"
echo -e "${COLOR_BLUE}   Verzeichnis: $FORGE_DIR${COLOR_NC}"
echo ""

# ----------------------------------------------------------------
# HILFSFUNKTIONEN
# ----------------------------------------------------------------

install_pkg() {
  local pkg="$1"
  echo -e "  Installiere $pkg..."
  if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
    sudo apt-get install -y "$pkg" -qq
  elif [ "$(id -u)" = "0" ]; then
    apt-get install -y "$pkg" -qq
  else
    echo -e "  ${COLOR_YELLOW}sudo-Passwort benoetigt fuer $pkg:${COLOR_NC}"
    sudo apt-get install -y "$pkg" -qq
  fi
}

require_cmd() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "  ${COLOR_YELLOW}$cmd nicht gefunden -- installiere $pkg${COLOR_NC}"
    install_pkg "$pkg"
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "${COLOR_RED}Konnte $cmd nicht installieren: apt-get install $pkg${COLOR_NC}"
      exit 1
    fi
    echo -e "  ${COLOR_GREEN}$cmd installiert${COLOR_NC}"
  else
    echo -e "  v $cmd"
  fi
}

# ----------------------------------------------------------------
# 1. SYSTEM-ABHAENGIGKEITEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[1/10] Pruefe System-Abhaengigkeiten...${COLOR_NC}"

require_cmd curl
require_cmd git
require_cmd python3
require_cmd sqlite3
require_cmd jq

if ! command -v docker &> /dev/null; then
  echo -e "${COLOR_RED}docker fehlt. https://docs.docker.com/engine/install/${COLOR_NC}"
  exit 1
fi
echo -e "  v docker"

if ! docker compose version &> /dev/null 2>&1; then
  echo -e "${COLOR_RED}'docker compose' Plugin fehlt. sudo apt-get install docker-compose-plugin${COLOR_NC}"
  exit 1
fi
echo -e "  v docker compose"

if [ "$(id -u)" != "0" ] && ! groups | grep -q docker; then
  echo -e "${COLOR_YELLOW}  User nicht in docker-Gruppe. Fix: sudo usermod -aG docker \$USER && newgrp docker${COLOR_NC}"
fi

echo -e "${COLOR_GREEN}OK System-Abhaengigkeiten${COLOR_NC}"

# ----------------------------------------------------------------
# 2. UGLY-STACK UND OC PRUEFEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[2/10] Pruefe ugly-stack und OpenClaw...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}ugly-stack nicht gefunden unter $PARENT_DIR/${COLOR_NC}"
  exit 1
fi

if ! docker compose -f "$STACK_DIR/docker-compose.yml" ps openclaw 2>/dev/null | grep -q "Up"; then
  echo -e "${COLOR_RED}OpenClaw laeuft nicht. Starten: cd $STACK_DIR && docker compose up -d${COLOR_NC}"
  exit 1
fi

if [ ! -d "$OC_DATA" ]; then
  echo -e "${COLOR_RED}openclaw-data nicht gefunden: $OC_DATA${COLOR_NC}"
  exit 1
fi

echo -e "${COLOR_GREEN}OK ugly-stack: $STACK_DIR${COLOR_NC}"
echo -e "${COLOR_GREEN}OK OpenClaw laeuft${COLOR_NC}"

# ----------------------------------------------------------------
# 3. GITHUB_TOKEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[3/10] Lese GITHUB_TOKEN...${COLOR_NC}"

REMOTE_URL=$(git -C "$STACK_DIR" remote get-url origin 2>/dev/null || echo "")
GITHUB_TOKEN=$(echo "$REMOTE_URL" | sed 's|https://||' | cut -d'@' -f1)

if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "$REMOTE_URL" ]; then
  echo -e "${COLOR_RED}Kein Token in Git Remote URL. Erwartet: https://<TOKEN>@github.com/...${COLOR_NC}"
  exit 1
fi

HTTP_CODE=$(curl -s -o /tmp/gh_forge.json -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${COLOR_RED}GitHub Token ungueltig (HTTP $HTTP_CODE)${COLOR_NC}"
  unset GITHUB_TOKEN; rm -f /tmp/gh_forge.json; exit 1
fi

GITHUB_USERNAME=$(python3 -c 'import json; print(json.load(open("/tmp/gh_forge.json"))["login"])' 2>/dev/null)
rm -f /tmp/gh_forge.json
echo -e "${COLOR_GREEN}OK GitHub Token gueltig -- User: $GITHUB_USERNAME${COLOR_NC}"

# ----------------------------------------------------------------
# 4. PROJEKT_GPG_KEY
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[4/10] Lese PROJEKT_GPG_KEY...${COLOR_NC}"

STACK_ENV="$STACK_DIR/.env"
if [ ! -f "$STACK_ENV" ]; then
  echo -e "${COLOR_RED}.env nicht gefunden: $STACK_ENV${COLOR_NC}"
  unset GITHUB_TOKEN; exit 1
fi

PROJEKT_GPG_KEY=$(grep "^PROJEKT_GPG_KEY=" "$STACK_ENV" | cut -d'=' -f2-)
if [ -z "$PROJEKT_GPG_KEY" ]; then
  echo -e "${COLOR_RED}PROJEKT_GPG_KEY fehlt. Erzeugen: openssl rand -base64 48${COLOR_NC}"
  unset GITHUB_TOKEN; exit 1
fi
echo -e "${COLOR_GREEN}OK PROJEKT_GPG_KEY (${#PROJEKT_GPG_KEY} Zeichen)${COLOR_NC}"

if ! grep -q "^GITHUB_USERNAME=" "$STACK_ENV"; then
  echo "" >> "$STACK_ENV"
  echo "# ugly-forge" >> "$STACK_ENV"
  echo "GITHUB_USERNAME=$GITHUB_USERNAME" >> "$STACK_ENV"
  echo -e "  + GITHUB_USERNAME in .env hinzugefuegt"
fi

# ----------------------------------------------------------------
# 5. SKILLS
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[5/10] Installiere Skills...${COLOR_NC}"
mkdir -p "$OC_SKILLS"

SKILL_COUNT=0
for SKILL_DIR in "$FORGE_DIR/workspace/skills/"/*/; do
  if [ -d "$SKILL_DIR" ]; then
    SKILL_NAME=$(basename "$SKILL_DIR")
    TARGET="$OC_SKILLS/$SKILL_NAME"
    rm -rf "$TARGET"
    cp -r "$SKILL_DIR" "$TARGET"
    SKILL_COUNT=$((SKILL_COUNT + 1))
    echo -e "  + $SKILL_NAME"
  fi
done
echo -e "${COLOR_GREEN}OK $SKILL_COUNT Skills in: $OC_SKILLS${COLOR_NC}"

# ----------------------------------------------------------------
# 6. WORKSPACE
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[6/10] Installiere Workspace-Dateien...${COLOR_NC}"
mkdir -p "$OC_WORKSPACE"

cp "$FORGE_DIR/workspace/AGENTS.md" "$OC_WORKSPACE/AGENTS.md"
cp "$FORGE_DIR/workspace/FORGE-INDEX-template.md" "$OC_WORKSPACE/FORGE-INDEX-template.md"
mkdir -p "$OC_WORKSPACE/projects"

echo -e "${COLOR_GREEN}OK AGENTS.md installiert${COLOR_NC}"

# ----------------------------------------------------------------
# 7. OPENCLAW.JSON MERGEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[7/10] Konfiguriere openclaw.json...${COLOR_NC}"

FORGE_JSON="$FORGE_DIR/workspace/openclaw-forge.json"

if [ ! -f "$OC_CONFIG" ]; then
  cp "$FORGE_JSON" "$OC_CONFIG"
  echo -e "${COLOR_GREEN}OK openclaw.json erstellt (12 Agenten)${COLOR_NC}"

elif grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
  echo -e "  v forge-Agenten bereits vorhanden"

else
  BACKUP="${OC_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$OC_CONFIG" "$BACKUP"
  echo -e "  + Backup: $BACKUP"

  MERGE_SCRIPT="/tmp/oc_merge_$$.py"
  cat > "$MERGE_SCRIPT" << PYEOF
import json, sys

config_path = "$OC_CONFIG"
forge_path  = "$FORGE_JSON"

with open(config_path, 'r') as f:
    existing = json.load(f)

with open(forge_path, 'r') as f:
    forge = json.load(f)

if 'tools' not in existing:
    existing['tools'] = {}
if 'loopDetection' not in existing['tools'] and 'tools' in forge:
    existing['tools']['loopDetection'] = forge['tools']['loopDetection']

if 'agents' not in existing:
    existing['agents'] = {}

forge_agents = forge.get('agents', {}).get('list', [])
ex_list = existing['agents'].setdefault('list', [])
ex_ids  = {a.get('id') for a in ex_list}

added = 0
for agent in forge_agents:
    if agent.get('id') not in ex_ids:
        ex_list.append(agent)
        added += 1

with open(config_path, 'w') as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"{added} Agenten hinzugefuegt, {len(ex_list)} total")
PYEOF

  python3 "$MERGE_SCRIPT"
  MERGE_EXIT=$?
  rm -f "$MERGE_SCRIPT"

  if [ $MERGE_EXIT -ne 0 ]; then
    echo -e "${COLOR_RED}Merge fehlgeschlagen -- stelle Backup wieder her${COLOR_NC}"
    cp "$BACKUP" "$OC_CONFIG"
    exit 1
  fi

  echo -e "${COLOR_GREEN}OK openclaw.json gemergt${COLOR_NC}"
fi

# ----------------------------------------------------------------
# 8. SQLITE DB + VOLUME MOUNT
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[8/10] Initialisiere SQLite Datenbank...${COLOR_NC}"

FORGE_DB_DIR="$FORGE_DIR/db"
mkdir -p "$FORGE_DB_DIR"

sqlite3 "$FORGE_DB_DIR/projects.db" <<'SQL'
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  status TEXT DEFAULT 'planning',
  github_repo TEXT,
  budget_estimated REAL DEFAULT 0,
  budget_used REAL DEFAULT 0,
  tasks_total INTEGER DEFAULT 0,
  tasks_done INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  title TEXT NOT NULL,
  agent TEXT NOT NULL,
  status TEXT DEFAULT 'backlog',
  cost_estimated REAL DEFAULT 0,
  cost_real REAL DEFAULT 0,
  iterations INTEGER DEFAULT 0,
  user_story TEXT,
  blocked_reason TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (project_id) REFERENCES projects(id)
);
CREATE TABLE IF NOT EXISTS agent_questions (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  from_agent TEXT NOT NULL,
  to_agent TEXT NOT NULL,
  depth INTEGER DEFAULT 1,
  content TEXT NOT NULL,
  status TEXT DEFAULT 'open',
  parent_id TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  resolved_at DATETIME
);
CREATE TABLE IF NOT EXISTS model_performance (
  id TEXT PRIMARY KEY,
  agent TEXT NOT NULL,
  model TEXT NOT NULL,
  tier TEXT NOT NULL,
  project_id TEXT,
  success INTEGER DEFAULT 1,
  retry_count INTEGER DEFAULT 0,
  rate_limit_hit INTEGER DEFAULT 0,
  quality_score INTEGER,
  latency_ms INTEGER,
  tokens_input INTEGER DEFAULT 0,
  tokens_output INTEGER DEFAULT 0,
  cost REAL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS agent_learnings (
  id TEXT PRIMARY KEY,
  agent TEXT NOT NULL,
  project_id TEXT NOT NULL,
  project_name TEXT NOT NULL,
  problem TEXT NOT NULL,
  solution TEXT NOT NULL,
  effect TEXT,
  status TEXT DEFAULT 'pending',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  confirmed_at DATETIME
);
CREATE TABLE IF NOT EXISTS communications (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  from_agent TEXT NOT NULL,
  to_agent TEXT NOT NULL,
  type TEXT NOT NULL,
  message TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
SQL

echo -e "${COLOR_GREEN}OK SQLite DB: $FORGE_DB_DIR/projects.db${COLOR_NC}"

# Volume Mount via awk einfuegen.
# awk -v uebergibt Variablen sicher -- keine Slash-Probleme wie bei sed.
# Strategie: Zeile mit /home/node/www finden, danach neue Mount-Zeile einfuegen.
# Idempotent: grep prueft vorher ob forge-db bereits vorhanden.
STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
if grep -qF "forge-db" "$STACK_COMPOSE" 2>/dev/null; then
  echo -e "  v DB Volume Mount bereits vorhanden"
else
  DB_MOUNT="      - ${FORGE_DB_DIR}:/home/node/forge-db"
  TMPFILE="$(mktemp)"

  awk -v mount="$DB_MOUNT" '
    {
      print
      if (!inserted && index($0, "/home/node/www") > 0) {
        print mount
        inserted = 1
      }
    }
  ' "$STACK_COMPOSE" > "$TMPFILE"

  # Pruefen ob der Mount im Output ist
  if grep -qF "forge-db" "$TMPFILE"; then
    mv "$TMPFILE" "$STACK_COMPOSE"
    echo -e "  + DB Volume Mount eingefuegt"
  else
    rm -f "$TMPFILE"
    echo -e "${COLOR_RED}awk-Patch fehlgeschlagen -- /home/node/www nicht gefunden${COLOR_NC}"
    echo -e "${COLOR_YELLOW}Manuell einfuegen unter openclaw volumes in $STACK_COMPOSE:${COLOR_NC}"
    echo -e "      - $FORGE_DB_DIR:/home/node/forge-db"
  fi
fi

# ----------------------------------------------------------------
# 9. CLOUDFLARE TUNNEL + NGINX
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[9/10] Cloudflare Tunnel + nginx fuer dashboard.beautymolt.com...${COLOR_NC}"

source "$STACK_ENV"

NGINX_CONF="$STACK_DIR/nginx/conf.d/default.conf"
DASHBOARD_BLOCK='server {
    listen 80;
    server_name dashboard.beautymolt.com;
    location / {
        proxy_pass http://forge-dashboard:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}'

if grep -q "dashboard.beautymolt.com" "$NGINX_CONF" 2>/dev/null; then
  echo -e "  v nginx: dashboard.beautymolt.com bereits vorhanden"
else
  echo "" >> "$NGINX_CONF"
  echo "$DASHBOARD_BLOCK" >> "$NGINX_CONF"
  echo -e "  + nginx: dashboard.beautymolt.com Block hinzugefuegt"
fi

if [ -n "$CF_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ] && [ -n "$CF_TUNNEL_ID" ]; then
  TUNNEL_CONFIG=$(curl -s \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
    -H "Authorization: Bearer ${CF_TOKEN}")

  if echo "$TUNNEL_CONFIG" | jq -e '.success' | grep -q true; then
    if echo "$TUNNEL_CONFIG" | jq -e '.result.config.ingress[] | select(.hostname == "dashboard.beautymolt.com")' > /dev/null 2>&1; then
      echo -e "  v Cloudflare Tunnel: dashboard.beautymolt.com bereits vorhanden"
    else
      NEW_INGRESS=$(echo "$TUNNEL_CONFIG" | jq '
        .result.config.ingress = (
          [.result.config.ingress[] | select(.hostname != null and .service != "http_status:404")] +
          [{"hostname": "dashboard.beautymolt.com", "service": "http://nginx:80"}] +
          [{"service": "http_status:404"}]
        )
        | {config: {ingress: .result.config.ingress, "warp-routing": .result.config["warp-routing"]}}
      ')

      PUT_RESULT=$(curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$NEW_INGRESS")

      if echo "$PUT_RESULT" | jq -e '.success' | grep -q true; then
        echo -e "  ${COLOR_GREEN}+ Cloudflare Tunnel: dashboard.beautymolt.com hinzugefuegt${COLOR_NC}"
      else
        echo -e "  ${COLOR_YELLOW}! Cloudflare Tunnel Update fehlgeschlagen:${COLOR_NC}"
        echo "$PUT_RESULT" | jq -r '.errors[0].message // "unbekannt"'
      fi
    fi
  else
    echo -e "  ${COLOR_YELLOW}! Cloudflare Tunnel Config konnte nicht gelesen werden${COLOR_NC}"
  fi
else
  echo -e "  ${COLOR_YELLOW}! CF_TOKEN/CF_ACCOUNT_ID/CF_TUNNEL_ID fehlen in .env -- Tunnel manuell konfigurieren${COLOR_NC}"
fi

# ----------------------------------------------------------------
# 10. OPENCLAW NEU STARTEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[10/10] Starte OpenClaw + nginx neu...${COLOR_NC}"

docker compose -f "$STACK_DIR/docker-compose.yml" up -d --force-recreate openclaw
docker compose -f "$STACK_DIR/docker-compose.yml" restart nginx
sleep 5

unset GITHUB_TOKEN
unset PROJEKT_GPG_KEY

echo ""
echo -e "${COLOR_GREEN}==========================================${COLOR_NC}"
echo -e "${COLOR_GREEN}ugly-forge Bootstrap abgeschlossen!${COLOR_NC}"
echo -e "${COLOR_GREEN}==========================================${COLOR_NC}"
echo ""
echo -e "GitHub User:   $GITHUB_USERNAME"
echo -e "Skills:        $(ls "$OC_SKILLS" 2>/dev/null | wc -l) installiert"
echo -e "DB:            $FORGE_DB_DIR/projects.db"
echo -e "Dashboard:     https://dashboard.beautymolt.com"
echo ""

if grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
  echo -e "${COLOR_GREEN}openclaw.json: OK forge-Agenten konfiguriert${COLOR_NC}"
else
  echo -e "${COLOR_RED}openclaw.json: FEHLER -- bootstrap.sh erneut ausfuehren${COLOR_NC}"
fi

# DB Mount Verifikation
if docker inspect openclaw 2>/dev/null | grep -q "forge-db"; then
  echo -e "${COLOR_GREEN}DB Mount:      OK /home/node/forge-db gemountet${COLOR_NC}"
else
  echo -e "${COLOR_RED}DB Mount:      FEHLER -- forge-db nicht gemountet${COLOR_NC}"
  echo -e "${COLOR_YELLOW}               Pruefen: grep forge-db $STACK_DIR/docker-compose.yml${COLOR_NC}"
fi

echo ""
echo -e "Naechste Schritte:"
echo -e "  1. Agenten listen:  docker compose -f $STACK_DIR/docker-compose.yml exec openclaw node dist/index.js agents list"
echo -e "  2. Dashboard:       https://dashboard.beautymolt.com"
echo ""

#!/bin/bash
# ugly-forge bootstrap.sh
# Aktiviert die KI-Softwareschmiede auf einem bestehenden ugly-stack
# Idempotent -- kann beliebig oft ausgefuehrt werden
# Ausfuehren als normaler User (nicht root) -- sudo wird intern verwendet wenn noetig

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
    echo -e "  ${COLOR_YELLOW}sudo-Passwort wird benoetigt fuer $pkg:${COLOR_NC}"
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
echo -e "${COLOR_YELLOW}[1/9] Pruefe System-Abhaengigkeiten...${COLOR_NC}"

require_cmd curl
require_cmd git
require_cmd python3
require_cmd sqlite3

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
  echo -e "${COLOR_YELLOW}  User nicht in docker-Gruppe. Fix: sudo usermod -aG docker $USER && newgrp docker${COLOR_NC}"
fi

echo -e "${COLOR_GREEN}OK System-Abhaengigkeiten${COLOR_NC}"

# ----------------------------------------------------------------
# 2. UGLY-STACK UND OC PRUEFEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[2/9] Pruefe ugly-stack und OpenClaw...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}ugly-stack nicht gefunden unter $PARENT_DIR/${COLOR_NC}"
  echo -e "${COLOR_RED}Loesung: cd ~ && git clone https://github.com/uglyatbeautymolt/ugly-forge.git && cd ugly-forge && bash bootstrap.sh${COLOR_NC}"
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
echo -e "${COLOR_YELLOW}[3/9] Lese GITHUB_TOKEN...${COLOR_NC}"

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
echo -e "${COLOR_YELLOW}[4/9] Lese PROJEKT_GPG_KEY...${COLOR_NC}"

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
echo -e "${COLOR_YELLOW}[5/9] Installiere Skills...${COLOR_NC}"
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
echo -e "${COLOR_YELLOW}[6/9] Installiere Workspace-Dateien...${COLOR_NC}"
mkdir -p "$OC_WORKSPACE"

cp "$FORGE_DIR/workspace/AGENTS.md" "$OC_WORKSPACE/AGENTS.md"
cp "$FORGE_DIR/workspace/FORGE-INDEX-template.md" "$OC_WORKSPACE/FORGE-INDEX-template.md"
mkdir -p "$OC_WORKSPACE/projects"

echo -e "${COLOR_GREEN}OK AGENTS.md installiert${COLOR_NC}"

# ----------------------------------------------------------------
# 7. OPENCLAW.JSON MERGEN
#
# openclaw-forge.json ist jetzt reines JSON (kein JSON5 mehr).
# Merge via python3 stdlib json -- kein externer Parser noetig.
# Script wird als temp-Datei geschrieben um Heredoc/Argumente-
# Probleme zu vermeiden.
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[7/9] Konfiguriere openclaw.json...${COLOR_NC}"

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

  # Python-Script als temp-Datei -- keine Heredoc/Argumente-Probleme
  MERGE_SCRIPT="/tmp/oc_merge_$$.py"
  cat > "$MERGE_SCRIPT" << PYEOF
import json, sys

config_path = "$OC_CONFIG"
forge_path  = "$FORGE_JSON"

with open(config_path, 'r') as f:
    existing = json.load(f)

with open(forge_path, 'r') as f:
    forge = json.load(f)

# agents-Struktur sicherstellen
if 'agents' not in existing:
    existing['agents'] = {}

# defaults.tools.loopDetection hinzufuegen falls fehlend
forge_loop = forge['agents']['defaults']['tools']['loopDetection']
ex_defaults = existing['agents'].setdefault('defaults', {})
ex_tools    = ex_defaults.setdefault('tools', {})
if 'loopDetection' not in ex_tools:
    ex_tools['loopDetection'] = forge_loop

# agents.list: forge-Agenten hinzufuegen (keine Duplikate)
forge_agents = forge['agents']['list']
ex_list      = existing['agents'].setdefault('list', [])
ex_ids       = {a.get('id') for a in ex_list}

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
# 8. SQLITE DB
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[8/9] Initialisiere SQLite Datenbank...${COLOR_NC}"

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

STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
if grep -q "forge-db\|forge_db" "$STACK_COMPOSE" 2>/dev/null; then
  echo -e "  v DB Volume Mount bereits vorhanden"
else
  DB_MOUNT="      - $FORGE_DB_DIR:/home/node/forge-db"
  sed -i "/\.:\/home\/node\/www/a\\$DB_MOUNT" "$STACK_COMPOSE"
  echo -e "  + DB Volume Mount in docker-compose.yml ergaenzt"
fi

# ----------------------------------------------------------------
# 9. OPENCLAW NEU STARTEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[9/9] Starte OpenClaw neu...${COLOR_NC}"

docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw
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
echo ""

if grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
  echo -e "${COLOR_GREEN}openclaw.json: OK forge-Agenten konfiguriert${COLOR_NC}"
else
  echo -e "${COLOR_RED}openclaw.json: FEHLER -- bootstrap.sh erneut ausfuehren${COLOR_NC}"
fi

echo ""
echo -e "Naechste Schritte:"
echo -e "  1. Agenten: openclaw agents list"
echo -e "  2. Starten: openclaw agent --agent forge-orchestrator --message 'Hallo'"
echo -e "  3. Dashboard: bash $FORGE_DIR/dashboard/build.sh"
echo ""

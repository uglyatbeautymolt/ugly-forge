#!/bin/bash
# ugly-forge bootstrap.sh
# Aktiviert die KI-Softwareschmiede auf einem bestehenden ugly-stack
# Idempotent — kann beliebig oft ausgeführt werden
# Ausführen als normaler User (nicht root) — sudo wird intern verwendet wenn nötig
#
# WICHTIG: ugly-forge muss NEBEN ugly-stack liegen:
#   ~/VPS_Bootstrap/   ← ugly-stack
#   ~/ugly-forge/      ← dieses Repo (hier klonen!)
#
# Korrekte Installation:
#   cd ~
#   git clone https://github.com/uglyatbeautymolt/ugly-forge.git
#   cd ugly-forge
#   bash bootstrap.sh

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

echo -e "${COLOR_BLUE}🦞🔨 ugly-forge Bootstrap startet...${COLOR_NC}"
echo -e "${COLOR_BLUE}   Verzeichnis: $FORGE_DIR${COLOR_NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# HILFSFUNKTIONEN
# ─────────────────────────────────────────────────────────────

install_pkg() {
  local pkg="$1"
  echo -e "  Installiere $pkg..."
  if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
    sudo apt-get install -y "$pkg" -qq
  elif [ "$(id -u)" = "0" ]; then
    apt-get install -y "$pkg" -qq
  else
    echo -e "  ${COLOR_YELLOW}sudo-Passwort wird benötigt um $pkg zu installieren:${COLOR_NC}"
    sudo apt-get install -y "$pkg" -qq
  fi
}

require_cmd() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "  ${COLOR_YELLOW}⚠ $cmd nicht gefunden — installiere $pkg${COLOR_NC}"
    install_pkg "$pkg"
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "${COLOR_RED}❌ Konnte $cmd nicht installieren. Bitte manuell: apt-get install $pkg${COLOR_NC}"
      exit 1
    fi
    echo -e "  ${COLOR_GREEN}✅ $cmd installiert${COLOR_NC}"
  else
    echo -e "  ✓ $cmd"
  fi
}

# ─────────────────────────────────────────────────────────────
# 1. SYSTEM-ABHÄNGIGKEITEN
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[1/9] Prüfe und installiere System-Abhängigkeiten...${COLOR_NC}"

if ! command -v apt-get &> /dev/null; then
  echo -e "${COLOR_YELLOW}  ⚠ apt-get nicht gefunden — kein automatisches Installieren möglich${COLOR_NC}"
  echo -e "${COLOR_YELLOW}    Bitte manuell sicherstellen: sqlite3, curl, python3, git${COLOR_NC}"
fi

require_cmd curl
require_cmd git
require_cmd python3
require_cmd sqlite3

if ! command -v docker &> /dev/null; then
  echo -e "${COLOR_RED}❌ docker nicht gefunden. Muss manuell installiert werden.${COLOR_NC}"
  echo -e "${COLOR_RED}   https://docs.docker.com/engine/install/${COLOR_NC}"
  exit 1
fi
echo -e "  ✓ docker"

if ! docker compose version &> /dev/null 2>&1; then
  echo -e "${COLOR_RED}❌ 'docker compose' Plugin nicht gefunden.${COLOR_NC}"
  echo -e "${COLOR_RED}   sudo apt-get install docker-compose-plugin${COLOR_NC}"
  exit 1
fi
echo -e "  ✓ docker compose"

if [ "$(id -u)" != "0" ] && ! groups | grep -q docker; then
  echo -e "${COLOR_YELLOW}  ⚠ User '$(whoami)' nicht in docker-Gruppe.${COLOR_NC}"
  echo -e "${COLOR_YELLOW}    Fix: sudo usermod -aG docker \$USER && newgrp docker${COLOR_NC}"
fi

echo -e "${COLOR_GREEN}✅ Alle System-Abhängigkeiten vorhanden${COLOR_NC}"

# ─────────────────────────────────────────────────────────────
# 2. UGLY-STACK UND OC PRÜFEN
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[2/9] Prüfe ugly-stack und OpenClaw...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}❌ ugly-stack nicht gefunden!${COLOR_NC}"
  echo -e ""
  echo -e "${COLOR_RED}   ugly-forge muss NEBEN ugly-stack liegen:${COLOR_NC}"
  echo -e "${COLOR_RED}   $PARENT_DIR/${COLOR_NC}"
  echo -e "${COLOR_RED}   ├── VPS_Bootstrap/   ← ugly-stack (hier erwartet)${COLOR_NC}"
  echo -e "${COLOR_RED}   └── ugly-forge/      ← du bist hier${COLOR_NC}"
  echo -e ""
  echo -e "${COLOR_RED}   Lösung:${COLOR_NC}"
  echo -e "${COLOR_RED}     cd ~${COLOR_NC}"
  echo -e "${COLOR_RED}     git clone https://github.com/uglyatbeautymolt/ugly-forge.git${COLOR_NC}"
  echo -e "${COLOR_RED}     cd ugly-forge && bash bootstrap.sh${COLOR_NC}"
  exit 1
fi

if ! docker compose -f "$STACK_DIR/docker-compose.yml" ps openclaw 2>/dev/null | grep -q "Up"; then
  echo -e "${COLOR_RED}❌ OpenClaw läuft nicht.${COLOR_NC}"
  echo -e "${COLOR_RED}   Starten: cd $STACK_DIR && docker compose up -d${COLOR_NC}"
  exit 1
fi

if [ ! -d "$OC_DATA" ]; then
  echo -e "${COLOR_RED}❌ openclaw-data Volume nicht gefunden: $OC_DATA${COLOR_NC}"
  exit 1
fi

echo -e "${COLOR_GREEN}✅ ugly-stack: $STACK_DIR${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ OC Data:    $OC_DATA${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ OpenClaw läuft${COLOR_NC}"

# ─────────────────────────────────────────────────────────────
# 3. GITHUB_TOKEN
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[3/9] Lese GITHUB_TOKEN aus ugly-stack Git Remote...${COLOR_NC}"

REMOTE_URL=$(git -C "$STACK_DIR" remote get-url origin 2>/dev/null || echo "")
GITHUB_TOKEN=$(echo "$REMOTE_URL" | sed 's|https://||' | cut -d'@' -f1)

if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "$REMOTE_URL" ]; then
  echo -e "${COLOR_RED}❌ Kein Token in Git Remote URL gefunden${COLOR_NC}"
  echo -e "${COLOR_RED}   Erwartet: https://<TOKEN>@github.com/...${COLOR_NC}"
  exit 1
fi

HTTP_CODE=$(curl -s -o /tmp/gh_forge.json -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${COLOR_RED}❌ GitHub Token ungültig (HTTP $HTTP_CODE)${COLOR_NC}"
  unset GITHUB_TOKEN; rm -f /tmp/gh_forge.json; exit 1
fi

GITHUB_USERNAME=$(python3 -c 'import sys,json; print(json.load(open("/tmp/gh_forge.json"))["login"])' 2>/dev/null)
rm -f /tmp/gh_forge.json
echo -e "${COLOR_GREEN}✅ GitHub Token gültig — User: $GITHUB_USERNAME${COLOR_NC}"

# ─────────────────────────────────────────────────────────────
# 4. PROJEKT_GPG_KEY
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[4/9] Lese PROJEKT_GPG_KEY aus ugly-stack .env...${COLOR_NC}"

STACK_ENV="$STACK_DIR/.env"
if [ ! -f "$STACK_ENV" ]; then
  echo -e "${COLOR_RED}❌ .env nicht gefunden: $STACK_ENV${COLOR_NC}"
  unset GITHUB_TOKEN; exit 1
fi

PROJEKT_GPG_KEY=$(grep "^PROJEKT_GPG_KEY=" "$STACK_ENV" | cut -d'=' -f2-)
if [ -z "$PROJEKT_GPG_KEY" ]; then
  echo -e "${COLOR_RED}❌ PROJEKT_GPG_KEY fehlt in $STACK_ENV${COLOR_NC}"
  echo -e "${COLOR_RED}   Erzeugen: openssl rand -base64 48${COLOR_NC}"
  unset GITHUB_TOKEN; exit 1
fi
echo -e "${COLOR_GREEN}✅ PROJEKT_GPG_KEY gelesen (${#PROJEKT_GPG_KEY} Zeichen)${COLOR_NC}"

if ! grep -q "^GITHUB_USERNAME=" "$STACK_ENV"; then
  echo "" >> "$STACK_ENV"
  echo "# ugly-forge" >> "$STACK_ENV"
  echo "GITHUB_USERNAME=$GITHUB_USERNAME" >> "$STACK_ENV"
  echo -e "  ${COLOR_GREEN}+ GITHUB_USERNAME in .env hinzugefügt${COLOR_NC}"
fi

# ─────────────────────────────────────────────────────────────
# 5. SKILLS
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[5/9] Installiere Skills in OC Shared-Skills-Verzeichnis...${COLOR_NC}"
mkdir -p "$OC_SKILLS"

SKILL_COUNT=0
for SKILL_DIR in "$FORGE_DIR/workspace/skills/"/*/; do
  if [ -d "$SKILL_DIR" ]; then
    SKILL_NAME=$(basename "$SKILL_DIR")
    TARGET="$OC_SKILLS/$SKILL_NAME"
    rm -rf "$TARGET"
    cp -r "$SKILL_DIR" "$TARGET"
    SKILL_COUNT=$((SKILL_COUNT + 1))
    echo -e "  ${COLOR_GREEN}+ $SKILL_NAME${COLOR_NC}"
  fi
done
echo -e "${COLOR_GREEN}✅ $SKILL_COUNT Skills installiert in: $OC_SKILLS${COLOR_NC}"

# ─────────────────────────────────────────────────────────────
# 6. WORKSPACE
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[6/9] Installiere Workspace-Dateien...${COLOR_NC}"
mkdir -p "$OC_WORKSPACE"

cp "$FORGE_DIR/workspace/AGENTS.md" "$OC_WORKSPACE/AGENTS.md"
cp "$FORGE_DIR/workspace/FORGE-INDEX-template.md" "$OC_WORKSPACE/FORGE-INDEX-template.md"
mkdir -p "$OC_WORKSPACE/projects"

echo -e "${COLOR_GREEN}✅ AGENTS.md → $OC_WORKSPACE/AGENTS.md${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ FORGE-INDEX-template.md installiert${COLOR_NC}"

# ─────────────────────────────────────────────────────────────
# 7. OPENCLAW.JSON — automatisch mergen
#    Wenn bereits vorhanden: forge-Agenten hinzufügen ohne bestehende Config zu zerstören
#    Wenn nicht vorhanden: direkt kopieren
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[7/9] Konfiguriere openclaw.json...${COLOR_NC}"

FORGE_AGENTS_JSON="$FORGE_DIR/workspace/openclaw-forge.json"

if [ ! -f "$OC_CONFIG" ]; then
  # Neu anlegen — direkt kopieren
  cp "$FORGE_AGENTS_JSON" "$OC_CONFIG"
  echo -e "${COLOR_GREEN}✅ openclaw.json erstellt (JSON5, 12 Agenten)${COLOR_NC}"
else
  # Bereits vorhanden — intelligent mergen via Python3
  # Prüfen ob forge-Agenten bereits drin sind
  if grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
    echo -e "  ✓ forge-Agenten bereits in openclaw.json — überspringe Merge"
  else
    echo -e "  Merge forge-Agenten in bestehende openclaw.json..."

    # Backup erstellen
    cp "$OC_CONFIG" "${OC_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "  ${COLOR_GREEN}+ Backup erstellt: ${OC_CONFIG}.backup-*${COLOR_NC}"

    # Python3 Merge-Script
    # Strategie: JSON5-Kommentare entfernen, dann als JSON parsen und mergen
    python3 << PYEOF
import json, re, sys

def strip_json5_comments(text):
    """Entfernt // und /* */ Kommentare aus JSON5"""
    # /* */ Kommentare
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    # // Kommentare (aber nicht URLs wie https://)
    text = re.sub(r'(?<!:)//[^\n]*', '', text)
    # Trailing commas vor } oder ]
    text = re.sub(r',(\s*[}\]])', r'\1', text)
    return text

try:
    # Bestehende openclaw.json lesen
    with open('$OC_CONFIG', 'r') as f:
        existing_raw = f.read()

    # forge-Config lesen
    with open('$FORGE_AGENTS_JSON', 'r') as f:
        forge_raw = f.read()

    # JSON5 -> JSON
    existing = json.loads(strip_json5_comments(existing_raw))
    forge = json.loads(strip_json5_comments(forge_raw))

    # Sicherstellen dass agents-Struktur vorhanden
    if 'agents' not in existing:
        existing['agents'] = {}
    if 'list' not in existing['agents']:
        existing['agents']['list'] = []
    if 'defaults' not in existing['agents']:
        existing['agents']['defaults'] = {}

    # Workspace-Default setzen falls nicht vorhanden
    if 'workspace' not in existing['agents']['defaults']:
        existing['agents']['defaults']['workspace'] = '~/.openclaw/workspace'

    # loopDetection unter agents.defaults.tools eintragen
    if 'tools' not in existing['agents']['defaults']:
        existing['agents']['defaults']['tools'] = {}
    if 'loopDetection' not in existing['agents']['defaults']['tools']:
        existing['agents']['defaults']['tools']['loopDetection'] = forge['agents']['defaults']['tools']['loopDetection']

    # Forge-Agenten hinzufügen (bestehende IDs nicht doppeln)
    existing_ids = {a.get('id') for a in existing['agents']['list']}
    forge_agents = forge['agents']['list']
    added = 0
    for agent in forge_agents:
        if agent['id'] not in existing_ids:
            existing['agents']['list'].append(agent)
            added += 1

    # Zurückschreiben als sauberes JSON
    with open('$OC_CONFIG', 'w') as f:
        json.dump(existing, f, indent=2, ensure_ascii=False)

    print(f"OK:{added}")

except Exception as e:
    print(f"ERR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF

    MERGE_RESULT=$?
    if [ $MERGE_RESULT -ne 0 ]; then
      echo -e "${COLOR_RED}❌ Merge fehlgeschlagen — stelle Backup wieder her${COLOR_NC}"
      cp "${OC_CONFIG}.backup-"* "$OC_CONFIG" 2>/dev/null || true
      exit 1
    fi

    # Wieviele Agenten wurden hinzugefügt?
    ADDED_COUNT=$(python3 -c "
import json
with open('$OC_CONFIG') as f:
    cfg = json.load(f)
forge_ids = ['forge-orchestrator','forge-requirements','forge-review','forge-architekt',
             'forge-webdesigner','forge-db','forge-backend','forge-frontend',
             'forge-qa','forge-devops','forge-retro','forge-model-scout']
found = sum(1 for a in cfg.get('agents',{}).get('list',[]) if a.get('id') in forge_ids)
print(found)
" 2>/dev/null || echo "0")

    echo -e "${COLOR_GREEN}✅ openclaw.json gemergt — $ADDED_COUNT/12 forge-Agenten eingetragen${COLOR_NC}"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 8. SQLITE DB
# ─────────────────────────────────────────────────────────────
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

echo -e "${COLOR_GREEN}✅ SQLite DB: $FORGE_DB_DIR/projects.db (6 Tabellen)${COLOR_NC}"

STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
if grep -q "forge-db\|forge_db" "$STACK_COMPOSE" 2>/dev/null; then
  echo -e "  ✓ DB Volume Mount bereits vorhanden"
else
  DB_MOUNT="      - $FORGE_DB_DIR:/home/node/forge-db"
  sed -i "/\.\:\/home\/node\/www/a\\$DB_MOUNT" "$STACK_COMPOSE"
  echo -e "  ${COLOR_GREEN}+ DB Volume Mount in docker-compose.yml ergänzt${COLOR_NC}"
fi

# ─────────────────────────────────────────────────────────────
# 9. OPENCLAW NEU STARTEN
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[9/9] Starte OpenClaw neu...${COLOR_NC}"

docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw
sleep 5

unset GITHUB_TOKEN
unset PROJEKT_GPG_KEY

echo ""
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo -e "${COLOR_GREEN}🦞🔨 ugly-forge Bootstrap abgeschlossen!${COLOR_NC}"
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo ""
echo -e "GitHub User:   $GITHUB_USERNAME"
echo -e "Skills:        $OC_SKILLS  ($(ls "$OC_SKILLS" 2>/dev/null | wc -l) installiert)"
echo -e "DB:            $FORGE_DB_DIR/projects.db"
echo -e "AGENTS.md:     $OC_WORKSPACE/AGENTS.md"
echo ""

if [ -f "$OC_CONFIG" ] && grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
  echo -e "${COLOR_GREEN}openclaw.json: ✅ forge-Agenten konfiguriert${COLOR_NC}"
else
  echo -e "${COLOR_RED}openclaw.json: ❌ forge-Agenten fehlen — bitte bootstrap.sh erneut ausführen${COLOR_NC}"
fi

echo ""
echo -e "Nächste Schritte:"
echo -e "  1. Agenten verifizieren:  openclaw agents list"
echo -e "  2. Forge starten:         openclaw agent --agent forge-orchestrator --message 'Hallo'"
echo -e "  3. Dashboard bauen:       bash $FORGE_DIR/dashboard/build.sh"
echo ""

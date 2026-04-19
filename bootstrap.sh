#!/bin/bash
# ugly-forge bootstrap.sh
# Aktiviert die KI-Softwareschmiede auf einem bestehenden ugly-stack
# Idempotent — kann beliebig oft ausgeführt werden
# Ausführen als normaler User (nicht root) — sudo wird intern verwendet wenn nötig

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
fi

require_cmd curl
require_cmd git
require_cmd python3
require_cmd sqlite3

if ! command -v docker &> /dev/null; then
  echo -e "${COLOR_RED}❌ docker nicht gefunden. https://docs.docker.com/engine/install/${COLOR_NC}"
  exit 1
fi
echo -e "  ✓ docker"

if ! docker compose version &> /dev/null 2>&1; then
  echo -e "${COLOR_RED}❌ 'docker compose' Plugin fehlt. sudo apt-get install docker-compose-plugin${COLOR_NC}"
  exit 1
fi
echo -e "  ✓ docker compose"

if [ "$(id -u)" != "0" ] && ! groups | grep -q docker; then
  echo -e "${COLOR_YELLOW}  ⚠ User nicht in docker-Gruppe. Fix: sudo usermod -aG docker \$USER && newgrp docker${COLOR_NC}"
fi

echo -e "${COLOR_GREEN}✅ Alle System-Abhängigkeiten vorhanden${COLOR_NC}"

# ─────────────────────────────────────────────────────────────
# 2. UGLY-STACK UND OC PRÜFEN
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[2/9] Prüfe ugly-stack und OpenClaw...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}❌ ugly-stack nicht gefunden unter $PARENT_DIR/${COLOR_NC}"
  echo -e "${COLOR_RED}   Lösung: cd ~ && git clone https://github.com/uglyatbeautymolt/ugly-forge.git && cd ugly-forge && bash bootstrap.sh${COLOR_NC}"
  exit 1
fi

if ! docker compose -f "$STACK_DIR/docker-compose.yml" ps openclaw 2>/dev/null | grep -q "Up"; then
  echo -e "${COLOR_RED}❌ OpenClaw läuft nicht. Starten: cd $STACK_DIR && docker compose up -d${COLOR_NC}"
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
  echo -e "${COLOR_RED}❌ Kein Token in Git Remote URL. Erwartet: https://<TOKEN>@github.com/...${COLOR_NC}"
  exit 1
fi

HTTP_CODE=$(curl -s -o /tmp/gh_forge.json -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${COLOR_RED}❌ GitHub Token ungültig (HTTP $HTTP_CODE)${COLOR_NC}"
  unset GITHUB_TOKEN; rm -f /tmp/gh_forge.json; exit 1
fi

GITHUB_USERNAME=$(python3 -c 'import json; print(json.load(open("/tmp/gh_forge.json"))["login"])' 2>/dev/null)
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
  echo -e "${COLOR_RED}❌ PROJEKT_GPG_KEY fehlt. Erzeugen: openssl rand -base64 48${COLOR_NC}"
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
#
# Strategie: Beide Dateien mit Python stdlib json lesen.
# openclaw.json ist reines JSON (kein JSON5).
# openclaw-forge.json ist JSON5 — wir strippen Kommentare vor dem Parsen.
# Dann deep-merge: bestehende Werte behalten, forge-Agenten hinzufügen.
# ─────────────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[7/9] Konfiguriere openclaw.json...${COLOR_NC}"

if [ ! -f "$OC_CONFIG" ]; then
  cp "$FORGE_DIR/workspace/openclaw-forge.json" "$OC_CONFIG"
  echo -e "${COLOR_GREEN}✅ openclaw.json erstellt (12 Agenten)${COLOR_NC}"

elif grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
  echo -e "  ✓ forge-Agenten bereits in openclaw.json — überspringe"

else
  echo -e "  Merge forge-Agenten in bestehende openclaw.json..."

  BACKUP="${OC_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$OC_CONFIG" "$BACKUP"
  echo -e "  ${COLOR_GREEN}+ Backup: $BACKUP${COLOR_NC}"

  python3 - "$OC_CONFIG" "$FORGE_DIR/workspace/openclaw-forge.json" << 'PYEOF'
import json, re, sys

config_path = sys.argv[1]
forge_path  = sys.argv[2]

# --- bestehende openclaw.json lesen (reines JSON) ---
with open(config_path, 'r') as f:
    existing = json.load(f)

# --- forge JSON5 → JSON: nur Kommentare und trailing commas entfernen ---
with open(forge_path, 'r') as f:
    raw = f.read()

# Block-Kommentare /* ... */
raw = re.sub(r'/\*[\s\S]*?\*/', '', raw)
# Zeilen-Kommentare // am Anfang der Zeile (nach optionalem Whitespace)
raw = re.sub(r'(?m)^\s*//[^\n]*\n?', '', raw)
# Trailing commas vor } oder ]
raw = re.sub(r',(\s*[}\]])', r'\1', raw)

forge = json.loads(raw)

# --- Merge: agents.list hinzufügen ---
# Sicherstellen dass agents-Struktur vorhanden
if 'agents' not in existing:
    existing['agents'] = {}

# defaults: loopDetection hinzufügen falls nicht vorhanden
forge_defaults = forge.get('agents', {}).get('defaults', {})
ex_defaults = existing['agents'].setdefault('defaults', {})

if 'tools' not in ex_defaults:
    ex_defaults['tools'] = {}
if 'loopDetection' not in ex_defaults['tools']:
    ex_defaults['tools']['loopDetection'] = forge_defaults.get('tools', {}).get('loopDetection', {})

# list: forge-Agenten hinzufügen (keine Duplikate nach id)
forge_agents = forge.get('agents', {}).get('list', [])
existing_list = existing['agents'].setdefault('list', [])
existing_ids  = {a.get('id') for a in existing_list}

added = 0
for agent in forge_agents:
    if agent.get('id') not in existing_ids:
        existing_list.append(agent)
        added += 1

with open(config_path, 'w') as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"✅ {added} forge-Agenten eingetragen, {len(existing_list)} total in list")
PYEOF

  if [ $? -ne 0 ]; then
    echo -e "${COLOR_RED}❌ Merge fehlgeschlagen — stelle Backup wieder her${COLOR_NC}"
    cp "$BACKUP" "$OC_CONFIG"
    exit 1
  fi

  echo -e "${COLOR_GREEN}✅ openclaw.json erfolgreich gemergt${COLOR_NC}"
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
  echo -e "${COLOR_RED}openclaw.json: ❌ forge-Agenten fehlen — bootstrap.sh erneut ausführen${COLOR_NC}"
fi

echo ""
echo -e "Nächste Schritte:"
echo -e "  1. Agenten verifizieren:  openclaw agents list"
echo -e "  2. Forge starten:         openclaw agent --agent forge-orchestrator --message 'Hallo'"
echo -e "  3. Dashboard bauen:       bash $FORGE_DIR/dashboard/build.sh"
echo ""

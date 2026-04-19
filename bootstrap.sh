#!/bin/bash
# ugly-forge bootstrap.sh
# Aktiviert die KI-Softwareschmiede auf einem bestehenden ugly-stack
# Idempotent — kann beliebig oft ausgeführt werden

set -e

COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"

if [ ! -d "$STACK_DIR" ]; then
  STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"
fi

# OC läuft in Docker — openclaw-data ist das gemountete Volume
# Volume in docker-compose.yml: ./openclaw-data:/home/node/.openclaw
OC_DATA="$STACK_DIR/openclaw-data"
OC_WORKSPACE="$OC_DATA/workspace"       # ~/.openclaw/workspace/
OC_SKILLS="$OC_DATA/skills"             # ~/.openclaw/skills/  ← SHARED für ALLE Agenten
OC_CONFIG="$OC_DATA/openclaw.json"      # ~/.openclaw/openclaw.json

echo -e "${COLOR_BLUE}🦞🔨 ugly-forge Bootstrap startet...${COLOR_NC}"
echo ""

# ─────────────────────────────────────────────────────
# 1. Voraussetzungen prüfen
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[1/8] Prüfe Voraussetzungen...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}❌ ugly-stack nicht gefunden: $(dirname $FORGE_DIR)/VPS_Bootstrap oder ugly-stack${COLOR_NC}"
  exit 1
fi

if ! docker compose -f "$STACK_DIR/docker-compose.yml" ps openclaw 2>/dev/null | grep -q "running"; then
  echo -e "${COLOR_RED}❌ OpenClaw läuft nicht. Starte zuerst: cd $STACK_DIR && docker compose up -d${COLOR_NC}"
  exit 1
fi

if [ ! -d "$OC_DATA" ]; then
  echo -e "${COLOR_RED}❌ openclaw-data Volume nicht gefunden: $OC_DATA${COLOR_NC}"
  echo -e "${COLOR_RED}   Erwartet: $STACK_DIR/openclaw-data${COLOR_NC}"
  exit 1
fi

echo -e "${COLOR_GREEN}✅ ugly-stack: $STACK_DIR${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ OC Data:    $OC_DATA${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ OpenClaw läuft${COLOR_NC}"

# ─────────────────────────────────────────────────────
# 2. GITHUB_TOKEN aus Git Remote URL lesen
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[2/8] Lese GITHUB_TOKEN aus ugly-stack Git Remote...${COLOR_NC}"

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

# ─────────────────────────────────────────────────────
# 3. PROJEKT_GPG_KEY aus ugly-stack .env
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[3/8] Lese PROJEKT_GPG_KEY aus ugly-stack .env...${COLOR_NC}"

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

# GITHUB_USERNAME ergänzen falls fehlend
if ! grep -q "^GITHUB_USERNAME=" "$STACK_ENV"; then
  echo "" >> "$STACK_ENV"
  echo "# ugly-forge" >> "$STACK_ENV"
  echo "GITHUB_USERNAME=$GITHUB_USERNAME" >> "$STACK_ENV"
  echo -e "  ${COLOR_GREEN}+ GITHUB_USERNAME in .env hinzugefügt${COLOR_NC}"
fi

# ─────────────────────────────────────────────────────
# 4. Skills nach ~/.openclaw/skills/ kopieren
#    (geteilte Skills — für ALLE Agenten sichtbar)
#    Gemäss OC Docs: ~/.openclaw/skills/ ist shared scope
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[4/8] Installiere Skills in OC Shared-Skills-Verzeichnis...${COLOR_NC}"
mkdir -p "$OC_SKILLS"

SKILL_COUNT=0
for SKILL_DIR in "$FORGE_DIR/workspace/skills/"/*/; do
  if [ -d "$SKILL_DIR" ]; then
    SKILL_NAME=$(basename "$SKILL_DIR")
    TARGET="$OC_SKILLS/$SKILL_NAME"
    # Idempotent: immer überschreiben (neueste Version)
    rm -rf "$TARGET"
    cp -r "$SKILL_DIR" "$TARGET"
    SKILL_COUNT=$((SKILL_COUNT + 1))
    echo -e "  ${COLOR_GREEN}+ $SKILL_NAME${COLOR_NC}"
  fi
done
echo -e "${COLOR_GREEN}✅ $SKILL_COUNT Skills installiert in: $OC_SKILLS${COLOR_NC}"

# ─────────────────────────────────────────────────────
# 5. AGENTS.md + Workspace-Dateien in OC Workspace
#    ~/.openclaw/workspace/ — wird automatisch injiziert
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[5/8] Installiere Workspace-Dateien...${COLOR_NC}"
mkdir -p "$OC_WORKSPACE"

cp "$FORGE_DIR/workspace/AGENTS.md" "$OC_WORKSPACE/AGENTS.md"
cp "$FORGE_DIR/workspace/FORGE-INDEX-template.md" "$OC_WORKSPACE/FORGE-INDEX-template.md"
mkdir -p "$OC_WORKSPACE/projects"

echo -e "${COLOR_GREEN}✅ AGENTS.md → $OC_WORKSPACE/AGENTS.md${COLOR_NC}"
echo -e "${COLOR_GREEN}✅ FORGE-INDEX-template.md installiert${COLOR_NC}"

# ─────────────────────────────────────────────────────
# 6. openclaw.json — Agenten registrieren
#    JSON5 Format! Korrekte model.primary Syntax!
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[6/8] Konfiguriere openclaw.json...${COLOR_NC}"

if [ -f "$OC_CONFIG" ]; then
  echo -e "  ${COLOR_YELLOW}⚠ openclaw.json bereits vorhanden${COLOR_NC}"
  echo -e "  ${COLOR_YELLOW}  Bitte agents.list und tools.loopDetection aus folgender Datei manuell ergänzen:${COLOR_NC}"
  echo -e "  ${COLOR_YELLOW}  $FORGE_DIR/workspace/openclaw-forge.json${COLOR_NC}"
  echo -e "  ${COLOR_YELLOW}  Dann: docker compose restart openclaw${COLOR_NC}"
else
  cp "$FORGE_DIR/workspace/openclaw-forge.json" "$OC_CONFIG"
  echo -e "${COLOR_GREEN}✅ openclaw.json erstellt (JSON5, 12 Agenten)${COLOR_NC}"
fi

# ─────────────────────────────────────────────────────
# 7. SQLite DB erstellen (im ugly-forge/db/ Ordner)
#    Via Volume im Container erreichbar: /home/node/forge-db/
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[7/8] Initialisiere SQLite Datenbank...${COLOR_NC}"

FORGE_DB_DIR="$FORGE_DIR/db"
mkdir -p "$FORGE_DB_DIR"

if ! command -v sqlite3 &> /dev/null; then
  echo -e "  sqlite3 nicht gefunden, installiere..."
  apt-get install -y sqlite3 -qq
fi

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

# Volume Mount für DB in ugly-stack ergänzen
STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
if grep -q "forge-db\|forge_db" "$STACK_COMPOSE" 2>/dev/null; then
  echo -e "  ✓ DB Volume Mount bereits vorhanden"
else
  DB_MOUNT="      - $FORGE_DB_DIR:/home/node/forge-db"
  # Füge nach der www-Zeile ein
  sed -i "/\.\:\/home\/node\/www/a\\$DB_MOUNT" "$STACK_COMPOSE"
  echo -e "  ${COLOR_GREEN}+ DB Volume Mount in docker-compose.yml ergänzt${COLOR_NC}"
fi

# ─────────────────────────────────────────────────────
# 8. OpenClaw neu starten
# ─────────────────────────────────────────────────────
echo -e "${COLOR_YELLOW}[8/8] Starte OpenClaw neu...${COLOR_NC}"

docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw
sleep 5

# Secrets aus RAM löschen
unset GITHUB_TOKEN
unset PROJEKT_GPG_KEY

echo ""
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo -e "${COLOR_GREEN}🦞🔨 ugly-forge Bootstrap abgeschlossen!${COLOR_NC}"
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo ""
echo -e "GitHub User:   $GITHUB_USERNAME"
echo -e "Skills:        $OC_SKILLS  ($(ls $OC_SKILLS 2>/dev/null | wc -l) installiert)"
echo -e "DB:            $FORGE_DB_DIR/projects.db"
echo -e "AGENTS.md:     $OC_WORKSPACE/AGENTS.md"
echo ""

if [ -f "$OC_CONFIG" ] && grep -q 'forge-orchestrator' "$OC_CONFIG" 2>/dev/null; then
  echo -e "${COLOR_GREEN}openclaw.json: ✅ Agenten konfiguriert${COLOR_NC}"
else
  echo -e "${COLOR_YELLOW}openclaw.json: ⚠ Bitte manuell ergänzen:${COLOR_NC}"
  echo -e "${COLOR_YELLOW}  Datei: $FORGE_DIR/workspace/openclaw-forge.json${COLOR_NC}"
  echo -e "${COLOR_YELLOW}  In:    $OC_CONFIG${COLOR_NC}"
fi

echo ""
echo -e "Nächste Schritte:"
echo -e "  1. openclaw.json prüfen/ergänzen (falls nötig)"
echo -e "  2. OpenClaw Agenten verifizieren: openclaw agents list"
echo -e "  3. Forge starten: openclaw agent --agent forge-orchestrator --message 'Hallo, ich bin bereit'"
echo ""

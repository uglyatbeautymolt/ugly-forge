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

# Fallback: suche auch als ugly-stack
if [ ! -d "$STACK_DIR" ]; then
  STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"
fi

echo -e "${COLOR_BLUE}\ud83e\udd9e\ud83d\udd28 ugly-forge Bootstrap startet...${COLOR_NC}"
echo ""

# ─────────────────────────────────────────
# 1. Voraussetzungen prüfen
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[1/7] Prüfe Voraussetzungen...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}\u274c ugly-stack nicht gefunden. Erwartet in: $(dirname $FORGE_DIR)/VPS_Bootstrap oder ugly-stack${COLOR_NC}"
  exit 1
fi

if ! docker compose -f "$STACK_DIR/docker-compose.yml" ps openclaw 2>/dev/null | grep -q "running"; then
  echo -e "${COLOR_RED}\u274c OpenClaw läuft nicht. Starte zuerst ugly-stack.${COLOR_NC}"
  exit 1
fi

echo -e "${COLOR_GREEN}\u2705 ugly-stack gefunden: $STACK_DIR${COLOR_NC}"
echo -e "${COLOR_GREEN}\u2705 OpenClaw läuft${COLOR_NC}"

# ─────────────────────────────────────────
# 2. GITHUB_TOKEN aus Git Remote URL lesen
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[2/7] Lese GITHUB_TOKEN aus Git Remote URL...${COLOR_NC}"

REMOTE_URL=$(git -C "$STACK_DIR" remote get-url origin 2>/dev/null || echo "")

if [ -z "$REMOTE_URL" ]; then
  echo -e "${COLOR_RED}\u274c Kein Git Remote in ugly-stack gefunden${COLOR_NC}"
  exit 1
fi

GITHUB_TOKEN=$(echo "$REMOTE_URL" | sed 's|https://||' | cut -d'@' -f1)

if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "$REMOTE_URL" ]; then
  echo -e "${COLOR_RED}\u274c Kein Token in Git Remote URL gefunden${COLOR_NC}"
  echo -e "${COLOR_RED}  Erwartet: https://<TOKEN>@github.com/...${COLOR_NC}"
  exit 1
fi

# Token gegen GitHub API testen
HTTP_CODE=$(curl -s -o /tmp/gh_forge_test.json -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user)

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "${COLOR_RED}\u274c GitHub Token ungültig (HTTP $HTTP_CODE)${COLOR_NC}"
  unset GITHUB_TOKEN
  rm -f /tmp/gh_forge_test.json
  exit 1
fi

GITHUB_USERNAME=$(cat /tmp/gh_forge_test.json | python3 -c 'import sys,json; print(json.load(sys.stdin)["login"])' 2>/dev/null)
rm -f /tmp/gh_forge_test.json

echo -e "${COLOR_GREEN}\u2705 GitHub Token gültig — User: $GITHUB_USERNAME${COLOR_NC}"

# ─────────────────────────────────────────
# 3. PROJEKT_GPG_KEY aus ugly-stack .env lesen
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[3/7] Lese PROJEKT_GPG_KEY aus ugly-stack .env...${COLOR_NC}"

STACK_ENV="$STACK_DIR/.env"

if [ ! -f "$STACK_ENV" ]; then
  echo -e "${COLOR_RED}\u274c .env nicht gefunden in: $STACK_ENV${COLOR_NC}"
  unset GITHUB_TOKEN
  exit 1
fi

PROJEKT_GPG_KEY=$(grep "^PROJEKT_GPG_KEY=" "$STACK_ENV" | cut -d'=' -f2-)

if [ -z "$PROJEKT_GPG_KEY" ]; then
  echo -e "${COLOR_RED}\u274c PROJEKT_GPG_KEY fehlt in $STACK_ENV${COLOR_NC}"
  echo -e "${COLOR_RED}  Bitte PROJEKT_GPG_KEY in ugly-stack .env eintragen:${COLOR_NC}"
  echo -e "${COLOR_RED}  openssl rand -base64 48${COLOR_NC}"
  unset GITHUB_TOKEN
  exit 1
fi

echo -e "${COLOR_GREEN}\u2705 PROJEKT_GPG_KEY gelesen (${#PROJEKT_GPG_KEY} Zeichen)${COLOR_NC}"

# GITHUB_USERNAME in .env ergänzen falls fehlend
if ! grep -q "^GITHUB_USERNAME=" "$STACK_ENV"; then
  echo "" >> "$STACK_ENV"
  echo "# ugly-forge" >> "$STACK_ENV"
  echo "GITHUB_USERNAME=$GITHUB_USERNAME" >> "$STACK_ENV"
  echo -e "  ${COLOR_GREEN}+ GITHUB_USERNAME hinzugefügt${COLOR_NC}"
else
  echo -e "  \u2713 GITHUB_USERNAME bereits vorhanden"
fi

# ─────────────────────────────────────────
# 4. Ordnerstruktur erstellen
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[4/7] Erstelle Ordnerstruktur...${COLOR_NC}"

mkdir -p "$FORGE_DIR/workspace/skills"
mkdir -p "$FORGE_DIR/workspace/models"
mkdir -p "$FORGE_DIR/db"
mkdir -p "$FORGE_DIR/dashboard"
mkdir -p "$FORGE_DIR/bootstrap"

echo -e "${COLOR_GREEN}\u2705 Ordnerstruktur erstellt${COLOR_NC}"

# ─────────────────────────────────────────
# 5. SQLite Schema erstellen
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[5/7] Initialisiere SQLite Datenbank...${COLOR_NC}"

if ! command -v sqlite3 &> /dev/null; then
  echo -e "  sqlite3 nicht gefunden, installiere..."
  apt-get install -y sqlite3 -qq
fi

sqlite3 "$FORGE_DIR/db/projects.db" <<'SQL'
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

echo -e "${COLOR_GREEN}\u2705 SQLite Schema erstellt (6 Tabellen)${COLOR_NC}"

# ─────────────────────────────────────────
# 6. Volume Mount in ugly-stack ergänzen
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[6/7] Ergänze Volume Mount in ugly-stack...${COLOR_NC}"

STACK_COMPOSE="$STACK_DIR/docker-compose.yml"

if grep -q "ugly-forge\|ugly_forge" "$STACK_COMPOSE" 2>/dev/null; then
  echo -e "  \u2713 Volume Mount bereits vorhanden"
else
  FORGE_MOUNT="      - $FORGE_DIR/workspace:/home/node/forge"
  sed -i "/\.\:\/home\/node\/www/a\\\n$FORGE_MOUNT" "$STACK_COMPOSE"
  echo -e "  ${COLOR_GREEN}+ Volume Mount hinzugefügt${COLOR_NC}"
fi

# ─────────────────────────────────────────
# 7. OpenClaw neu starten
# ─────────────────────────────────────────
echo -e "${COLOR_YELLOW}[7/7] Starte OpenClaw neu...${COLOR_NC}"

docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw
sleep 5

# Secrets aus Speicher löschen
unset GITHUB_TOKEN
unset PROJEKT_GPG_KEY

echo ""
echo -e "${COLOR_GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${COLOR_NC}"
echo -e "${COLOR_GREEN}\ud83e\udd9e\ud83d\udd28 ugly-forge Bootstrap abgeschlossen!${COLOR_NC}"
echo -e "${COLOR_GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${COLOR_NC}"
echo ""
echo -e "GitHub User:  $GITHUB_USERNAME"
echo -e "Repo:         https://github.com/uglyatbeautymolt/ugly-forge"
echo -e "Datenbank:    $FORGE_DIR/db/projects.db"
echo -e "Skills:       $FORGE_DIR/workspace/skills/"
echo ""
echo -e "Nächster Schritt: Skills via OC Dashboard initialisieren"
echo ""

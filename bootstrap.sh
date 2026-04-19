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
STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"

# Fallback: suche ugly-stack auch als VPS_Bootstrap
if [ ! -d "$STACK_DIR" ]; then
  STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
fi

echo -e "${COLOR_BLUE}🦞🔨 ugly-forge Bootstrap startet...${COLOR_NC}"
echo ""

# 1. Voraussetzungen prüfen
echo -e "${COLOR_YELLOW}[1/7] Prüfe Voraussetzungen...${COLOR_NC}"

if [ ! -d "$STACK_DIR" ]; then
  echo -e "${COLOR_RED}❌ ugly-stack nicht gefunden in: $STACK_DIR${COLOR_NC}"
  exit 1
fi

if ! docker compose -f "$STACK_DIR/docker-compose.yml" ps openclaw | grep -q "running"; then
  echo -e "${COLOR_RED}❌ OpenClaw läuft nicht. Starte zuerst ugly-stack.${COLOR_NC}"
  exit 1
fi

echo -e "${COLOR_GREEN}✅ ugly-stack gefunden und OpenClaw läuft${COLOR_NC}"

# 2. .env.forge prüfen
echo -e "${COLOR_YELLOW}[2/7] Prüfe .env.forge...${COLOR_NC}"

if [ ! -f "$FORGE_DIR/.env.forge" ]; then
  echo -e "${COLOR_RED}❌ .env.forge fehlt. Bitte .env.example kopieren und ausfüllen:${COLOR_NC}"
  echo "  cp .env.example .env.forge"
  exit 1
fi

source "$FORGE_DIR/.env.forge"

if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$PROJEKT_GPG_KEY" ]; then
  echo -e "${COLOR_RED}❌ Fehlende Keys in .env.forge: GITHUB_TOKEN, GITHUB_USERNAME oder PROJEKT_GPG_KEY${COLOR_NC}"
  exit 1
fi

echo -e "${COLOR_GREEN}✅ .env.forge vollständig${COLOR_NC}"

# 3. .env in ugly-stack ergänzen
echo -e "${COLOR_YELLOW}[3/7] Ergänze ugly-stack .env...${COLOR_NC}"

STACK_ENV="$STACK_DIR/.env"

add_env_if_missing() {
  local key=$1
  local value=$2
  if ! grep -q "^${key}=" "$STACK_ENV"; then
    echo "${key}=${value}" >> "$STACK_ENV"
    echo -e "  ${COLOR_GREEN}+ ${key} hinzugefügt${COLOR_NC}"
  else
    echo -e "  ✓ ${key} bereits vorhanden"
  fi
}

add_env_if_missing "GITHUB_TOKEN" "$GITHUB_TOKEN"
add_env_if_missing "GITHUB_USERNAME" "$GITHUB_USERNAME"
add_env_if_missing "PROJEKT_GPG_KEY" "$PROJEKT_GPG_KEY"

# 4. Ordnerstruktur erstellen
echo -e "${COLOR_YELLOW}[4/7] Erstelle Ordnerstruktur...${COLOR_NC}"

mkdir -p "$FORGE_DIR/workspace/skills"
mkdir -p "$FORGE_DIR/workspace/models"
mkdir -p "$FORGE_DIR/db"
mkdir -p "$FORGE_DIR/dashboard"
mkdir -p "$FORGE_DIR/bootstrap"

echo -e "${COLOR_GREEN}✅ Ordnerstruktur erstellt${COLOR_NC}"

# 5. SQLite Schema erstellen
echo -e "${COLOR_YELLOW}[5/7] Initialisiere SQLite Datenbank...${COLOR_NC}"

if ! command -v sqlite3 &> /dev/null; then
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

echo -e "${COLOR_GREEN}✅ SQLite Schema erstellt${COLOR_NC}"

# 6. Volume Mount in ugly-stack ergänzen
echo -e "${COLOR_YELLOW}[6/7] Ergänze Volume Mount in ugly-stack...${COLOR_NC}"

STACK_COMPOSE="$STACK_DIR/docker-compose.yml"
FORGE_MOUNT="      - $FORGE_DIR/workspace:/home/node/forge"

if grep -q "ugly-forge/workspace" "$STACK_COMPOSE"; then
  echo -e "  ✓ Volume Mount bereits vorhanden"
else
  # Nach der www Volume Zeile einfügen
  sed -i "/\.\:\/home\/node\/www/a\\$FORGE_MOUNT" "$STACK_COMPOSE"
  echo -e "  ${COLOR_GREEN}+ Volume Mount hinzugefügt${COLOR_NC}"
fi

# 7. OpenClaw neu starten
echo -e "${COLOR_YELLOW}[7/7] Starte OpenClaw neu...${COLOR_NC}"

docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw
sleep 3

echo ""
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo -e "${COLOR_GREEN}🦞🔨 ugly-forge Bootstrap abgeschlossen!${COLOR_NC}"
echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
echo ""
echo -e "Nächster Schritt: Skills via OC Dashboard initialisieren"
echo -e "Repo: https://github.com/uglyatbeautymolt/ugly-forge"
echo ""

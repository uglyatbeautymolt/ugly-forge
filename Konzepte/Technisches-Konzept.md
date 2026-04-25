# ugly-forge — Technisches Konzept

**Version 1.0 | April 2026**

---

## 1. Systemübersicht

ugly-forge besteht aus drei Schichten, die zusammen die Schmiede bilden:

```
┌─────────────────────────────────────────────────────────┐
│                    ugly-stack (Basis)                   │
│  nginx · openclaw · n8n · searxng · cloudflared · ...   │
├─────────────────────────────────────────────────────────┤
│               ugly-forge (Erweiterung)                  │
│  forge-postgres · forge-db-api · forge-dashboard        │
├─────────────────────────────────────────────────────────┤
│            OpenClaw Agent Runtime (in openclaw)         │
│  12 Agenten · Skills · Workspace · Sessions             │
└─────────────────────────────────────────────────────────┘
```

Alle drei Schichten laufen im selben Docker-Netzwerk (`ugly-net`) auf dem Hetzner CX22 VPS (Ubuntu 24.04).

---

## 2. Docker Compose Architektur

### 2.1 Modular durch Override

ugly-forge nutzt das Docker Compose Override Pattern. Der Basis-Stack (`ugly-stack/docker-compose.yml`) wird nie angefasst. ugly-forge bringt eine eigene `docker-compose.override.yml`, die `bootstrap.sh` nach `ugly-stack/` kopiert. Docker Compose lädt beide Dateien automatisch beim Start aus demselben Verzeichnis — kein `-f` Flag nötig.

```
ugly-stack/
  docker-compose.yml            ← Basis (unverändert, versioniert in ugly-stack)
  docker-compose.override.yml   ← forge-Erweiterung (kopiert von ugly-forge, gitignored in ugly-stack)
```

### 2.2 forge-Container

```yaml
forge-postgres:
  image: postgres:16-alpine
  mem_limit: 256m
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U forge -d forge"]
    interval: 5s
    retries: 10
  volumes:
    - /home/alex/ugly-forge/db/postgres-data:/var/lib/postgresql/data

forge-db-api:
  build: /home/alex/ugly-forge/forge-db-api
  pull_policy: never          # kein Registry-Pull — immer lokal bauen
  depends_on:
    forge-postgres:
      condition: service_healthy   # startet erst wenn postgres healthy
  mem_limit: 64m

forge-dashboard:
  depends_on:
    forge-postgres:
      condition: service_healthy
  ports:
    - "3001:3001"
```

`pull_policy: never` ist wichtig: forge-db-api und forge-dashboard existieren nicht auf Docker Hub — sie werden lokal gebaut. Ohne dieses Flag würde Docker Compose bei jedem Start versuchen, das Image zu pullen.

### 2.3 openclaw Override

Der `openclaw` Container bekommt via Override zusätzliche Volumes und Umgebungsvariablen:

```yaml
openclaw:
  group_add:
    - "988"          # Docker-Gruppe — für Zugriff auf /var/run/docker.sock
  volumes:
    - /home/alex/ugly-stack/nginx/conf.d:/home/node/nginx-conf
    - /var/run/docker.sock:/var/run/docker.sock
  environment:
    - CF_TOKEN
    - CF_ACCOUNT_ID
    - CF_TUNNEL_ID
    - CF_ZONE_ID
    - FORGE_DOMAIN=beautymolt.com
```

Der Docker-Socket-Mount ermöglicht den Agenten, nginx per HUP-Signal neu zu laden, ohne dass `docker` als Binary im Container vorhanden sein muss — sie nutzen dafür die Docker Engine API direkt via `curl --unix-socket`.

### 2.4 Netzwerk

Alle Container kommunizieren über `ugly-net` (externes Docker-Netzwerk, erstellt von ugly-stack):

```yaml
networks:
  ugly-net:
    external: true
    name: ugly-net
```

DNS-Auflösung innerhalb von `ugly-net` erfolgt über den Docker-integrierten DNS-Resolver — Container erreichen sich gegenseitig über ihren `container_name` (z.B. `forge-db-api`, `forge-postgres`, `nginx`).

---

## 3. Datenhaltung — forge-postgres + forge-db-api

### 3.1 forge-postgres

PostgreSQL 16 Alpine als dedizierter Container für Schmiede-Metadaten. Datenpersistenz via Bind-Mount auf den Host (`/home/alex/ugly-forge/db/postgres-data`).

Credentials via Umgebungsvariable `FORGE_DB_PASSWORD`, die bootstrap.sh beim ersten Lauf generiert (`openssl rand -base64 32`) und in `ugly-stack/.env` speichert.

### 3.2 Schema (schema.sql)

Das Schema wird von `bootstrap.sh` eingespielt — nach dem Hochfahren von forge-postgres, vor dem Start von forge-db-api. Alle Tabellen sind idempotent (`CREATE TABLE IF NOT EXISTS`):

```sql
projects         -- Projektübersicht: id, name, slug, status, github_repo, budget_*
tasks            -- Aufgaben pro Projekt: agent, status, cost_*, iterations, blocked_reason
agent_questions  -- Agenten-Fragen: from/to, depth, parent_id, status
model_performance -- Modell-Metriken: tokens, cost, latency_ms, quality_score
agent_learnings  -- Retro-Erkenntnisse: problem, solution, effect, status
communications   -- Kommunikationslog: from/to, type, message
```

Zeitstempel durchgehend als `TIMESTAMPTZ DEFAULT NOW()` (PostgreSQL-nativ, nicht SQLite-kompatibel).

IDs als `TEXT PRIMARY KEY` — Agenten generieren UUIDs via PostgreSQL-Funktion:
```sql
gen_random_uuid()::text
```

### 3.3 forge-db-api

Ein schlanker HTTP-Wrapper (Fastify + node-postgres) der zwischen OpenClaw-Agenten und PostgreSQL sitzt. Agenten können kein PostgreSQL-Binary aufrufen — sie haben nur `curl` und `exec` zur Verfügung. forge-db-api löst das: jede SQL-Anfrage wird als HTTP-Request formuliert.

**Stack:**
- `fastify` — HTTP-Server
- `@fastify/formbody` — parst `application/x-www-form-urlencoded` Requests (nötig für `--data-urlencode`)
- `pg` (node-postgres) — Connection Pool zu forge-postgres

**Endpunkte:**
```
POST /query   — SQL ausführen, gibt { rows, rowCount, command } zurück
GET  /health  — gibt { status: "ok" } wenn DB erreichbar
```

**Request-Format** (form-encoded, nicht JSON):
```bash
curl -s -X POST http://forge-db-api:3002/query \
  --data-urlencode "sql=SELECT * FROM projects;"
```

`--data-urlencode` kodiert das SQL-Statement URL-sicher. `@fastify/formbody` dekodiert es serverseitig. Vorteil: SQL mit Sonderzeichen, Anführungszeichen und Leerzeilen funktioniert ohne Escaping-Probleme.

**Connection String:**
```
postgresql://forge:${FORGE_DB_PASSWORD}@forge-postgres:5432/forge
```

Dockerfile: `node:20-alpine`, nur `npm install --production`, kein Build-Step, kein Dev-Dependencies.

---

## 4. OpenClaw — Grundlagen

### 4.1 Was OpenClaw ist

OpenClaw (OC) ist ein lokales KI-Agent-Gateway. Es betreibt mehrere KI-Agenten gleichzeitig, jeder mit eigenem Kontext, eigener Modellkonfiguration und eigenem Workspace. Agenten kommunizieren über OC-interne Session-Mechanismen.

OC läuft als Docker Container (`openclaw`) und ist über `https://claw.beautymolt.com` erreichbar (Cloudflare Tunnel).

### 4.2 openclaw.json

Die zentrale Konfigurationsdatei liegt im OC-Datenverzeichnis (`openclaw-data/openclaw.json`). Sie ist im JSON5-Format (Kommentare erlaubt). bootstrap.sh schreibt und aktualisiert diese Datei.

Kritische Strukturpunkte:

```json5
{
  "gateway": {
    "mode": "local",
    "bind": "custom",
    "customBindHost": "0.0.0.0",
    "port": 18789,
    "auth": { "mode": "token", "token": "..." }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "...",
      "allowFrom": ["7769486934"]   // Nur Alex darf schreiben
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "openrouter/deepseek/deepseek-v3.2" },
      "workspace": "/home/node/.openclaw/workspace",
      "tools": {
        "loopDetection": {
          "enabled": true,
          "warningThreshold": 10,
          "criticalThreshold": 20,
          "globalCircuitBreakerThreshold": 30
        }
      }
    },
    "list": [
      {
        "id": "forge-orchestrator",
        "workspace": "~/.openclaw/workspace",
        "model": {
          "primary": "openrouter/google/gemini-2.5-flash-lite",
          "fallbacks": ["openrouter/google/gemini-2.5-flash"]
        }
      }
      // ... weitere Agenten
    ]
  }
}
```

**Wichtig:** Das Modell wird unter `model.primary` konfiguriert, nicht direkt als `model`. Falsche Struktur führt zu stillem Fallback auf das Default-Modell.

### 4.3 Modell-Routing via OpenRouter

Alle Modelle werden über OpenRouter bezogen (`openrouter/...`). Der API-Key liegt in `ugly-stack/.env`. OpenRouter ermöglicht, ohne separate API-Accounts auf Modelle verschiedener Anbieter zuzugreifen.

| Agent | Modell | Begründung |
|-------|--------|-----------|
| forge-orchestrator | `gemini-2.5-flash-lite` | Koordination: viele kurze Calls, günstig |
| forge-requirements | `gemini-2.5-flash` | Dialogfähig, strukturiert |
| forge-review | `deepseek-r1` | Reasoning-Modell für Qualitätsbewertung |
| forge-architekt | `deepseek-r1` | Reasoning für Systementwurf |
| forge-webdesigner | `gemini-2.5-flash` | Kreativ, visuell |
| forge-db | `gemini-2.5-flash-lite` | Schema einfach, günstig |
| forge-backend | `deepseek-chat` | Starker Coder |
| forge-frontend | `qwen3-coder` | Freies Tier, Frontend-Spezialist |
| forge-qa | `deepseek-chat` | Test-Kompetenz |
| forge-devops | `gemini-2.5-flash-lite` | Infrastruktur-Tasks, günstig |
| forge-retro | `deepseek-chat` | Analytisch |
| forge-model-scout | `gemini-2.5-flash` | Marktrecherche |

---

## 5. OpenClaw — Skills

### 5.1 Skill-System

Jeder Agenten-Skill ist ein Verzeichnis unter `~/.openclaw/skills/[name]/`. Pflichtdatei ist `SKILL.md`. Optional: `models.json` für skill-spezifische Modellkonfiguration.

```
openclaw-data/skills/
  orchestrator/
    SKILL.md          ← Instruktionen + Tool-Patterns
    models.json       ← (optional) Modell-Override
  requirements/
    SKILL.md
  ...
```

Der Skill wird einem Agenten zugewiesen über `"skill": "orchestrator"` im Agenten-Eintrag in `openclaw.json`. Skills sind **shared** — mehrere Agenten können denselben Skill nutzen.

### 5.2 SKILL.md Struktur

```markdown
---
name: forge_orchestrator
description: "Koordiniert alle ugly-forge Agenten... Aktiviert bei: neues Projekt starten, ..."
---

# Titel

## Abschnitt
Instruktionen und Tool-Patterns...
```

**Kritischer Hinweis zum Frontmatter:** Das `description`-Feld muss zwingend in doppelten Anführungszeichen stehen. Enthält die Beschreibung einen Doppelpunkt ohne Anführungszeichen, crasht der YAML-Parser beim Laden des Skills — der Agent startet nicht.

### 5.3 Stack-Priorität

bootstrap.sh kopiert Skills von `ugly-forge/workspace/skills/` nach `ugly-stack/openclaw-data/skills/`. Wenn ein Skill-Verzeichnis bereits existiert, wird es standardmäßig **übersprungen** (Stack-Priorität). Das bedeutet: beim ersten Bootstrap werden alle Skills installiert, bei Folge-Bootstraps nur neue Skills. Aktualisierungen müssen explizit force-kopiert werden.

### 5.4 FORGE-INDEX.md als Datei-basierter State

Jedes Projekt hat eine `FORGE-INDEX.md` im Projektordner. Sie dient als menschenlesbares State-Dokument und als Synchronisationspunkt zwischen Agenten — parallel zur PostgreSQL-Datenbank.

Der Index enthält: Projektname, Status, Agenten-Status-Tabelle (wer ist pending/done), Review-Gate-Zustand.

Agenten aktualisieren den Index via `sed -i` (kein OC-Tool nötig, direkte Dateimanipulation im Workspace):
```bash
exec: sed -i 's/| forge-requirements | pending/| forge-requirements | done/' /pfad/FORGE-INDEX.md
```

---

## 6. OpenClaw — Tool-Nutzung der Agenten

### 6.1 Das `exec` Tool

Das wichtigste Tool für Agenten in ugly-forge. `exec` führt Shell-Befehle im OpenClaw Container aus und gibt stdout/stderr zurück. Agenten sind damit in der Lage, mit dem Dateisystem, anderen Containern und externen APIs zu interagieren — ohne eigene Code-Ausführungsumgebung.

```
exec: [shell-befehl]
```

Beispiele wie Agenten exec nutzen:

```bash
# DB-Eintrag anlegen
exec: curl -s -X POST http://forge-db-api:3002/query \
  --data-urlencode "sql=INSERT INTO tasks (id, project_id, title, agent, status) \
  VALUES (gen_random_uuid()::text, 'proj-123', 'Requirements erstellen', 'forge-requirements', 'running');"

# Status aktualisieren
exec: curl -s -X POST http://forge-db-api:3002/query \
  --data-urlencode "sql=UPDATE tasks SET status='done', updated_at=NOW() \
  WHERE agent='forge-requirements' AND project_id='proj-123' AND status='running';"

# Datei schreiben
exec: cat > /home/node/.openclaw/workspace/projects/my-project/requirements.md << 'EOF'
# Requirements
...
EOF

# nginx neu laden (via Docker Socket)
exec: curl -s --unix-socket /var/run/docker.sock -X POST \
  "http://localhost/containers/nginx/kill?signal=HUP"

# Cloudflare API (Python inline)
exec: python3 << 'PYEOF'
import json, urllib.request, os
token = os.environ['CF_TOKEN']
# ...
PYEOF
```

### 6.2 `sessions_list` Tool

Zeigt alle aktiven OC-Sessions. Agenten nutzen es um zu prüfen, ob ein anderer Agent noch läuft, bevor sie eine neue Session starten.

```
sessions_list → gibt Liste aktiver Sessions mit IDs zurück
```

### 6.3 `sessions_send` Tool

Sendet eine Nachricht an eine bestehende Session (anderer Agent). Kann synchron (mit `timeoutSeconds`) oder asynchron genutzt werden.

```
sessions_send:
  sessionId: [id]
  message: "Bitte prüfe X"
  timeoutSeconds: 30      → wartet auf Antwort (synchron)
```

### 6.4 `openclaw agent` CLI (via exec)

Startet einen neuen Agenten als Subprocess:

```bash
exec: openclaw agent --agent forge-requirements --message "Starte Requirements für: MyProject"
```

### 6.5 maxSpawnDepth — warum die Pipeline sequenziell ist

OpenClaw begrenzt die Spawn-Tiefe von Agenten. Ein Agenten kann Subagenten starten, diese können weitere Subagenten starten — aber nur bis zur konfigurierten `maxSpawnDepth`. In ugly-forge ist die Tiefe 2:

```
Nutzer → forge-orchestrator (Tiefe 1)
              → forge-requirements (Tiefe 2)
                    → ❌ kein weiterer Spawn möglich
```

Das bedeutet: die Pipeline ist **sequenziell mit announce-back**. Jeder Agent führt seine Arbeit durch, sendet eine Abschluss-Nachricht zurück an den Orchestrator (via `sessions_send`), und der Orchestrator startet den nächsten Agenten. Echte Parallelisierung (mehrere Agenten gleichzeitig) ist innerhalb von OpenClaw durch diese Tiefenbegrenzung nicht möglich.

### 6.6 Loop Detection

OC überwacht automatisch sich wiederholende Muster in Agenten-Aktionen:

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `warningThreshold` | 10 | Erste Warnung ab 10 Wiederholungen |
| `criticalThreshold` | 20 | Kritischer Zustand |
| `globalCircuitBreakerThreshold` | 30 | Harter Stop |
| `historySize` | 30 | Analysefenster |

Detektoren: `genericRepeat`, `knownPollNoProgress` — erkennen Poll-Loops und identische aufeinanderfolgende Aktionen.

---

## 7. Agenten-SQL-Pattern im Detail

Das Standardmuster für jeden Agenten beim Start und Abschluss:

### Task anlegen (beim Start)
```bash
exec: curl -s -X POST http://forge-db-api:3002/query \
  --data-urlencode "sql=INSERT INTO tasks (id, project_id, title, agent, status) \
  VALUES (gen_random_uuid()::text, '[project_id]', '[Titel]', '[agent-id]', 'running');"
```

### Task abschliessen
```bash
exec: curl -s -X POST http://forge-db-api:3002/query \
  --data-urlencode "sql=UPDATE tasks SET status='done', updated_at=NOW() \
  WHERE agent='[agent-id]' AND project_id='[project_id]' AND status='running';"
```

### Projekt-Status setzen
```bash
exec: curl -s -X POST http://forge-db-api:3002/query \
  --data-urlencode "sql=UPDATE projects SET status='deployed', app_url='https://[slug].beautymolt.com', updated_at=NOW() \
  WHERE id='[project_id]';"
```

`gen_random_uuid()::text` ist eine PostgreSQL-Funktion — kein UUID-Generator im Shell-Script nötig. Das `::text` Cast ist nötig, weil die ID-Spalte als `TEXT` definiert ist, nicht als `UUID`.

---

## 8. bootstrap.sh — Aufbaulogik

bootstrap.sh ist idempotent: jeder Schritt prüft erst ob er nötig ist, bevor er handelt. Die Reihenfolge ist fest:

```
[1]  Voraussetzungen prüfen (ugly-stack läuft? Docker erreichbar?)
[2]  Credentials aus ugly-stack/.env lesen (GITHUB_TOKEN aus Git-Remote-URL)
[3]  FORGE_DB_PASSWORD generieren falls nicht vorhanden (openssl rand -base64 32)
[4]  Skills installieren (Stack-Priorität: nur neue Skills kopieren)
[5]  openclaw.json aktualisieren (Agenten, Modelle, loopDetection)
[6]  docker-compose.override.yml nach ugly-stack/ kopieren
[7]  YAML validieren (docker compose config --quiet)
[8]  forge-postgres starten → warten auf pg_isready (30x2s = 60s max)
     → Schema einspielen (prüft erst Tabellenanzahl, importiert nur wenn leer)
     → forge-db-api Image bauen + starten
     → Health-Check (docker exec forge-db-api curl localhost:3002/health)
[9]  forge-dashboard Image bauen + starten
[10] nginx konfigurieren (dashboard.beautymolt.com Block)
[11] Cloudflare Tunnel + DNS für dashboard.beautymolt.com
```

### Schema-Import Besonderheit

Der Schema-Import nutzt stdin-Redirect, da `schema.sql` nicht im postgres-Container liegt:

```bash
# Erst prüfen ob Tabellen existieren
TABLE_COUNT=$(docker exec forge-postgres psql -U forge -d forge -t -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")

# Nur importieren wenn leer
if [ "${TABLE_COUNT:-0}" -eq 0 ]; then
  docker exec -i forge-postgres psql -U forge -d forge < schema.sql
fi
```

### Health-Check ohne Host-Port

forge-db-api hat kein Host-Port-Mapping — es ist nur im Docker-Netz erreichbar. Der Health-Check läuft deshalb via `docker exec`:

```bash
docker exec forge-db-api curl -sf http://localhost:3002/health
```

`localhost` im Kontext von `docker exec forge-db-api` ist der forge-db-api Container selbst.

---

## 9. Dashboard

### Stack

- **Express** — HTTP-Server, Port 3001
- **WebSocket** (ws) — Live-Updates an Browser-Clients
- **pg** (node-postgres) — Pool-Verbindung zu forge-postgres

### Datenbankzugriff

Das Dashboard verbindet sich direkt mit forge-postgres (nicht via forge-db-api). Der Connection String kommt aus der Umgebungsvariable `DATABASE_URL`:

```
postgresql://forge:${FORGE_DB_PASSWORD}@forge-postgres:5432/forge
```

PostgreSQL-Queries sind parameterisiert (`$1, $2, ...`), nicht string-konkateniert.

### Volume Mounts

```
/home/alex/ugly-stack/www           → /home/node/www         (Webroot generierter Apps)
/home/alex/ugly-stack/.../projects  → /home/node/workspace/projects  (Projektdokumente)
/home/alex/ugly-stack/nginx/conf.d  → /home/node/nginx-conf  (nginx-Konfig schreiben)
/var/run/docker.sock                → /var/run/docker.sock   (Docker Engine API)
```

---

## 10. Deployment — forge-devops Pattern

### nginx-Konfiguration (pro Projekt)

```bash
exec: cat > /home/node/nginx-conf/[slug].conf << 'NGINXEOF'
server {
    listen 80;
    server_name [slug].beautymolt.com;
    location / {
        set $upstream http://[slug]-frontend:80;
        proxy_pass $upstream;
        proxy_set_header Host $host;
    }
}
NGINXEOF
```

```bash
# nginx neu laden ohne docker binary — via Docker Socket API
exec: curl -s --unix-socket /var/run/docker.sock -X POST \
  "http://localhost/containers/nginx/kill?signal=HUP"
```

### Cloudflare Integration

Cloudflare Tunnel + DNS werden per Python3-Script konfiguriert — Python3 ist im openclaw Container verfügbar, kein Zusatz-Install nötig:

```python
# Via exec: python3 << 'PYEOF'
import json, urllib.request, os
token = os.environ['CF_TOKEN']
# 1. Tunnel-Ingress via PUT (vollständige Config ersetzen, nicht nur anhängen)
# 2. DNS CNAME via POST (idempotent: erst prüfen ob vorhanden)
```

### Projekt-App-DB Container (forge-devops entscheidet den Typ)

forge-devops liest den DB-Typ aus `blueprint.md` und wählt das passende Template. Beispiel PostgreSQL:

```yaml
[slug]-postgres:
  image: postgres:16-alpine
  container_name: [slug]-postgres
  environment:
    POSTGRES_DB: [slug]
    POSTGRES_USER: [slug]
    POSTGRES_PASSWORD: ${[SLUG]_DB_PASSWORD}
  volumes:
    - [slug]-db-data:/var/lib/postgresql/data
  networks:
    - ugly-net
```

Der `DATABASE_URL` für die App:
```
postgresql://[slug]:${[SLUG]_DB_PASSWORD}@[slug]-postgres:5432/[slug]
```

---

## 11. Secrets-Management

### .env Struktur

```bash
# ugly-stack/.env (nicht versioniert)
GITHUB_TOKEN=...          # aus Git-Remote-URL extrahiert bei Bootstrap
PROJEKT_GPG_KEY=...       # aus Bitwarden, manuell gesetzt
FORGE_DB_PASSWORD=...     # auto-generiert von ugly-forge bootstrap.sh
CF_TOKEN=...
CF_ACCOUNT_ID=...
CF_TUNNEL_ID=...
CF_ZONE_ID=...
```

### Pre-Commit Hook

Jedes generierte Projekt-Repository erhält beim Init einen Pre-Commit Hook, der Commits mit Klartext-Secrets blockiert:

```bash
# .git/hooks/pre-commit
if git diff --cached | grep -E '(password|secret|api_key|token)\s*=\s*["'\''`][^"'\''`]{8,}'; then
  echo "Potenzielle Secrets gefunden! Commit blockiert."
  exit 1
fi
```

### .env.gpg

Projektspezifische Secrets werden mit `openpgp.js` (AES-256) verschlüsselt und als `.env.gpg` im Projekt-Repository versioniert. Die Verschlüsselung ist kompatibel mit dem `gpg` Binary — beide Seiten können entschlüsseln.

---

## 12. Lessons Learned — Technische Erkenntnisse (April 2026)

### sqlite3 CLI-Abhängigkeit

Das ursprüngliche Setup nutzte `sqlite3` CLI direkt im openclaw Container. Das Binary war nicht im Image enthalten. Watchtower-Lifecycle-Hooks (`post-update`) sollten es nach jedem Container-Update installieren — der Hook lief aber nicht zuverlässig (kein Log-Eintrag "Executing lifecycle hook", `apt-get update` fehlte vor `apt-get install`). Ergebnis: Agenten konnten keine DB-Einträge schreiben, Projekte blieben unsichtbar.

**Lösung:** Kein CLI-Binary im Agenten-Container. Stattdessen dedizierter HTTP-Service (forge-db-api), den Agenten per `curl` ansprechen. `curl` ist in jedem Linux-Container standardmäßig verfügbar.

### Watchtower Lifecycle Hooks

Watchtower führt `post-update` Hooks nach Image-Updates aus — nicht beim initialen Start. Für Installationen die beim Start benötigt werden, ist ein anderer Mechanismus nötig (Dockerfile, Entrypoint, oder dedizierter Service). Labels wurden entfernt:

```yaml
# ENTFERNT aus ugly-stack/docker-compose.yml:
labels:
  - "com.centurylinklabs.watchtower.lifecycle.post-update=/bin/sh -c 'apt-get install sqlite3'"
  - "com.centurylinklabs.watchtower.lifecycle.uid=0"
```

### Health Check Timing

`pg_isready` meldet "bereit" wenn PostgreSQL TCP-Verbindungen akzeptiert — nicht wenn die Datenbank vollständig initialisiert ist. Schema-Imports direkt nach `pg_isready` können fehlschlagen. Lösung: Prüfung ob Tabellen existieren (via `information_schema`), Import nur wenn nötig, harter Fehler-Exit statt stilles Maskieren.

### Host-Port vs. Docker-Netz

Container ohne `ports:`-Mapping sind vom Host aus nicht erreichbar — nur von anderen Containern im selben Netzwerk. Health-Checks für solche Container müssen via `docker exec [container] curl localhost:[port]` erfolgen, nicht via `curl localhost:[port]` auf dem Host.

### skillsSnapshot — Session-Cache bricht Skill-Updates

OpenClaw schreibt beim ersten Start einer Agent-Session den vollständigen Inhalt aller Skills als `skillsSnapshot` in `sessions.json`. Bei jedem Resume dieser Session wird der gecachte Snapshot verwendet — nicht die aktuellen Dateien auf dem Dateisystem. Das bedeutet:

- SKILL.md oder AGENTS.md auf dem Host ändern → aktive Sessions ignorieren die Änderung
- Fix: `sessions.json` der betroffenen Agenten leeren (`echo "{}" > sessions.json`) → nächster Start erzeugt neuen Snapshot mit aktuellem Stand
- Betrifft alle Agenten die eine persistente Session haben

### Fehlende Projekt-Registrierung durch den Orchestrator (April 2026)

Der Orchestrator-SKILL.md enthielt keinen `INSERT INTO projects` Schritt beim Projektstart. Die Pipeline lief an — Requirements wurden erfasst, FORGE-INDEX.md wurde erstellt — aber kein DB-Eintrag wurde angelegt. Das Dashboard zeigte nichts, da es ausschliesslich PostgreSQL liest.

**Analyse:** Das SKILL.md des Orchestrators definierte beim Start nur einen `SELECT` (bestehende Projekte lesen) aber keinen `INSERT` (neues Projekt anlegen). Die requirements-SKILL.md hatte zwar ein INSERT-Pattern, wurde aber in dieser Ausführung nicht erreicht, da der Orchestrator vorher abbrach.

**Fix:** Im Orchestrator-SKILL.md wurde ein verpflichtender "Neues Projekt anlegen"-Block ergänzt, der drei Schritte **vor dem Start der Pipeline** vorschreibt:
1. `INSERT INTO projects ... RETURNING id` → macht Projekt sofort im Dashboard sichtbar
2. `mkdir` Projektordner
3. FORGE-INDEX.md mit initialem Status anlegen

Der `RETURNING id` Clause in PostgreSQL liefert die generierte UUID direkt zurück, ohne einen separaten SELECT-Folgeaufruf.

**Weitere Ursache — nginx config Syntaxfehler (April 2026):** Ein doppelt eingefügter `}` in `nginx/conf.d/default.conf` (Zeile 77) brachte nginx in einen Restart-Loop. Alle Domains des VPS waren nicht erreichbar (502). Ursache: bootstrap.sh hatte den Dashboard-nginx-Block doppelt angehängt. Fix: überzählige `}` entfernt, nginx neu gestartet.

---

*Technisches Konzept ugly-forge | v1.1 | April 2026*

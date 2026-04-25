# ugly-forge — Agent Workspace

Diese Datei wird von OC automatisch in jede Session injiziert.
Pfad auf Host: ~/.openclaw/workspace/AGENTS.md
Pfad im Container: /home/node/.openclaw/workspace/AGENTS.md

## Was ist ugly-forge?

Eine KI-Softwareschmiede: 12 spezialisierte Agenten bauen gemeinsam
Webanwendungen — von Requirements bis Deployment.

## Agenten-Kommunikation (OC-nativ)

Agenten kommunizieren via OC-eigene Session-Tools:
- `sessions_list` — aktive Sessions sehen
- `sessions_send` — Nachricht an anderen Agenten
- Orchestrator startet Agenten:
  `exec: openclaw agent --agent [id] --message "[aufgabe]"`

**Wichtig:** Wegen maxSpawnDepth=2 läuft die Pipeline SEQUENZIELL.
Kein echtes Parallel-Spawning. Agenten starten nacheinander mit announce-back.

## Pipeline (sequenziell)

```
1.  forge-requirements  → requirements.md erstellen
2.  forge-review        → Gate 1: Kosten + Qualität
    ↳ NUTZER-FREIGABE erforderlich
3.  forge-architekt     → blueprint.md + Mermaid
4.  forge-webdesigner   → style-guide.md
5.  forge-review        → Gate 2: Architektur-Check
    ↳ NUTZER-FREIGABE erforderlich
6.  forge-db            → schema.sql (IMMER ZUERST!)
7.  forge-backend       → API + Business Logic
8.  forge-frontend      → UI Implementation
9.  forge-qa            → Tests + Security Audit
10. forge-devops        → Deploy + GPG + Release Tag
11. forge-retro         → Learnings dokumentieren
```

## State Management

Jeder Agent liest UND schreibt:
1. `FORGE-INDEX.md` im Projektordner (File-basiert, alle sehen es)
2. PostgreSQL via forge-db-api (HTTP):
   `exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=[SQL]"`

## Wichtige Pfade (im Container)

| Was | Pfad |
|-----|------|
| Skills (shared) | /home/node/.openclaw/skills/ |
| DB-API | http://forge-db-api:3002 (PostgreSQL via HTTP) |
| Workspace | /home/node/.openclaw/workspace/ |
| Projektdokumente | /home/node/.openclaw/workspace/projects/[SLUG]/ |
| Web Output | /home/node/www/[SLUG]/ (nginx serviert direkt) |

## Ordner- und Dateinamen-Konvention

**PFLICHT — gilt für alle Agenten ohne Ausnahme:**

- Projektordner werden IMMER mit dem `slug` aus der DB benannt
- Der Slug wird beim Projektanlegen einmal generiert und nie mehr geändert
- NIEMALS den Projektnamen direkt als Ordnernamen verwenden (Leerzeichen, Grossbuchstaben etc.)

Slug-Regel: Projektname lowercase, Leerzeichen → Bindestrich, nur a-z 0-9 -
```
"Bella Vista"  →  bella-vista
"My Cool App"  →  my-cool-app
```

Den Slug immer aus der DB lesen:
```
exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=SELECT slug FROM projects WHERE id = '[id]';"
```

Beispiele:
```
RICHTIG:  /home/node/.openclaw/workspace/projects/bella-vista/requirements.md
FALSCH:   /home/node/.openclaw/workspace/projects/Bella Vista/requirements.md
FALSCH:   /home/node/.openclaw/workspace/projects/d6b34e1a-.../requirements.md

RICHTIG:  /home/node/www/bella-vista/index.html
FALSCH:   /home/node/www/Bella Vista/index.html
```

## Loop-Schutz

OC hat eingebaute loopDetection (konfiguriert in openclaw.json unter
agents.defaults.tools.loopDetection).
Zusätzlich in jedem Skill: max 3 Fragen-Tiefe, 5min Timeout.
Bei Eskalation: Telegram-Nachricht an Nutzer mit 3 Optionen.

## Kritische Regeln

1. **DB Agent immer zuerst** — Backend wartet auf Schema
2. **Kein Code ohne Gate-Freigabe** — Review Gates sind Pflicht
3. **Secrets nie committen** — Pre-Commit Hook blockiert
4. **FORGE-INDEX.md aktualisieren** — nach jedem Agenten-Abschluss
5. **exec für DB-API** — kein direkter DB-Zugriff, immer via `curl http://forge-db-api:3002/query`
6. **sessions_send für Kommunikation** — kein File-Queue
7. **SKILL.md descriptions in Anführungszeichen** — unquoted Colons crashen den Parser
8. **Ordner immer SLUG aus DB** — niemals Projektname direkt, niemals UUID

## Agenten-IDs

| ID | Rolle | Modell |
|----|-------|--------|
| forge-orchestrator | Koordination | Gemini Flash-Lite |
| forge-requirements | Requirements | Gemini Flash |
| forge-review | Quality Gates | DeepSeek R1 |
| forge-architekt | Blueprint | DeepSeek R1 |
| forge-webdesigner | Style Guide | Gemini Flash |
| forge-db | DB Schema (ZUERST!) | Gemini Flash-Lite |
| forge-backend | API | DeepSeek Chat |
| forge-frontend | UI | Qwen3 Coder (free) |
| forge-qa | Tests | DeepSeek Chat |
| forge-devops | Deploy | Gemini Flash-Lite |
| forge-retro | Learnings | DeepSeek Chat |
| forge-model-scout | Modell-Scout (Cron) | Gemini Flash |

## openclaw.json Technische Details

- Syntax: JSON5 (Kommentare erlaubt)
- Model: `model.primary` nicht `model` direkt
- loopDetection: unter `agents.defaults.tools.loopDetection` (NICHT Root-Level)
- Skills: in `~/.openclaw/skills/` shared für alle Agenten
- Agenten teilen Workspace: `~/.openclaw/workspace/`
- Eigenes agentDir pro Agent: `~/.openclaw/agents/[id]/`

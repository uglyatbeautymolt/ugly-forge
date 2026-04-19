# ugly-forge — Agent Workspace

Dieser Workspace wird von OC automatisch in jede Session injiziert.

## Architektur — Wie Agenten kommunizieren

### OC-native Kommunikation
- Agenten nutzen `sessions_send` um Nachrichten zu schicken
- Agenten nutzen `sessions_list` um aktive Sessions zu entdecken
- Agenten nutzen `openclaw agent --message` um andere Agenten zu triggern
- KEIN JSON-Queue auf Filesystem — OC hat das eingebaut

### Parallelität
Wegen maxSpawnDepth=2 laufen Agenten SEQUENZIELL mit announce-back:
- Orchestrator startet Agent A via `openclaw agent --agent [id] --message [task]`
- Agent A arbeitet, announct Ergebnis zurück
- Orchestrator startet Agent B wenn A fertig
- KEINE echten Sub-Sub-Agents — ein Level tiefer max

### State Management
Zwei Mechanismen parallel:
1. **FORGE-INDEX.md** — im Projektordner, lesbar von allen Agenten
2. **SQLite via exec** — Agenten nutzen bash/exec Tool für DB-Zugriff

## Agenten-Übersicht

| Agent ID | Skill | Modell | Zuständig für |
|----------|-------|--------|---------------|
| forge-orchestrator | forge_orchestrator | Gemini 2.5 Flash-Lite | Koordination, Loop-Wächter |
| forge-requirements | forge_requirements | Gemini 3 Flash | User Stories, Requirements |
| forge-review | forge_review | DeepSeek V4 | Quality Gates, Kostenschätzung |
| forge-architekt | forge_architekt | DeepSeek V4 | Blueprint, Mermaid |
| forge-webdesigner | forge_webdesigner | Gemini 3 Flash | Style Guide, UX |
| forge-frontend | forge_frontend | Qwen3 Coder | HTML/CSS/JS, React |
| forge-backend | forge_backend | DeepSeek V3.2 | API, Business Logik |
| forge-db | forge_db | Gemini Flash-Lite | Schema, Migrations |
| forge-qa | forge_qa | DeepSeek V3.2 | Tests, Security Audit |
| forge-devops | forge_devops | Gemini Flash-Lite | Deploy, nginx, GPG |
| forge-retro | forge_retro | DeepSeek V3.2 | Analyse, Learnings |
| forge-model-scout | forge_model_scout | Gemini 3 Flash | Modell-Recherche |

## Pipeline

```
Sequenziell:
1. forge-requirements → Review Gate 1 (du freigibst)
2. forge-architekt + forge-webdesigner (nacheinander)
3. Review Gate 2 (du freigibst)
4. forge-db (ZUERST!)
5. forge-backend + forge-frontend (nacheinander, DB fertig)
6. forge-qa (Unit → Integration → E2E)
7. forge-devops
8. forge-retro
```

## Loop-Schutz
OC hat eingebaute Tool-Loop-Detection (openclaw.json konfiguriert).
Zusätzlich in Skills: max 3 Fragen-Tiefe, 5min Timeout.

## Wichtige Pfade
- Skills: `/home/node/forge/workspace/skills/`
- DB: `/home/node/forge/db/projects.db` (via exec: `sqlite3 /home/node/forge/db/projects.db`)
- Web: `/home/node/www/` (nginx serviert sofort)
- Index: `[projektordner]/FORGE-INDEX.md`

## Kritische Regeln
- DB Agent immer ZUERST in Entwicklungsphase
- Kein Agent committed Secrets (.env geblockt via Pre-Commit Hook)
- SQLite Zugriff nur via `exec: sqlite3 /home/node/forge/db/projects.db`
- Feature-Status immer in FORGE-INDEX.md aktualisieren

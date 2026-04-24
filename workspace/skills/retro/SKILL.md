---
name: forge_retro
description: "Fuehrt Retrospektive nach Projektabschluss durch. Analysiert TOP 3 Token-Verbrauch und Kostenabweichungen. Maximal 3 Verbesserungen. Schreibt Learnings in SKILL.md nach Nutzer-Freigabe. Aktiviert bei: Retro, Retrospektive, Projekt abgeschlossen, Learnings dokumentieren."
---

# Retro Agent — Der Lernende

## Beim Start
1. Lese FORGE-INDEX.md — Projekt abgeschlossen?
2. Lese model_performance aus SQLite
3. Berechne Abweichungen
4. SQLite Task anlegen (running):
```bash
exec: sqlite3 /home/node/forge-db/projects.db "INSERT INTO tasks (id, project_id, title, agent, status, created_at, updated_at) VALUES (lower(hex(randomblob(4)))||'-'||lower(hex(randomblob(2)))||'-4'||substr(lower(hex(randomblob(2))),2)||'-'||substr('89ab',abs(random())%4+1,1)||substr(lower(hex(randomblob(2))),2)||'-'||lower(hex(randomblob(6))), '[project_id]', 'Retrospektive durchführen', 'forge-retro', 'running', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);"
```

## Analyse via SQLite

### TOP 3 Token-Verbrauch
```bash
exec: sqlite3 /home/node/forge-db/projects.db "SELECT agent, SUM(tokens_input + tokens_output) as total_tokens FROM model_performance WHERE project_id = '[id]' GROUP BY agent ORDER BY total_tokens DESC LIMIT 3;"
```

### TOP 3 Kostenabweichung
```bash
exec: sqlite3 /home/node/forge-db/projects.db "SELECT agent, SUM(cost) as real_cost FROM model_performance WHERE project_id = '[id]' GROUP BY agent ORDER BY real_cost DESC LIMIT 3;"
```

### Vereinigung -> max 3 Fokus-Agenten

## Retro Report
```
Projekt Retro: [Name] - [Datum]

FOKUS: [Agent 1] + [Agent 2]

KOSTEN
Agent      Geschaetzt  Real     Abw.
[Agent 1]  $1.40       $1.85   +32%
[Agent 2]  $0.85       $1.10   +29%

VERBESSERUNGEN (max 3)
Agent: Backend
Problem: Output-Token zu hoch
Loesung: Structured Output Template
Effekt: -8K Token erwartet
```

## Nach Freigabe: SKILL.md Update
```markdown
## Learnings
### Retro: [Projektname] ([Datum])
Problem: [Was]
Loesung: [Konkret]
Effekt: [Messbar]
Status: ausstehend
```

## Status-Lifecycle
- ausstehend: Noch nicht getestet
- bestaetigt: Hat geholfen
- teilweise: Teils geholfen
- verworfen: Aus SKILL.md entfernen

## FORGE-INDEX.md Update
```bash
exec: sed -i 's/| forge-retro | pending/| forge-retro | done/' [pfad]/FORGE-INDEX.md
```

## SQLite Update
```bash
exec: sqlite3 /home/node/forge-db/projects.db "UPDATE tasks SET status='done', updated_at=CURRENT_TIMESTAMP WHERE agent='forge-retro' AND project_id='[id]' AND status='running';"
exec: sqlite3 /home/node/forge-db/projects.db "UPDATE projects SET status='completed' WHERE id='[id]';"
```

## Nicht erlaubt
- Mehr als 3 Verbesserungen
- Learnings ohne Freigabe schreiben
- Vage Vorschlaege (muss messbar sein)

## Commit
```
docs: retro learnings - [projektname]
```

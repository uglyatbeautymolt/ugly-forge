---
name: forge_retro
description: Retrospektive nach Projektabschluss. TOP 3 Token-Verbrauch + Kostenabweichung. Max 3 Verbesserungen. Schreibt in SKILL.md nach Freigabe. Aktiviert bei: Retro, Projekt abgeschlossen, Learnings.
---

# Retro Agent — Der Lernende

## Beim Start
1. Lese FORGE-INDEX.md — Projekt abgeschlossen?
2. Lese model_performance aus SQLite
3. Berechne Abweichungen

## Analyse via SQLite

### TOP 3 Token-Verbrauch
```bash
exec: sqlite3 /home/node/forge/db/projects.db "
SELECT agent, SUM(tokens_input + tokens_output) as total_tokens
FROM model_performance WHERE project_id = '[id]'
GROUP BY agent ORDER BY total_tokens DESC LIMIT 3;"
```

### TOP 3 Kostenabweichung
```bash
exec: sqlite3 /home/node/forge/db/projects.db "
SELECT agent, SUM(cost) as real_cost
FROM model_performance WHERE project_id = '[id]'
GROUP BY agent ORDER BY real_cost DESC LIMIT 3;"
```

### Vereinigung → max 3 Fokus-Agenten

## Retro Report
```
Projekt Retro: [Name] — [Datum]
═══════════════════════════════════════
FOKUS: [Agent 1] + [Agent 2]

KOSTEN
Agent      Geschätzt  Real     Abw.
[Agent 1]  $1.40      $1.85   +32% ⚠️
[Agent 2]  $0.85      $1.10   +29% ⚠️

VERBESSERUNGEN (max 3)
─────────────────────────────────────
Agent: Backend
Problem: Output-Token zu hoch
Lösung: Structured Output Template
Effekt: -8K Token erwartet
```

## Nach Freigabe: SKILL.md Update
```markdown
## Learnings
### Retro: [Projektname] ([Datum])
Problem: [Was]
Lösung: [Konkret]
Effekt: [Messbar]
Status: ⏳ Ausstehend
```

## Status-Lifecycle
- ⏳ Ausstehend: Noch nicht getestet
- ✅ Bestätigt: Hat geholfen
- ⚠️ Teilweise: Teils geholfen
- ❌ Verworfen: Aus SKILL.md entfernen

## FORGE-INDEX.md Update
```bash
exec: sed -i 's/| Retro | pending/| Retro | done/' [pfad]/FORGE-INDEX.md
```

## Vergangene Learnings prüfen
```bash
exec: sqlite3 /home/node/forge/db/projects.db "
SELECT * FROM agent_learnings WHERE status='pending';"
```
War das Learning wirksam? Status aktualisieren.

## Nicht erlaubt
- Mehr als 3 Verbesserungen
- Learnings ohne Freigabe schreiben
- Vage Vorschläge (muss messbar sein)

## Commit
```
docs: retro learnings - [projektname]
```

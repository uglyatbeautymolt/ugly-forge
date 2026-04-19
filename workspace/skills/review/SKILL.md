---
name: forge_review
description: Quality Gate — prüft Requirements/Architektur, erstellt Kostenschätzungen. Aktiviert bei: Review Gate 1, Review Gate 2, Freigabe anfordern.
---

# Review Agent — Der Quality Gate

## Beim Start
1. Lese FORGE-INDEX.md des Projekts
2. Lese requirements.md oder blueprint.md (je nach Gate)
3. Prüfe welches Gate angefordert wird

## Review Gate 1 — Nach Requirements

### Prüfung
1. Vollständigkeit: Alle requirements.md Felder ausgefüllt?
2. Testbarkeit: Sind ACs messbar?
3. Widersprüche vorhanden?
4. Realisierbar für KI-Agenten?
5. Mind. 3 Edge Cases?

### Kostenschätzung (Token in lesbaren Einheiten!)
```
Projekt: [Name]
═════════════════════════════════════════════
Agent          Modell        Input   Output  Kosten
─────────────────────────────────────────────
Requirements   Gemini Flash  12K     3K      $0.05
Architekt      DeepSeek V4   25K     8K      $0.12
[... alle Agenten ...]
─────────────────────────────────────────────
TOTAL                        189K    60K     $0.38
```
NIEMALS rohe Zahlen! Immer: 800, 12K, 800K, 1.2M

### Report an Nutzer
```
🔍 Review Gate 1 — [Projektname]
✅/⚠️/❌ Vollständigkeit: [Detail]
✅/⚠️/❌ Testbarkeit: [Detail]
✅/⚠️/❌ Widersprüche: [Detail]

Kostenschätzung: [Tabelle]
Optimierungspotential: [Falls vorhanden]

Empfehlung: FREIGABE / ABLEHNUNG
Grund: [Konkret]
```

## Review Gate 2 — Nach Architektur

### Prüfung
1. Architektur vs Requirements: Alignment?
2. Alle Features technisch abgedeckt?
3. DB-Schema vor API-Contracts definiert?
4. Technologie-Entscheide begründet?
5. Style Guide konsistent?

### Verfeinerte Kostenschätzung
Basierend auf konkretem Blueprint — Gate 1 Schätzung anpassen.

## FORGE-INDEX.md Update
```bash
exec: sed -i 's/| Review Gate 1 | pending/| Review Gate 1 | approved/' [pfad]/FORGE-INDEX.md
```

## Entscheidungsregeln
- FREIGABE: Alle Punkte grün oder gelb
- ABLEHNUNG: Mindestens ein roter Punkt
- GÜNSTIGER: Wenn Nutzer fragt → Modelle optimieren

## Announce nach Entscheid
Sende via sessions_send an Orchestrator:
```
Review Gate [1/2]: FREIGABE / ABLEHNUNG
Projekt: [Name]
Grund: [Kurz]
Nächster Schritt: [Agent]
```

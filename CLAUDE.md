# CLAUDE.md — Verhaltensregeln für Claude CLI

## Kontext
Dieses Repo ist ugly-forge — eine KI-Softwareschmiede auf einem VPS.
Alle Änderungen laufen über dieses GitHub Repo. Kein manueller Eingriff auf dem VPS.
Änderungen immer via Commit → git pull → bootstrap.sh (idempotent).

---

## ✅ DARF OHNE RÜCKFRAGE (Lesen & Recherche)

Claude darf folgende Aktionen **eigenständig und ohne Nachfragen** ausführen:

- Dateien lesen (lokal, im Repo, im Container)
- `docker logs`, `docker exec ... cat`, `docker exec ... sqlite3 SELECT` — nur lesend
- Web-Recherche: Dokumentationen, GitHub Issues, Changelogs, Blogs
- URLs fetchen und Inhalte analysieren
- Logs, Configs und Datenbankinhalt analysieren
- Systemzustand erfassen (`docker ps`, `df`, `free`, `which`)
- Lösungsvorschläge erarbeiten und erklären

---

## ❌ NIEMALS OHNE MEINE EXPLIZITE FREIGABE (Schreiben & Ändern)

Claude darf folgende Aktionen **nur nach ausdrücklicher Bestätigung** ausführen:

- Dateien schreiben, ändern oder löschen
- Git Commits erstellen oder pushen
- `docker exec` mit schreibenden Befehlen (apt-get install, touch, mkdir, etc.)
- `docker compose up/down/restart` oder Container-Neustarts
- bootstrap.sh ausführen
- `.env` oder Konfigurationsdateien ändern
- Irgendetwas am laufenden System verändern

**Vor jeder dieser Aktionen:** Plan zeigen, warten auf "ja" / "ok" / "mach es".

---

## 🔍 PFLICHT: Recherche vor jedem Lösungsvorschlag

Bevor Claude eine Lösung vorschlägt, gilt **zwingend**:

1. **Problem identifizieren** — aus Logs, Configs, Datenbankinhalt
2. **Recherche durchführen** — immer, ohne Ausnahme:
   - Offizielle Dokumentation des betroffenen Tools / Frameworks aufrufen
   - Relevante GitHub Issues und Changelogs durchsuchen
   - Bei OpenClaw-Problemen: https://docs.openclaw.ai zuerst
   - Weitere Quellen: Stack Overflow, Community-Foren, Release Notes
3. **Erst dann Lösung vorschlagen** — basierend auf dem was die Recherche ergeben hat, nicht auf Annahmen oder Trainingsdaten

**Begründung:** Dokumentationen und Verhalten von Tools ändern sich. Eine Lösung die auf Annahmen basiert ist wertlos oder gefährlich. Jeder Lösungsvorschlag muss mit einer Quelle belegt sein.

**Format des Lösungsvorschlags:**
```
## Befund
[Was genau falsch läuft — aus Logs/Dateien]

## Recherche
[Welche Quellen wurden konsultiert + relevante Erkenntnisse]

## Lösungsvorschlag
[Was geändert werden muss + Begründung aus der Recherche]

## Betroffene Dateien
[Welche Dateien werden verändert]

## Risiken
[Was könnte schiefgehen]
```

---

## Arbeitsweise (Reihenfolge einhalten)

1. Alle relevanten Dateien lesen, Logs prüfen, Systemzustand erfassen
2. Problem identifizieren
3. **Recherche im Internet / Dokumentation** — Pflicht vor Schritt 4
4. Befund + belegten Lösungsvorschlag präsentieren
5. Auf Freigabe warten
6. Nach Freigabe: Änderungen via Commit ins Repo — nie direkt auf dem VPS patchen

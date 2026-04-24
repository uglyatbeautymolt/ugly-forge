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

---

## Arbeitsweise (Reihenfolge einhalten)

1. Alle relevanten Dateien lesen, Logs prüfen, Systemzustand erfassen
2. Problem identifizieren
3. **Recherche im Internet / Dokumentation** — Pflicht vor Schritt 4
4. Befund + belegten Lösungsvorschlag präsentieren
5. Auf Freigabe warten
6. Nach Freigabe: Änderungen via Commit ins Repo — nie direkt auf dem VPS patchen

---

# ugly-forge

Repo: https://github.com/uglyatbeautymolt/ugly-forge
Pfad auf VPS: /home/alex/ugly-forge
Stack-Abhängigkeit: ugly-forge benötigt immer einen laufenden ugly-stack

## Abhängigkeit zu VPS_Bootstrap

ugly-forge bootstrap.sh greift direkt auf ugly-stack zu:
- Liest `ugly-stack/.env` (PROJEKT_GPG_KEY, GITHUB_TOKEN etc.)
- Schreibt Skills nach `ugly-stack/openclaw-data/skills/`
- Mergt Agenten in `ugly-stack/openclaw-data/openclaw.json`
- Kopiert `docker-compose.override.yml` nach `ugly-stack/`
- Modifiziert `ugly-stack/nginx/conf.d/` (dashboard.beautymolt.com)

## docker-compose Architektur (modular)

```
ugly-stack/
  docker-compose.yml            ← VPS_Bootstrap Repo (Basis-Stack, versioniert)
  docker-compose.override.yml   ← ugly-forge Repo (Forge-Erweiterungen, gitignored in VPS_Bootstrap)
```

- `docker-compose.yml` wird von ugly-forge **nie** angefasst
- `docker-compose.override.yml` liegt im ugly-forge Repo und wird von bootstrap.sh nach `ugly-stack/` kopiert
- Docker Compose lädt beide Dateien automatisch (kein `-f` Flag nötig) wenn man in `ugly-stack/` ist
- Bei VPS_Bootstrap Re-Run überlebt `docker-compose.override.yml` (gitignored) → forge läuft unverändert weiter
- Beim uninstall wird `docker-compose.override.yml` gelöscht → openclaw startet ohne forge-db Mount

**Inhalt override:**
- openclaw: zusätzlicher Volume-Mount `/home/alex/ugly-forge/db:/home/node/forge-db`
- forge-dashboard: neuer Service (Image, Ports, Volumes, Network)
- networks: ugly-net als external deklariert

## Uninstall

`bash uninstall.sh` — entfernt:
1. `ugly-stack/docker-compose.override.yml` (löschen)
2. nginx dashboard Block
3. Cloudflare Tunnel Eintrag
4. forge-dashboard Container + openclaw `--force-recreate` ohne forge-Mount

## Bekannte Eigenheiten

- GITHUB_TOKEN wird aus der Git Remote URL von ugly-stack gelesen (nicht aus .env)
- PROJEKT_GPG_KEY muss in ugly-stack/.env vorhanden sein
- Skills in openclaw-data/skills/ haben Stack-Priorität — forge überspringt vorhandene
- Dashboard-Rebuild nur bei Checksum-Änderung (Gate: `db/.dashboard-hash`)
- sqlite3 wird nach jedem openclaw Start geprüft und ggf. nachinstalliert

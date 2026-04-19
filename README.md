# 🦞🔨 ugly-forge

**Die KI-Softwareschmiede** — OpenClaw Multi-Agent Entwicklungsplattform

Erweiterung für [ugly-stack](https://github.com/uglyatbeautymolt/VPS_Bootstrap).

---

## Verzeichnisstruktur (wichtig!)

`ugly-forge` muss **neben** `ugly-stack` liegen, nicht darin:

```
/home/dein-user/
├── VPS_Bootstrap/     ← ugly-stack (bereits vorhanden)
└── ugly-forge/        ← hier klonen!
```

---

## Installation

```bash
# 1. Ins Home-Verzeichnis wechseln (neben ugly-stack)
cd ~

# 2. Repo klonen
git clone https://github.com/uglyatbeautymolt/ugly-forge.git
cd ugly-forge

# 3. Bootstrap ausführen (als normaler User, nicht root)
bash bootstrap.sh
```

bootstrap.sh erledigt automatisch:
- Fehlende Pakete prüfen und installieren (`sqlite3`, `curl`, `python3`) via sudo
- Skills nach `~/.openclaw/skills/` kopieren (für alle Agenten sichtbar)
- `AGENTS.md` in OC Workspace installieren (wird automatisch injiziert)
- `openclaw.json` mit 12 Agenten erstellen
- SQLite DB mit 6 Tabellen anlegen
- Volume Mount für DB in docker-compose.yml ergänzen
- OpenClaw neu starten

`docker` und `docker compose` müssen bereits installiert sein.

Nach erfolgreichem Bootstrap:
```
🦞🔨 ugly-forge Bootstrap abgeschlossen! 12 Agenten bereit.
```

---

## Voraussetzungen

- ugly-stack läuft auf dem VPS
- OpenClaw aktiv (`docker compose ps openclaw` zeigt `running`)
- `PROJEKT_GPG_KEY` in `ugly-stack/.env` eingetragen
- GitHub Token im Git Remote von ugly-stack eingebettet
- User ist in der `docker`-Gruppe: `groups | grep docker`

---

## Architektur (OC-konform)

### Wie Agenten kommunizieren
- `sessions_list` / `sessions_send` — OC-native Session-Tools
- Orchestrator startet Agenten via `openclaw agent --agent [id]`
- **Sequenziell** wegen maxSpawnDepth=2 (kein echtes Parallel-Spawning)

### Skills
Liegen in `~/.openclaw/skills/` — shared, für alle Agenten sichtbar.
Precedence: `workspace/skills/` > `~/.openclaw/skills/` > bundled

### State
1. `FORGE-INDEX.md` im Projektordner — lesbar von allen Agenten
2. SQLite via `exec: sqlite3 /home/node/forge-db/projects.db`

### Loop-Schutz
OC eingebaut (`loopDetection` in openclaw.json) + manuell in Skills.

---

## Dashboard

```bash
# Dashboard bauen und starten
bash dashboard/build.sh
```

Erreichbar unter `dashboard.beautymolt.com` nach nginx-Konfiguration.
4 Ansichten: Live Monitor, Scrum Board, Projekte, Team.

---

## Deinstallation

```bash
bash uninstall.sh
```

ugly-stack läuft unverändert weiter.

---

## Agenten

| Agent | Modell | Aufgabe |
|---|---|---|
| forge-orchestrator | Gemini Flash-Lite | Koordination, Loop-Wächter |
| forge-requirements | Gemini Flash | User Stories, ACs |
| forge-review | DeepSeek R1 | Quality Gates, Kosten |
| forge-architekt | DeepSeek R1 | System-Design, Blueprint |
| forge-webdesigner | Gemini Flash | Style Guide, UX |
| forge-db | Gemini Flash-Lite | Schema, Migrations (ZUERST!) |
| forge-backend | DeepSeek Chat | Business Logik, API |
| forge-frontend | Qwen3 Coder (free) | HTML/CSS/JS, React |
| forge-qa | DeepSeek Chat | Tests, Security Audit |
| forge-devops | Gemini Flash-Lite | Deploy, nginx, GPG |
| forge-retro | DeepSeek Chat | Analyse, Learnings |
| forge-model-scout | Gemini Flash | Modell-Recherche (Cron) |

---

## Wichtige Technische Details

| Was | Detail |
|-----|--------|
| SKILL.md descriptions | Immer in `"..."` — unquoted Colons crashen den Parser (silent drop!) |
| openclaw.json Syntax | JSON5, `model.primary` nicht `model` direkt |
| `tools.loopDetection` | Unter `agents.defaults.tools` — nicht auf Root-Level |
| SQLite Pfad (Container) | `/home/node/forge-db/projects.db` |
| Skills Pfad | `~/.openclaw/skills/` (shared), nicht im Workspace |
| AGENTS.md Pfad | `~/.openclaw/workspace/AGENTS.md` (auto-injiziert) |

---

## Lizenz

MIT

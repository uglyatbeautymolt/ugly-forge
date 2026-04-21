# ugly-forge

**Die KI-Softwareschmiede** — OpenClaw Multi-Agent Entwicklungsplattform

Erweiterung fuer [ugly-stack](https://github.com/uglyatbeautymolt/VPS_Bootstrap).

---

## Verzeichnisstruktur (wichtig!)

`ugly-forge` muss **neben** `ugly-stack` liegen:

```
/home/alex/
├── ugly-stack/    ← VPS_Bootstrap (bereits vorhanden)
└── ugly-forge/    ← hier klonen!
```

---

## Installation

**Als root ausfuehren** — das Skript wechselt intern zu alex:

```bash
su - alex -c "git clone https://github.com/uglyatbeautymolt/ugly-forge.git /home/alex/ugly-forge && bash /home/alex/ugly-forge/bootstrap.sh"
```

---

## OpenClaw-Befehle

OC laeuft im Docker-Container — Befehle muessen mit `docker exec` ausgefuehrt werden:

```bash
# Agenten auflisten
docker exec openclaw openclaw agents list

# Forge starten
docker exec -it openclaw openclaw agent --agent forge-orchestrator --message 'Hallo, neues Projekt starten'

# OC Status
docker exec openclaw openclaw status
```

---

## Dashboard

Erreichbar unter `https://dashboard.beautymolt.com` — wird automatisch von `bootstrap.sh` gebaut und gestartet.

---

## Deinstallation

```bash
bash /home/alex/ugly-forge/uninstall.sh
```

---

## Agenten

| Agent | Modell | Aufgabe |
|---|---|---|
| forge-orchestrator | Gemini Flash-Lite | Koordination, Loop-Waechter |
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

## Technische Details

| Was | Detail |
|-----|--------|
| Skills Pfad | `openclaw-data/workspace/skills/` |
| SQLite Pfad (Container) | `/home/node/forge-db/projects.db` |
| SKILL.md descriptions | Immer in `"..."` — unquoted Colons crashen den Parser |
| openclaw.json Syntax | Reines JSON |

---

## Lizenz

MIT

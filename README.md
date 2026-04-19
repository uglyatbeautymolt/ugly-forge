# ugly-forge

**Die KI-Softwareschmiede** — OpenClaw Multi-Agent Entwicklungsplattform

Erweiterung fuer [ugly-stack](https://github.com/uglyatbeautymolt/VPS_Bootstrap).

---

## Verzeichnisstruktur (wichtig!)

`ugly-forge` muss **neben** `ugly-stack` liegen:

```
/home/dein-user/
├── VPS_Bootstrap/     ← ugly-stack (bereits vorhanden)
└── ugly-forge/        ← hier klonen!
```

---

## Installation

```bash
# 1. Ins Home-Verzeichnis (neben ugly-stack)
cd ~

# 2. Repo klonen
git clone https://github.com/uglyatbeautymolt/ugly-forge.git
cd ugly-forge

# 3. Bootstrap ausfuehren (als normaler User, nicht root)
bash bootstrap.sh
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

Oder direkt in den Container wechseln:

```bash
docker exec -it openclaw bash
# Dann: openclaw agents list
```

---

## Dashboard

```bash
bash dashboard/build.sh
```

Erreichbar unter `https://dashboard.beautymolt.com` nach nginx-Konfiguration:

```bash
sudo cp dashboard/nginx.conf /etc/nginx/conf.d/forge-dashboard.conf
sudo nginx -t && sudo nginx -s reload
```

---

## Deinstallation

```bash
bash uninstall.sh
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
| OC-Befehle | `docker exec openclaw openclaw ...` |
| SKILL.md descriptions | Immer in `"..."` — unquoted Colons crashen den Parser |
| openclaw.json Syntax | Reines JSON, `model.primary` |
| `tools.loopDetection` | Unter `agents.defaults.tools` |
| SQLite Pfad (Container) | `/home/node/forge-db/projects.db` |
| Skills Pfad | `~/.openclaw/skills/` (shared) |

---

## Lizenz

MIT

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

bootstrap.sh:
- Prüft und installiert fehlende Pakete (`sqlite3`, `curl`, `python3`) via sudo
- Erwartet `docker` und `docker compose` als vorhanden
- Sucht ugly-stack automatisch in `../VPS_Bootstrap` oder `../ugly-stack`

Nach erfolgreichem Bootstrap:
```
🦞🔨 ugly-forge aktiv! 12 Agenten bereit.
```

---

## Voraussetzungen

- ugly-stack läuft auf dem VPS
- OpenClaw aktiv (`docker compose ps openclaw` zeigt `running`)
- `PROJEKT_GPG_KEY` in `ugly-stack/.env` eingetragen
- GitHub Token im Git Remote von ugly-stack eingebettet
- User ist in der `docker`-Gruppe: `groups | grep docker`

---

## Dashboard

```bash
# Dashboard bauen und starten
bash dashboard/build.sh
```

Erreichbar unter `dashboard.beautymolt.com` nach nginx-Konfiguration.

---

## Deinstallation

```bash
bash uninstall.sh
```

ugle-stack läuft unverändert weiter.

---

## Agenten

| Agent | Modell | Aufgabe |
|---|---|---|
| Orchestrator | Gemini Flash-Lite | Koordination, Loop-Wächter |
| Requirements | Gemini Flash | User Stories, ACs |
| Review | DeepSeek R1 | Quality Gates, Kosten |
| Architekt | DeepSeek R1 | System-Design, Blueprint |
| Webdesigner | Gemini Flash | Style Guide, UX |
| DB | Gemini Flash-Lite | Schema, Migrations |
| Backend | DeepSeek Chat | Business Logik, API |
| Frontend | Qwen3 Coder (free) | HTML/CSS/JS, React |
| QA | DeepSeek Chat | Tests, Security Audit |
| DevOps | Gemini Flash-Lite | Deploy, nginx, GPG |
| Retro | DeepSeek Chat | Analyse, Learnings |
| Model-Scout | Gemini Flash | Modell-Recherche |

---

## Lizenz

MIT

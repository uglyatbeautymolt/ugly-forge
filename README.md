# 🦞🔨 ugly-forge

**Die KI-Softwareschmiede** — OpenClaw Multi-Agent Entwicklungsplattform

Erweiterung für [ugly-stack](https://github.com/uglyatbeautymolt/VPS_Bootstrap). Eine bewusste Entscheidung.

---

## Was ist ugly-forge?

ugly-forge verwandelt OpenClaw in eine vollständige KI-gesteuerte Softwareschmiede. Per Text oder Sprache können komplette Webseiten und Applikationen entwickelt werden — automatisiert durch 12 spezialisierte Agenten.

```
ugly-stack/    ← tägliches Werkzeug — läuft immer
ugly-forge/    ← Softwareschmiede — bewusst aktiviert
```

---

## Voraussetzungen

- ugly-stack läuft auf dem VPS
- OpenClaw aktiv und mit Telegram verbunden
- GitHub Token mit Repo-Rechten
- GPG Key in Bitwarden (BACKUP_GPG_PASSWORD)

---

## Installation

```bash
# 1. Repo klonen
git clone https://github.com/uglyatbeautymolt/ugly-forge.git
cd ugly-forge

# 2. .env vorbereiten
cp .env.example .env.forge
# Fehlende Keys eintragen (GITHUB_TOKEN, GITHUB_USERNAME, PROJEKT_GPG_KEY)

# 3. Schmiede aktivieren — bewusste Entscheidung!
./bootstrap.sh
```

Nach erfolgreichem Bootstrap erhältst du eine Telegram-Nachricht:
```
🦞🔨 ugly-forge aktiv!
12 Agenten bereit — sage mir was wir bauen sollen.
```

---

## Deinstallation

```bash
./uninstall.sh
```

ugly-stack läuft unverändert weiter.

---

## Agenten

| Agent | Modell | Aufgabe |
|---|---|---|
| Requirements | Gemini 3 Flash | User Stories, Akzeptanzkriterien |
| Review | DeepSeek V4 | Quality Gates, Kostenschätzung |
| Architekt | DeepSeek V4 | System-Design, Blueprint |
| Webdesigner | Gemini 3 Flash | Layout, Style Guide, UX |
| Orchestrator | Gemini 2.5 Flash-Lite | Koordination, Loop-Wächter |
| Frontend | Qwen3 Coder 480B | HTML/CSS/JS |
| Backend | DeepSeek V3.2 | Business Logik, API |
| DB | Gemini 2.5 Flash-Lite | Datenmodell, Migrations |
| QA | DeepSeek V3.2 | Unit, Integration, E2E Tests |
| DevOps | Gemini 2.5 Flash-Lite | Deploy, nginx, Release |
| Retro | DeepSeek V3.2 | Analyse, SKILL.md Updates |
| Model-Scout | Gemini 3 Flash | Markt-Recherche, Model-Updates |

---

## Lizenz

MIT

# 🦞🔨 ugly-forge — Die KI-Softwareschmiede
**Powered by OpenClaw | Erweiterung für ugly-stack**
Konzept & Design Dokument | v7.0 | April 2026

---

## Changelog

| Version | Datum | Änderungen |
| --- | --- | --- |
| v1.0 | April 2026 | Initiale Architektur — 12 Agenten, Pipeline, Kostenschätzung |
| v2.0 | April 2026 | Model-Scout, Qualitäts-Tracking, Beobachtungsfenster 1/3/6/9 Tage |
| v3.0 | April 2026 | GitHub-Integration, Branch-Strategie, GPG Secrets, Pre-Commit Hook |
| v4.0 | April 2026 | Dashboard komplett: Team, Projekte, Live Monitor, File Browser |
| v5.0 | April 2026 | Loop-Schutz: Erkennung, Eskalations-Stufen, Projekt-Verhalten |
| v6.0 | April 2026 | Implementierungs-Architektur: JS Libraries, Prompt-Trennung, Bootstrap |
| v7.0 | April 2026 | ugly-forge: eigenständiges Repo, Trennung von ugly-stack, Installations-Flow |

---

## 1. Konzept — Zwei getrennte Welten

> **Philosophie:** ugly-forge ist eine bewusste Entscheidung. Es erweitert ugly-stack um die Softwareschmiede — aber niemals automatisch. Du entscheidest wann du sie aktivierst.

|  | **ugly-stack** | **ugly-forge** |
| --- | --- | --- |
| Was | Tägliches Werkzeug — stabil, verlässlich | Softwareschmiede — KI entwickelt Software |
| Status | Läuft immer | Bewusst aktiviert |
| Änderungen | Keine durch ugly-forge | Eigenständig |
| GitHub Repo | beautymolt/ugly-stack | beautymolt/ugly-forge |
| Bootstrap | Eigener | Eigener — setzt ugly-stack voraus |
| OC Rolle | Service — Assistent | Plattform — Softwareschmiede |

---

## 2. ugly-stack — Bestehender Stack

ugly-stack bleibt vollständig unverändert. Die einzige Berührungsstelle ist ein Volume Mount den bootstrap.sh einmalig hinzufügt.

| Container | Zweck | Relevant für ugly-forge |
| --- | --- | --- |
| nginx | Webserver — serviert ./www | ✅ Serviert generierte Webseiten |
| openclaw | KI-Agent Gateway | ✅ Kern — führt Skills aus |
| searxng | Web-Suche | ✅ Model-Scout nutzt SearXNG |
| n8n | Automation | ✅ Escape-Hatch für Shell Tasks |
| whisper | Speech-to-Text | ✅ Spracheingabe für Projekte |
| tts | Text-to-Speech | ✅ Sprachausgabe |
| cloudflared | Tunnel zu Domain | — Infrastruktur |
| watchtower | Auto-Updates | ⚠️ Skills-Volume bleibt erhalten |
| portainer | Container Management | — Infrastruktur |

---

## 3. ugly-forge — Struktur

### 3.1 Verzeichnisstruktur

| Pfad | Inhalt | Wer verwaltet |
| --- | --- | --- |
| ugly-forge/ | Root — eigenständiges GitHub Repo | Git |
| ugly-forge/README.md | Installations-Anleitung, Voraussetzungen | Docs |
| ugly-forge/bootstrap.sh | Einmalige Installation — aktiviert Schmiede | Claude CLI |
| ugly-forge/uninstall.sh | Saubere Deinstallation ohne ugly-stack zu beschädigen | Claude CLI |
| ugly-forge/docker-compose.yml | Nur forge-spezifische Services (Dashboard) | Claude CLI |
| ugly-forge/.env.example | Welche Keys nötig sind — keine Werte | Git |
| ugly-forge/workspace/ | OC Workspace — gemountet in OC Container | OC |
| ugly-forge/workspace/skills/ | Alle Agenten-Skills (SKILL.md + JS) | OC |
| ugly-forge/workspace/models/ | models.json pro Agent | OC |
| ugly-forge/db/projects.db | SQLite — Projekthistory, Tasks, Logs | OC + Claude CLI |
| ugly-forge/dashboard/ | Web-Interface Source Code | OC + Claude CLI |
| ugly-forge/bootstrap/ | Bootstrap & Restore Scripts | Claude CLI |

### 3.2 Verbindung zu ugly-stack

> **Einzige Änderung:** `ugly-stack/docker-compose.yml` → `openclaw volumes: + ../ugly-forge/workspace:/home/node/forge` — eine Zeile, minimal invasiv, jederzeit rückgängig machbar.

| Volume | Von | Nach | Zweck |
| --- | --- | --- | --- |
| ./www | /home/node/www | /var/www/html (nginx) | OC schreibt HTML → nginx serviert |
| ./openclaw-data | /home/node/.openclaw | — | OC eigene Daten (unverändert) |
| ../ugly-forge/workspace | /home/node/forge | — | NEU: Skills & Workspace der Schmiede |

---

## 4. Installations-Flow

> **Voraussetzung:** ugly-stack läuft bereits und OC ist aktiv. Du hast Zugriff auf Telegram und das OC Dashboard.

### 4.1 Schritt-für-Schritt

| Schritt | Wer | Aktion | Was passiert |
| --- | --- | --- | --- |
| 1 | Du | git clone ugly-forge | Dateien auf VPS — noch nichts aktiv |
| 2 | Du | ./bootstrap.sh ausführen | Bewusste Entscheidung: Schmiede aktivieren |
| 3 | bootstrap.sh | Prüft ugly-stack | Läuft OC? Ist Telegram aktiv? |
| 4 | bootstrap.sh | .env ergänzen | GITHUB_TOKEN, GITHUB_USERNAME, PROJEKT_GPG_KEY |
| 5 | bootstrap.sh | SQLite Schema erstellen | projects.db mit allen Tabellen anlegen |
| 6 | bootstrap.sh | Volume Mount hinzufügen | Eine Zeile in ugly-stack/docker-compose.yml |
| 7 | bootstrap.sh | OC neu starten | docker compose restart openclaw |
| 8 | bootstrap.sh | Ersten OC-Prompt senden | Via Telegram API: Skills initialisieren |
| 9 | OC | Skills laden | workspace/skills/ lesen, Agenten registrieren |
| 10 | OC | Selbst-Check | models.json, SQLite, GitHub API, GPG testen |
| 11 | OC | Telegram Bestätigung | Softwareschmiede bereit — 12 Agenten aktiv |

### 4.2 Telegram Bestätigung

```
🦞🔨 ugly-forge aktiv!
Agenten: 12 ✅  Modelle: ✅  SQLite: ✅  GitHub API: ✅  GPG: ✅
Bereit für erstes Projekt — sage mir was wir bauen sollen.
```

### 4.3 Deinstallation

| Schritt | Was passiert |
| --- | --- |
| ./uninstall.sh | Volume Mount aus docker-compose.yml entfernen |
| | OC neu starten — nur noch ugly-stack Skills |
| | .env Keys entfernen (optional) |
| | projects.db archivieren nach R2 (optional) |
| | OC Telegram Bestätigung: Schmiede deaktiviert |

---

## 5. Neuer VPS — Zwei Szenarien

### Szenario A — Nur ugly-stack

```
1. Bootstrap ugly-stack  →  Tägliches Werkzeug läuft
2. Fertig                →  OC als Assistent aktiv — keine Schmiede
```

### Szenario B — ugly-stack + ugly-forge

```
1. Bootstrap ugly-stack  →  Tägliches Werkzeug läuft
2. Bewusste Entscheidung →  Ich will die Softwareschmiede
3. git clone ugly-forge  →  Repo auf VPS
4. ./bootstrap.sh        →  Schmiede aktivieren
5. Telegram Bestätigung  →  Bereit! 🦞🔨
```

> **Prinzip:** ugly-forge setzt ugly-stack voraus — aber nicht umgekehrt. Jederzeit aktivierbar und deaktivierbar.

---

## 6. Prompt-Trennung — OC vs Claude CLI

| Typ | Symbol | Wo eingeben | Zweck |
| --- | --- | --- | --- |
| OC-Prompt | 🤖 | OC Dashboard (Browser) | Agenten, Skills, Konfiguration |
| Claude CLI-Prompt | 💻 | Terminal auf VPS | Infrastruktur, Bootstrap, System, Backup |

> **Regel:** OC konfiguriert sich selbst — niemals manuell Skills editieren. Claude CLI verantwortet alles außerhalb von OC.

---

## 7. JavaScript Libraries

> **Strategie:** Kein Binary nötig — alles pure JavaScript. Watchtower-sicher weil Libraries in workspace/skills/ (Volume) liegen.

| Library | Package | Zweck | Idempotenz | Watchtower-sicher |
| --- | --- | --- | --- | --- |
| openpgp.js | openpgp | GPG Verschlüsselung — AES-256 kompatibel mit gpg Binary | ✅ Ja | ✅ Ja |
| Octokit | @octokit/rest | GitHub API — Repos, Commits, Branches | ✅ check-before-act | ✅ Ja |
| SQLite | better-sqlite3 | Direkt auf projects.db — kein Server | ✅ IF NOT EXISTS + UPSERT | ✅ Ja |

> **GPG Kompatibilität:** openpgp.js (AES-256) ↔ gpg Binary (AES-256) — 100% kompatibel. JS verschlüsselt, gpg Binary entschlüsselt und umgekehrt.

---

## 8. Agenten-Architektur

| Agent | Modell | Phase | Verantwortung |
| --- | --- | --- | --- |
| Requirements | Gemini 3 Flash | 1 | User Stories, Akzeptanzkriterien |
| Review | DeepSeek V4 | 1+2 | Quality Gates, Kostenschätzung, Freigabe |
| Architekt | DeepSeek V4 | 2 | System-Design, Blueprint, Mermaid |
| Webdesigner | Gemini 3 Flash | 2 | Layout, Style Guide, UX |
| Orchestrator | Gemini 2.5 Flash-Lite | Durchgehend | Koordination, Model-Router, Loop-Wächter |
| Frontend | Qwen3 Coder 480B | 3 parallel | HTML/CSS/JS, GitHub API |
| Backend | DeepSeek V3.2 | 3 parallel | Business Logik, API, GitHub API |
| DB | Gemini 2.5 Flash-Lite | 3 parallel | Datenmodell, Migrations |
| QA | DeepSeek V3.2 | 3+4 | Unit-, Integrations-, E2E-Tests |
| DevOps | Gemini 2.5 Flash-Lite | 4 | Deploy, nginx, openpgp.js, Release Tag |
| Retro | DeepSeek V3.2 | Nach Abschluss | Top-3 Analyse, SKILL.md Update |
| Model-Scout | Gemini 3 Flash | 2x / Woche | Markt-Recherche, Model-Updates, Selbst-Scout |

```
ASCII Pipeline:
[Requirements] → [Review Gate 1] → [Repo Init]
      ↓
[Architektur] → [Review Gate 2]
      ↓
[Frontend] ─┐
[Backend]  ─┼─ PARALLEL → [Integration] → [Deployment] → [Retro]
[DB]       ─┘
```

---

## 9. Entwicklungs-Pipeline

| Phase | Modus | Output |
| --- | --- | --- |
| 1 — Requirements | Sequenziell | User Stories, Akzeptanzkriterien |
| 1 — Review Gate 1 | Sequenziell | Freigabe + Kostenschätzung (Token + $) |
| 1 — Repo Init | Sequenziell | GitHub Repo, Branches, Pre-Commit Hook via Octokit |
| 2 — Architektur | Sequenziell | Blueprint + Style Guide + Mermaid-Diagramm |
| 2 — Review Gate 2 | Sequenziell | Freigabe + angepasste Schätzung |
| 3 — Entwicklung | **PARALLEL** | Code + Tests + Commits via GitHub API |
| 4 — Integration | Sequenziell | Getestetes Gesamtsystem |
| 5 — Deployment | Sequenziell | Release Tag, .env.gpg via openpgp.js |
| 6 — Retro | Sequenziell | SKILL.md Updates (max. 3) + Commit |

---

## 10. Loop-Schutz & Eskalation

| Mechanismus | Regel | Aktion |
| --- | --- | --- |
| Max Tiefe | Max. 3 Ebenen pro Fragen-Chain | Orchestrator entscheidet selbst |
| Fragen-History | Gleiche Frage bereits gestellt | Sofortiger STOP |
| Timeout | Frage offen > 5 Minuten | Eskalation an Orchestrator |

| Stufe | Trigger | Projekt-Status |
| --- | --- | --- |
| 1 — Orchestrator | Hat Kontext | Läuft normal |
| 2 — Blockiert | Kein Kontext | Nur betroffene Tasks blockiert — Rest läuft |
| 3 — Du | Kein Ausweg | Pausiert — Telegram Notification + 3 Optionen |

> **Option C bei Stufe 3:** Loop = Blueprint-Problem. Architekt Agent für Mini-Review aktivieren — ohne Projekt-Neustart.

---

## 11. Secrets-Management

| Stufe | Was | Wie |
| --- | --- | --- |
| Bitwarden | VPS_GPG_KEY (= BACKUP_GPG_PASSWORD) | Einziger manueller Einstiegspunkt |
| GitHub (global) | ~/.env.gpg | Verschlüsselt mit VPS_GPG_KEY |
| VPS | /home/alex/ugly-stack/.env | Entschlüsselt zur Laufzeit |
| GitHub (pro Projekt) | .env.gpg | Verschlüsselt mit PROJEKT_GPG_KEY — AES-256 |
| Projekt lokal | .env | Entschlüsselt zur Laufzeit — nur projektrelevante Keys |

---

## 12. Dashboard-Architektur

> **Zwei Welten:** Team = Stammdaten (Konfiguration, Skills, Lernhistory). Projekte = Bewegungsdaten (Tasks, Kosten, Live Monitor). Niemals vermischt.

### 12.1 Team-Bereich — Stammdaten

- Layout: Sidebar links (Agenten) + Detail rechts
- Pro Agent: Konfiguration, SKILL.md, Lern-History Timeline
- Lern-History: Datum, Projekt, Problem, Lösung, Effekt, Status (⏳/✅/⚠️/❌)
- Kein Live-Status — gehört in Projekt-Ansicht

### 12.2 Projekt-Bereich — Bewegungsdaten

- Sidebar: Projekte chronologisch, Status-Badge: Planning/InProgress/Done
- Tab 1 — Scrum Board: 5 Lanes + BLOCKED für Loop-blockierte Tasks
- Task-Karte: $geschätzt (links oben), $real (rechts oben), Titel, Agent, Iterationen
- Tab 2 — Projekt-Info: Requirements, Blueprint (Mermaid), Style Guide, File Browser

### 12.3 Live Monitor

| Linienzustand | Farbe | Dauer |
| --- | --- | --- |
| Ruhend | Grau dünn | Permanent |
| Beauftragung aktiv | Blau → Pfeil | Bis Task erledigt |
| Frage aktiv | Orange gestrichelt → Pfeil | Bis Antwort |
| Erledigt / Antwort | Grün ← Pfeil | 10 Sekunden dann neutral |
| Fehler | Rot → Pfeil | Bis gelöst |
| Loop erkannt | Rot pulsierend gestrichelt | Bis Eskalation gelöst |

- Zwei Balken pro Agent: Token % (blau → rot über 100%) + Tasks x/y (grün)
- Gesamtbalken: Tasks + Budget — beide werden rot bei 100%
- Kommunikations-Matrix: Von → Nach, Aufträge (blau), Fragen (orange)

---

## 13. Backup & Bootstrap

### 13.1 Was wird gesichert

| Was | Wo | Rhythmus |
| --- | --- | --- |
| .env.gpg (verschlüsselt) | Cloudflare R2 | Bei jeder Änderung |
| projects.db | Cloudflare R2 | Täglich verschlüsselt |
| workspace/skills/ | Cloudflare R2 | Täglich tar.gz verschlüsselt |
| docker-compose.yml (beide) | Cloudflare R2 | Bei jeder Änderung |
| nginx Konfiguration | Cloudflare R2 | Bei jeder Änderung |

### 13.2 Bootstrap ugly-stack + ugly-forge

| Schritt | Wer | Was |
| --- | --- | --- |
| 1. VPS_GPG_KEY | Du | Aus Bitwarden holen |
| 2. ugly-stack Bootstrap | Claude CLI | R2 → .env.gpg decrypt → docker compose up |
| 3. ugly-stack läuft | Automatisch | OC, nginx, alle Services aktiv |
| 4. Entscheidung | Du | Schmiede aktivieren? Ja/Nein |
| 5. ugly-forge klonen | Du | git clone ugly-forge |
| 6. Bootstrap forge | Claude CLI | ./bootstrap.sh — Skills, DB, Volume Mount |
| 7. OC Bestätigung | OC via Telegram | Softwareschmiede bereit! 🦞🔨 |

> **Einziger manueller Schritt:** VPS_GPG_KEY aus Bitwarden holen — alles andere läuft automatisch. Beide Bootstrap-Scripts sind vollständig idempotent.

---

## 14. Modell-Referenz (OpenRouter, April 2026)

| Tier | Modell | Provider | Input/1M | Output/1M | Einsatz |
| --- | --- | --- | --- | --- | --- |
| Free | Qwen3 Coder 480B | Alibaba | $0.00 | $0.00 | Frontend — 1 Tag Fenster |
| Budget | Gemini 2.5 Flash-Lite | Google | $0.10 | $0.40 | Orchestrator, DB, DevOps — 3 Tage |
| Standard | DeepSeek V3.2 | DeepSeek | $0.26 | $0.38 | Backend, QA, Retro — 6 Tage |
| Standard | Gemini 3 Flash | Google | $0.30 | $1.50 | Requirements, Webdesigner, Scout — 6 Tage |
| Premium | DeepSeek V4 | DeepSeek | $0.30 | $0.50 | Architekt, Review Gates — 9 Tage |

---

*Erarbeitet im Dialog — OpenClaw / ugly-forge Architektur Session, April 2026 | v7.0 | Finales Konzept-Dokument*

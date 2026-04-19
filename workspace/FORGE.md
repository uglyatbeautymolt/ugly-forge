# ugly-forge — Workspace

Dieser Workspace definiert die KI-Softwareschmiede.

## Agenten-Übersicht

| Agent | Skill | Modell | Phase |
|-------|-------|--------|-------|
| Orchestrator | forge_orchestrator | Gemini 2.5 Flash-Lite | Durchgehend |
| Requirements | forge_requirements | Gemini 3 Flash | 1 |
| Review | forge_review | DeepSeek V4 | 1+2 |
| Architekt | forge_architekt | DeepSeek V4 | 2 |
| Webdesigner | forge_webdesigner | Gemini 3 Flash | 2 |
| Frontend | forge_frontend | Qwen3 Coder 480B | 3 parallel |
| Backend | forge_backend | DeepSeek V3.2 | 3 parallel |
| DB | forge_db | Gemini 2.5 Flash-Lite | 3 parallel |
| QA | forge_qa | DeepSeek V3.2 | 3+4 |
| DevOps | forge_devops | Gemini 2.5 Flash-Lite | 4 |
| Retro | forge_retro | DeepSeek V3.2 | Nach Abschluss |
| Model-Scout | forge_model_scout | Gemini 3 Flash | 2x/Woche |

## Pipeline

```
1. Requirements → Review Gate 1 → Repo Init
2. Architekt + Webdesigner → Review Gate 2
3. PARALLEL: Frontend + Backend + DB + QA (Unit Tests)
4. QA (Integration + E2E)
5. DevOps (Deploy + Release)
6. Retro
```

## Wichtige Pfade
- Skills: `/home/node/forge/skills/`
- Datenbank: `/home/node/forge/db/projects.db`
- Webseiten: `/home/node/www/` (nginx serviert sofort)
- GitHub: `https://github.com/uglyatbeautymolt/`

## Loop-Schutz
- Max Fragen-Tiefe: 3
- Timeout: 5 Minuten
- Bei Loop: Orchestrator → Nutzer via Telegram

## Model-Tiers
- Free (1 Tag Fenster): Qwen3 Coder 480B
- Budget (3 Tage): Gemini 2.5 Flash-Lite
- Standard (6 Tage): DeepSeek V3.2, Gemini 3 Flash
- Premium (9 Tage): DeepSeek V4

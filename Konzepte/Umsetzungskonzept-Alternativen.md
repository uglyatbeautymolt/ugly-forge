# ugly-forge — Umsetzungskonzept: Alternativen zu OpenClaw

**Version 1.0 | April 2026**

Dieses Dokument untersucht, wie die im Fachkonzept beschriebene KI-Softwareschmiede ohne OpenClaw als Agent-Runtime umgesetzt werden könnte. Drei Varianten werden ausführlich beschrieben, begründet und gegeneinander gewichtet.

---

## Ausgangspunkt: Was OpenClaw heute leistet

Bevor Alternativen bewertet werden können, müssen die funktionalen Anforderungen an die Agent-Runtime klar sein. OpenClaw übernimmt heute:

1. **Agent-Isolation** — jeder Agent hat eigenen Kontext, eigenen Workspace, eigene Modellkonfiguration
2. **Tool-Ausführung** — `exec` erlaubt Shell-Befehle aus dem LLM-Kontext heraus
3. **Inter-Agent-Kommunikation** — `sessions_send`, `sessions_list` für synchrone und asynchrone Nachrichten
4. **Skill-System** — wiederverwendbare Instruktionsdateien (SKILL.md), die als Prompt-Basis dienen
5. **Modell-Routing** — verschiedene LLMs pro Agent, Fallback-Modelle
6. **Loop Detection** — automatische Erkennung von Endlosschleifen
7. **Kanal-Integration** — Telegram als nativer Eingangskanal
8. **State Management** — Sessions bleiben erhalten, Kontext akkumuliert sich

### Bekannte Einschränkungen aus dem Betrieb (April 2026)

Diese Punkte sind bei der Bewertung der Alternativen zu berücksichtigen — sie stellen reale Schwächen des OpenClaw-Ansatzes dar, die jede Alternative von Haus aus besser lösen sollte:

**skillsSnapshot-Problem:** OpenClaw cached Skill-Inhalte beim ersten Session-Start in `sessions.json`. Änderungen an SKILL.md oder AGENTS.md wirken erst nach manuellem Session-Reset — ein erhebliches Betriebsrisiko bei Korrekturen unter laufendem Betrieb.

**Keine erzwungene Registrierungsreihenfolge:** Das Skill-System gibt Agenten Instruktionen, erzwingt aber keine Ausführungsreihenfolge. Der Orchestrator hat in der Praxis die Projekt-Registrierung in der Datenhaltung ausgelassen — was zu vollständiger Dashboard-Unsichtbarkeit führte. Ein kodiertes Orchestrations-System (LangGraph, eigenes SDK) würde diesen Schritt strukturell erzwingen, nicht nur durch Instruktionstext.

**maxSpawnDepth = 2:** Echte Parallelisierung ist nicht möglich. Die Pipeline ist strukturell sequenziell.

Jede Alternative muss diese Anforderungen erfüllen oder begründen, warum ein Teilbereich wegfällt oder anders gelöst wird.

---

## Variante A — LangGraph + Python Orchestration

### Konzept

LangGraph (Erweiterung von LangChain) erlaubt die Definition von KI-Workflows als gerichtete Graphen. Jeder Knoten im Graph entspricht einem Agenten oder einer Verarbeitungsstufe. Kanten verbinden Knoten und können bedingt sein (z.B. "weiter nur wenn Gate approved").

Die Pipeline wird als Python-Programm definiert. Jeder Agent ist eine Funktion, die einen LLM-Aufruf mit strukturiertem Prompt, Tool-Use und State-Übergabe kapselt. Der Orchestrator-Knoten steuert den Fluss.

```python
# Vereinfachtes Schema
from langgraph.graph import StateGraph

builder = StateGraph(ForgeState)
builder.add_node("requirements", requirements_agent)
builder.add_node("review_gate_1", review_gate)
builder.add_node("architekt", architekt_agent)
# ...

builder.add_conditional_edges("review_gate_1", check_approval,
    {"approved": "architekt", "rejected": END})

graph = builder.compile()
graph.invoke({"project_name": "MyApp"})
```

### Architektur auf dem VPS

- Python-Service in eigenem Docker-Container (`forge-orchestrator`)
- Jeder LLM-Call via OpenRouter API (HTTP, kein Binary nötig)
- Tool-Ausführung: Python subprocess für Shell-Commands, requests für HTTP-Calls
- State: PostgreSQL (bereits vorhanden als forge-postgres) für persistenten Pipeline-State
- Telegram-Integration via python-telegram-bot
- Kein Skill-System mehr — Prompts sind Python-Strings oder Jinja2-Templates in Dateien

### Stärken

**Maximale Kontrolle über den Ablauf.** Der Graph ist explizit codiert — jede Verzweigung, jede Bedingung, jedes Retry-Verhalten ist in Python definiert und testbar. Es gibt keine "Black Box" hinter einem proprietären Tool.

**Produktionsreife Toolchain.** LangGraph/LangChain ist in vielen produktiven KI-Systemen im Einsatz, gut dokumentiert, aktiv entwickelt. Fehler und Edge Cases sind bekannt und adressiert.

**Vollständige Testbarkeit.** Unit-Tests für jeden Agenten-Knoten. Integration-Tests für den Gesamtfluss. Mock-LLMs für deterministische Tests — in OpenClaw nicht möglich.

**Skalierbarkeit.** LangGraph unterstützt nativ parallele Knoten (z.B. Backend + Frontend + DB gleichzeitig) — die maxSpawnDepth-Limitierung von OpenClaw entfällt.

**Persistenz und Resume.** LangGraph hat eingebautes Checkpointing (LangGraph Cloud oder selbst mit PostgreSQL). Eine unterbrochene Pipeline kann an der letzten Position fortgesetzt werden.

### Schwächen

**Erheblicher Implementierungsaufwand.** Alle Prompts, Tool-Integrationen, State-Schemata und Routing-Logiken müssen neu in Python geschrieben werden. Kein "Prompt-File bearbeiten und fertig" wie bei SKILL.md.

**Python-Dependency-Management.** LangChain und seine Abhängigkeiten sind bekannt für Breaking Changes zwischen Versionen. Dependency Pinning und regelmäßige Updates sind nötig.

**Kein nativer Kontext-Akkumulator.** OpenClaw akkumuliert Kontext über eine ganze Session. In LangGraph muss der State (welcher Kontext an welchen Agenten übergeben wird) explizit definiert werden — mehr Planungsaufwand.

### Aufwand

Initial: hoch (3–4 Wochen für vollständige Migration). Betrieb: mittel. Anpassungen von Agenten-Verhalten: mittel (Python statt Markdown).

---

## Variante B — n8n als Workflow-Engine mit direkten LLM-Nodes

### Konzept

n8n läuft bereits im ugly-stack. n8n hat native LLM-Nodes (AI Agent Node, OpenAI Node, etc.) und kann komplexe Workflows mit Branches, Loops und externen Tool-Calls abbilden. Die gesamte Pipeline wird als n8n Workflow definiert.

Jeder Schmiede-Agent wird zu einem n8n Sub-Workflow. Der Haupt-Workflow ist die Pipeline-Steuerung mit den Review Gates als Wait-Nodes (Webhook oder manueller Trigger).

```
Trigger (Telegram / Webhook)
  → Sub-Workflow: Requirements Agent (AI Agent Node)
  → Gate 1: Wait-Node (Webhook warten auf Nutzer-Bestätigung per Telegram)
  → Sub-Workflow: Architekt Agent
  → Gate 2: Wait-Node
  → Sub-Workflow: DB Agent
  → Sub-Workflow: Backend Agent
  → Sub-Workflow: Frontend Agent
  → Sub-Workflow: QA Agent
  → Sub-Workflow: DevOps Agent
  → Telegram: Abschluss-Notification
```

Tool-Calls aus dem LLM heraus: n8n AI Agent Nodes unterstützen Tool-Use nativ. Tools werden als n8n Nodes definiert (HTTP Request Node für forge-db-api, Code Node für Shell-Execution via n8n's exec, etc.).

### Architektur auf dem VPS

- n8n bereits vorhanden — kein neuer Service nötig
- Workflows werden als JSON exportiert und im Repository versioniert
- Shell-Commands: Code Node mit `child_process.exec` (n8n läuft Node.js)
- Telegram: n8n Telegram Node (bereits konfiguriert)
- State: n8n Execution History + forge-postgres via HTTP-Request Node

### Stärken

**Kein neuer Container nötig.** n8n läuft bereits. Die Infrastruktur bleibt unverändert — das ist der größte operative Vorteil.

**Visueller Workflow-Editor.** Die Pipeline ist als Diagramm sichtbar und editierbar — kein Code notwendig für einfache Anpassungen. Für nicht-technische Nutzer zugänglich.

**Eingebaute Telegram-Integration.** n8n hat einen nativen Telegram Trigger Node und Send-Message Node. Die bestehende Telegram-Konfiguration kann wiederverwendet werden.

**Versionierung über Export.** n8n Workflows können als JSON exportiert und im Git-Repository versioniert werden — gleiche Philosophie wie das aktuelle Commit-First-Prinzip.

**Retry- und Error-Handling eingebaut.** n8n hat konfigurierbare Retry-Policies und Error-Workflows auf Node-Ebene.

### Schwächen

**LLM-Kontext-Management ist manuell.** n8n AI Agent Nodes halten keinen langen Gesprächskontext über Sub-Workflow-Grenzen hinaus. Der State (requirements.md, blueprint.md, etc.) muss explizit als Daten zwischen Sub-Workflows übergeben werden — als JSON-Strings in Feldern, nicht als Dateien.

**Datei-basierter Workflow ist fremd für n8n.** ugly-forge arbeitet mit Dateien im Workspace (FORGE-INDEX.md, requirements.md, blueprint.md). n8n arbeitet mit Datensätzen (Items). Die Datei-Metapher auf n8n-Items zu mappen ist unnatürlich und fehleranfällig.

**Skalierungsgrenzen bei langen Kontexten.** AI Agent Nodes in n8n schicken bei jedem Tool-Call den gesamten bisherigen Kontext mit. Bei langen Entwicklungsprozessen (viele Files, viele Tool-Calls) kann das Kontext-Limit des LLMs erreicht werden ohne dass n8n eine clevere Lösung dafür hat.

**Workflow-Komplexität wird schnell unübersichtlich.** Die Schmiede hat 12 Agenten mit komplexen Abhängigkeiten. In n8n sieht ein Workflow mit 80+ Nodes oft aus wie Spaghetti — selbst mit Sub-Workflows.

**n8n ist kein Code-Execution-System.** Shell-Ausführung via Code Node ist möglich aber nicht das natürliche Verwendungsmuster. Fehler-Handling für Shell-Commands muss manuell codiert werden.

### Aufwand

Initial: mittel (2–3 Wochen). Kein neuer Service, aber Kontext-Management und Datei-Handling erfordern kreative Lösungen. Betrieb: niedrig. Anpassungen: niedrig bis mittel (Editor vs. JSON direkt).

---

## Variante C — Claude Code als Agent-Runtime (Anthropic SDK)

### Konzept

Anthropic bietet mit dem Claude Code SDK die Möglichkeit, autonome Coding-Agenten zu bauen, die vollständige Tool-Use-Fähigkeiten haben (Dateisystem, Shell, Web). Anstatt OpenClaw als Runtime zu nutzen, wird ein eigener Python- oder TypeScript-basierter Agent-Runner gebaut, der das Anthropic SDK direkt verwendet.

Jeder Schmiede-Agent ist ein Claude-Modell-Aufruf mit strukturiertem System-Prompt (dem heutigen SKILL.md entsprechend), Tool-Definitionen (exec, file_read, file_write, http_request) und Context-Window-Management.

Die Inter-Agent-Kommunikation erfolgt über eine gemeinsame Message Queue (z.B. Redis Pub/Sub oder PostgreSQL-basiert) oder einfach über das Dateisystem (wie heute mit FORGE-INDEX.md).

```typescript
// Vereinfachtes Schema
import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic();

async function runAgent(agentId: string, task: string, context: string) {
  const systemPrompt = await loadSkill(agentId); // liest SKILL.md
  const response = await client.messages.create({
    model: AGENT_MODELS[agentId],
    system: systemPrompt,
    messages: [{ role: "user", content: task }],
    tools: [execTool, fileReadTool, fileWriteTool, httpRequestTool],
  });
  // Tool-Use Loop...
}
```

Der Orchestrator ist ein TypeScript/Python Programm, das die Pipeline steuert, Gate-Freigaben via Telegram abwartet und die Agenten sequenziell oder parallel aufruft.

### Architektur auf dem VPS

- Ein neuer Container `forge-runtime` (Node.js oder Python)
- Anthropic SDK als einzige LLM-Dependency
- Tool-Implementierungen: Node.js child_process (exec), fs (file I/O), axios (HTTP)
- Telegram: Telegram Bot API direkt oder grammy/telegraf Library
- SKILL.md Dateien bleiben erhalten — gleiche Struktur, direktes Einlesen als System-Prompt
- PostgreSQL: forge-postgres (bereits vorhanden)

### Stärken

**SKILL.md Kompatibilität.** Die bestehenden SKILL.md Dateien können direkt als System-Prompts verwendet werden. Alle heute erarbeiteten Agenten-Instruktionen bleiben verwertbar — kein Neuschreiben nötig.

**Maximale Modell-Qualität für Coding-Tasks.** Claude 4 (Sonnet/Opus) ist für Code-Generierung, Architekturentscheidungen und Reasoning unter den besten verfügbaren Modellen. Für eine Softwareschmiede ist Modell-Qualität direkt produktivitätsrelevant.

**Tool-Use ist das native Paradigma.** Das Anthropic SDK ist um strukturierten Tool-Use herum gebaut — genau das, was die Schmiede braucht (exec, file I/O, HTTP-Calls). Kein Workaround wie bei n8n.

**Volle Kontrolle bei minimalem Framework-Overhead.** Kein LangGraph-Abstraktions-Layer, kein n8n-Node-System. Der Orchestrations-Code ist direkt lesbar und anpassbar.

**Parallele Agenten möglich.** Im Gegensatz zu OpenClaw (maxSpawnDepth=2) können mehrere Agenten gleichzeitig laufen — Backend, Frontend und DB-Agent parallel, echte Parallelisierung.

**Kein Vendor-Lock-In auf einen Agent-Framework.** OpenRouter bleibt weiterhin nutzbar — das SDK kann gegen beliebige OpenAI-kompatible Endpoints zeigen (für Fallback auf andere Modelle).

### Schwächen

**Signifikanter Implementierungsaufwand.** Tool-Use Loop (handle_tool_calls, continue conversation, check for stop), Context-Window-Management, Rate-Limit-Handling, Retry-Logik — das alles muss selbst implementiert werden. OpenClaw erledigt das heute.

**Kein eingebautes Session-Management.** OpenClaw verwaltet Sessions automatisch (Kontext akkumuliert sich über den Gesprächsverlauf). Im eigenen Runtime muss der Kontext explizit übergeben werden — welche Messages, welcher State, was wird abgeschnitten wenn das Context-Limit erreicht wird.

**Telegram-Integration muss gebaut werden.** n8n und OpenClaw haben fertige Telegram-Anbindungen. Hier muss ein Telegram-Bot implementiert werden (Webhook-Empfang, Nachrichten senden, Inline-Keyboards für Gate-Freigaben).

**Kosten-Kontrolle ist Eigenverantwortung.** OpenClaw zeigt keine detaillierte Kosten-Übersicht pro Agent. Ein eigenes System auch nicht — aber die Kostentransparenz die das Dashboard heute anzeigt, muss aktiv implementiert werden (Token-Counting, Cost-Calculation pro Aufruf).

### Aufwand

Initial: hoch (4–6 Wochen für vollständige, robuste Implementierung). Betrieb: mittel. Anpassungen von Agenten-Verhalten: niedrig (SKILL.md weiterhin editierbar).

---

## Gewichtung und Vergleich

| Kriterium | Gewicht | Variante A (LangGraph) | Variante B (n8n) | Variante C (Anthropic SDK) |
|-----------|---------|------------------------|------------------|---------------------------|
| Implementierungsaufwand (niedrig = gut) | 20% | ⚠️ hoch | ✅ mittel | ⚠️ hoch |
| Kontrolle über Ablauf | 15% | ✅ hoch | ⚠️ mittel | ✅ hoch |
| Modell-Qualität / Flexibilität | 15% | ✅ alle Modelle | ✅ alle Modelle | ✅ alle Modelle |
| Parallele Agenten | 10% | ✅ ja | ⚠️ begrenzt | ✅ ja |
| SKILL.md Kompatibilität | 10% | ❌ nein | ❌ nein | ✅ ja |
| Datei-basierter Workspace | 10% | ✅ natürlich | ❌ fremd | ✅ natürlich |
| Infrastruktur-Aufwand | 10% | ⚠️ neuer Container | ✅ bereits vorhanden | ⚠️ neuer Container |
| Testbarkeit | 5% | ✅ hoch | ⚠️ mittel | ✅ hoch |
| Betriebsreife / Community | 5% | ✅ gut | ✅ sehr gut | ✅ gut |

**Gesamtbewertung:**

| | Variante A | Variante B | Variante C |
|--|-----------|-----------|-----------|
| Punkte (0–10) | 6.8 | 6.2 | **7.5** |

---

## Empfehlung: Variante C — Anthropic SDK

**Begründung:**

Variante C ist die einzige, die zwei kritische Eigenschaften kombiniert: Sie ist **kompatibel mit dem heute erarbeiteten SKILL.md-System** und ermöglicht **echte Parallelisierung der Agenten**. Die bestehenden Agenten-Instruktionen bleiben verwertbar — das ist ein erheblicher Vorteil gegenüber einem vollständigen Neustart.

Das Anthropic SDK ist das "richtige Werkzeug für den Job": Es ist gebaut für agentenhafte, tool-nutzende LLM-Systeme. Die Tool-Use-Patterns (exec, file I/O, HTTP) sind genau die, die die Schmiede braucht.

Der höhere initiale Implementierungsaufwand gegenüber n8n ist gerechtfertigt, weil:
1. Das Ergebnis wartbarer ist als ein komplexer n8n-Workflow
2. Das Datei-basierte Workspace-Paradigma erhalten bleibt
3. Parallele Agenten die Pipeline beschleunigen können
4. Kein Framework-Overhead (LangGraph) den Ablauf verschleiert

**Voraussetzung für die Umsetzung:** Die drei aufwändigsten Eigenentwicklungen sind Tool-Use-Loop, Context-Window-Management und Telegram-Anbindung. Diese sollten als separate, testbare Module entwickelt werden, bevor die Agenten-Pipeline implementiert wird.

**Wann n8n (Variante B) die bessere Wahl wäre:** Wenn der Zeithorizont sehr kurz ist (< 2 Wochen) und die Pipeline-Komplexität gering bleibt (< 5 Agenten, kein Datei-basierter Workspace). Als Proof-of-Concept oder für einfachere Automatisierungen ist n8n der pragmatischste Einstieg.

---

*Umsetzungskonzept Alternativen | v1.1 | April 2026*

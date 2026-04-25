# ugly-forge — Fachkonzept

**Version 1.2 | April 2026**

---

## 1. Vision und Zweck

ugly-forge ist eine KI-Softwareschmiede: ein autonomes System, das auf Anfrage vollständige Webanwendungen entwickelt und in Betrieb nimmt — von der Anforderungsaufnahme bis zum produktiven Deployment. Der Mensch gibt das Ziel vor, die Schmiede liefert das Ergebnis.

**Was ugly-forge nicht ist:** Ein Coding-Assistent. ugly-forge übernimmt den gesamten Entwicklungsprozess eigenständig — Requirements, Architektur, Design, Implementierung, Tests, Deployment und Dokumentation. Der Mensch ist Auftraggeber und Freigabeinstanz, nicht Entwickler.

---

## 2. Einbettung in den Gesamtstack

ugly-forge ist eine bewusst aktivierbare Erweiterung des bestehenden VPS-Stacks (ugly-stack). Sie verändert die Basis-Infrastruktur nicht — sie ergänzt sie um die Schmiede-Funktionalität.

| Schicht | Verantwortung |
|---------|--------------|
| ugly-stack | Täglicher Betrieb — stabil, immer verfügbar |
| ugly-forge | Softwareentwicklung — aktivierbar, eigenständig |

Die Schmiede kann jederzeit aktiviert und deaktiviert werden, ohne den Grundbetrieb zu beeinträchtigen.

---

## 3. Das Agentenmodell

Zwölf spezialisierte Agenten bilden die Schmiede. Jeder Agent hat eine klar definierte Rolle und Verantwortung. Kein Agent greift in den Zuständigkeitsbereich eines anderen ein.

| Agent | Rolle | Verantwortung |
|-------|-------|---------------|
| **forge-orchestrator** | Koordinator | Steuert die Pipeline, verteilt Aufgaben, überwacht den Gesamtfortschritt |
| **forge-requirements** | Anforderungsanalytiker | Erhebt und dokumentiert Projektziele, User Stories und Akzeptanzkriterien |
| **forge-review** | Qualitätsprüfer | Bewertet Requirements und Architektur vor Freigabe durch den Nutzer |
| **forge-architekt** | Systemarchitekt | Entwirft das Gesamtsystem, wählt Technologien, definiert das Datenmodell |
| **forge-webdesigner** | Gestaltungsverantwortlicher | Legt visuelles Erscheinungsbild und UX-Prinzipien fest |
| **forge-db** | Datenbankverantwortlicher | Implementiert das Datenbankschema auf Basis der Architekturentscheidung |
| **forge-backend** | Backend-Entwickler | Implementiert Geschäftslogik und API |
| **forge-frontend** | Frontend-Entwickler | Implementiert die Benutzeroberfläche |
| **forge-qa** | Qualitätssicherer | Verifiziert Korrektheit und Sicherheit durch Tests |
| **forge-devops** | Deployment-Verantwortlicher | Bringt die Anwendung in Betrieb, konfiguriert Infrastruktur und DNS |
| **forge-retro** | Lernbeauftragter | Analysiert Projektverläufe und verbessert die Arbeitsprozesse der Schmiede |
| **forge-model-scout** | Marktbeobachter | Beobachtet kontinuierlich neue KI-Modelle und empfiehlt Optimierungen |

---

## 4. Der Entwicklungsprozess

Die Pipeline ist sequenziell und gate-gesteuert. Kein Schritt beginnt, bevor der vorherige abgeschlossen ist. Zwei Punkte erfordern explizite Nutzer-Freigabe.

```
Anfrage
  │
  ▼
[1] Requirements erfassen
  │
  ▼
[2] Review Gate 1 — NUTZER-FREIGABE
    Kostenschätzung + Qualitätsprüfung
    Ohne Freigabe: kein Fortschritt
  │
  ▼
[3] Architektur + Systemdesign
  │
  ▼
[4] Gestaltung (Style Guide)
  │
  ▼
[5] Review Gate 2 — NUTZER-FREIGABE
    Architektur-Prüfung + angepasste Schätzung
    Ohne Freigabe: kein Code
  │
  ▼
[6] Datenbankschema (immer zuerst)
  │
  ▼
[7] Implementierung (Backend + Frontend)
  │
  ▼
[8] Qualitätssicherung
  │
  ▼
[9] Deployment
  │
  ▼
[10] Retrospektive und Lernprozess
```

---

## 5. Qualitätssicherung und Freigabeprinzip

### 5.1 Review Gates

ugly-forge arbeitet mit zwei verbindlichen Freigabepunkten:

**Gate 1 — nach Requirements:** Der Nutzer prüft ob die Anforderungen korrekt verstanden wurden und stimmt der Kostenschätzung zu. Abweichungen können korrigiert werden, bevor Architekturarbeit beginnt.

**Gate 2 — nach Architektur:** Der Nutzer prüft Systemdesign und technische Entscheidungen. Erst mit Freigabe startet die Implementierung.

Das Gate-Prinzip stellt sicher, dass keine Ressourcen für falsch verstandene Anforderungen oder unerwünschte Architekturen verbraucht werden.

### 5.2 Qualitätssicherung durch forge-qa

Vor jedem Deployment prüft forge-qa:
- Funktionale Korrektheit (Testabdeckung)
- Sicherheitsaspekte (Eingabevalidierung, Authentifizierung)
- Deployment-Bereitschaft

Kein Deployment ohne QA-Freigabe.

---

## 6. Datenhaltung — Zwei Ebenen

Die Schmiede unterscheidet konsequent zwei Arten von Daten. Diese Trennung ist nicht nur eine technische Entscheidung — sie ist eine fachliche Notwendigkeit, die sich aus einem konkreten Problem ergeben hat.

### Erfahrung aus dem Betrieb (April 2026)

Im ersten Betrieb schrieben alle entwickelten Anwendungen in dieselbe gemeinsame Datenbank. Das führte zu zwei fundamentalen Problemen:

**Problem 1 — Deployment-Blockade:** Eine fertige Anwendung kann nicht unabhängig deployed werden, wenn ihre Daten in einer gemeinsamen Schmiede-internen Datenbank liegen. Die Anwendung wäre dauerhaft an die Schmiede-Infrastruktur gebunden — auch im produktiven Betrieb auf einem anderen System.

**Problem 2 — fehlende Projektsichtbarkeit (Ursache 1):** Ein Projekt das keine Einträge in die Schmiede-Metadaten schreiben konnte (weil die Datenhaltung nicht verfügbar war), war für die Schmiede unsichtbar. Das Dashboard zeigte es nicht. Der Orchestrator wusste nichts davon. Das Projekt hatte stattgefunden — aber die Schmiede hatte kein Gedächtnis daran. Diese Erfahrung unterstreicht: **die Verfügbarkeit der Schmiede-Metadaten ist eine Grundvoraussetzung für jeden Betrieb.**

**Problem 3 — fehlende Projektsichtbarkeit (Ursache 2, April 2026):** Selbst nach Bereitstellung der Datenhaltung blieb das Dashboard leer. Analyse ergab: der Orchestrator-Agent legte keinen DB-Eintrag an, bevor er die Pipeline startete. Requirements wurden erfasst, FORGE-INDEX.md wurde erstellt — aber das Dashboard, das ausschliesslich die Datenhaltung liest, zeigte nichts. Der Eintrag in die Schmiede-Metadaten war im Agenten-Ablauf gar nicht vorgesehen.

**Konsequenz — Registrierungsprinzip:** Ein Projekt existiert für die Schmiede erst dann, wenn es in der Datenhaltung registriert ist. Diese Registrierung ist die **erste Handlung des Orchestrators** — vor jedem anderen Schritt, vor dem Start der Pipeline, vor der Anlage von Dokumenten. Sichtbarkeit im Dashboard ab dem ersten Moment ist kein Nice-to-have, sondern ein Kontrollprinzip: nur registrierte Projekte werden verfolgt, bewertet und abgerechnet.

Aus diesen Erfahrungen entstand die klare Zwei-Ebenen-Trennung:

### 6.1 Schmiede-Metadaten (zentral)

Alle Orchestrierungsdaten werden zentral gehalten — projektübergreifend. Das ermöglicht projektübergreifende Auswertungen und das Lernen aus vergangenen Projekten.

Gespeichert werden: Projekte, Aufgaben, Agenten-Fragen, Kommunikationsverläufe, Modell-Leistungsdaten, Agent-Lernergebnisse.

Die Schmiede-Metadaten sind als eigenständiger, dedizierter Dienst betrieben — nicht als Nebenfunktion eines anderen Systems. Sie müssen verfügbar sein, bevor die erste Pipeline beginnt.

### 6.2 Anwendungsdaten (pro Projekt)

Jede entwickelte Anwendung erhält ihre eigene, vollständig isolierte Datenhaltung. **Die Wahl des Datenbanktyps ist eine Architekturentscheidung** — sie ergibt sich ausschliesslich aus den fachlichen Anforderungen des jeweiligen Projekts und wird von forge-architekt in der Blueprint-Phase festgelegt.

| Anforderung | Typische Wahl |
|-------------|--------------|
| Relationale Daten, mehrere Nutzer gleichzeitig | Relationale DB |
| Einfache Schlüssel-Wert-Daten, Sessions, Cache | In-Memory Store |
| Flexible Dokument-Strukturen | Dokumentenorientierte DB |
| Einzel-Nutzer, einfache Persistenz | Dateibasierte DB |
| Rein statische Anwendung | Keine DB |

Die Trennung zwischen Schmiede-Metadaten und Anwendungsdaten ist nicht verhandelbar: Projektdaten eines Projekts sind niemals mit Daten eines anderen Projekts vermischt. Und Anwendungsdaten eines Projekts haben keinen Bezug zur Schmiede-Infrastruktur — die Anwendung muss jederzeit unabhängig betrieben werden können.

---

## 7. Secrets-Management

Geheimnisse (API-Keys, Passwörter, Zugangsdaten) werden auf drei Ebenen verwaltet:

| Ebene | Inhalt | Zugang |
|-------|--------|--------|
| Persönlicher Tresor (Bitwarden) | Haupt-Schlüssel | Nur du, manuell |
| Infrastruktur (.env, verschlüsselt) | VPS-weite Geheimnisse | Automatisch beim Bootstrap |
| Projekt (.env.gpg) | Projektspezifische Secrets | Verschlüsselt im Git-Repo |

Kein Geheimnis wird jemals im Klartext versioniert. Pre-Commit-Hooks blockieren versehentliche Commits.

---

## 8. Deployment-Modell

Jede fertiggestellte Anwendung wird automatisch:

1. In einem eigenen Container-Verbund betrieben (isoliert von anderen Projekten)
2. Über eine eigene Subdomain erreichbar (`[projektname].beautymolt.com`)
3. Mit einem Release-Tag versioniert
4. Mit einem verschlüsselten `.env.gpg` im Repository gesichert

Das Teardown eines Projekts ist explizit und nur auf Anfrage — kein Projekt wird automatisch abgeschaltet.

---

## 9. Lernfähigkeit der Schmiede

### 9.1 Projekt-Retrospektive (forge-retro)

Nach jedem Projekt analysiert forge-retro den Verlauf und dokumentiert Erkenntnisse: Was lief gut, was lief schlecht, was sollte beim nächsten Projekt anders gemacht werden. Erkenntnisse werden direkt in die Arbeitsprozesse der betroffenen Agenten zurückgespielt.

### 9.2 Modell-Beobachtung (forge-model-scout)

Zweimal wöchentlich recherchiert forge-model-scout den Markt für KI-Modelle. Er vergleicht Leistung und Kosten aktuell genutzter Modelle mit neuen Alternativen und empfiehlt Anpassungen. Die Entscheidung über Modellwechsel trifft der Nutzer.

---

## 10. Loop-Schutz und Eskalation

Wenn ein Agent in einer Situation feststeckt (kein Fortschritt möglich, sich wiederholende Anfragen), greift ein dreistufiger Eskalationsmechanismus:

| Stufe | Wer übernimmt | Projektauswirkung |
|-------|--------------|-------------------|
| 1 | forge-orchestrator | Projekt läuft normal weiter |
| 2 | Blockierter Agent wird isoliert | Nur betroffene Aufgaben pausiert |
| 3 | Nutzer-Benachrichtigung | Projekt pausiert — Nutzer erhält 3 Optionen |

Die drei Optionen bei Stufe 3: Kontext nachliefern, Aufgabe überspringen, Architektur-Mini-Review starten. Kein Projekt wird ohne explizite Entscheidung abgebrochen.

---

## 11. Dashboard

Das Dashboard gibt jederzeit Überblick über die Schmiede — ohne in den Prozess einzugreifen.

**Team-Bereich:** Konfiguration der Agenten, ihre Lernhistorie und Entwicklung über Zeit.

**Projekt-Bereich:** Aktueller Stand jedes Projekts — Aufgaben-Board, Kommunikationsflüsse, Kostenverlauf, Projektdokumente (Requirements, Blueprint, Style Guide).

**Live-Ansicht:** Welcher Agent kommuniziert gerade mit welchem, welche Aufgaben laufen, welche sind blockiert.

---

## 12. Betriebsprinzipien

- **Idempotenz:** Alle Installations- und Setup-Prozesse können beliebig oft wiederholt werden — immer mit demselben Ergebnis.
- **Commit-First:** Jede Änderung an der Schmiede wird zuerst versioniert, dann auf dem Server eingespielt. Kein manueller Eingriff auf dem VPS.
- **Keine gemeinsamen Daten zwischen Projekten:** Jedes Projekt ist vollständig isoliert.
- **Keine Automatisierung ohne Gate:** Kein Schritt der Pipeline, der Ressourcen verbraucht, läuft ohne vorherige Freigabe.
- **Registrierung vor Pipeline-Start:** Der Orchestrator registriert jedes Projekt in der Datenhaltung — als allererste Handlung, vor dem Start der ersten Agenten. Erst danach wird FORGE-INDEX.md angelegt, erst danach beginnt die Pipeline. Kein Projekt läuft ohne Registrierung.
- **Dedizierte Dienste statt Workarounds:** Wenn ein Bedarf entsteht (z.B. Datenhaltung für die Agenten), wird ein eigenständiger, spezialisierter Dienst geschaffen. Das Modifizieren bestehender Systeme um einen Bedarf zu erfüllen ist kein akzeptabler Lösungsansatz — es schafft versteckte Abhängigkeiten und zerbrechliche Setups.
- **Sauberer Neustart in der POC-Phase:** Solange kein schützenswerter Produktivbetrieb besteht, ist ein sauberer Neustart (Deinstallation und Neuaufbau) einer Migration vorzuziehen. Das beweist die Funktionsfähigkeit der Architektur von Null an und verhindert das Weiterschleppen von Altlasten.

---

*Fachkonzept ugly-forge | v1.2 | April 2026*

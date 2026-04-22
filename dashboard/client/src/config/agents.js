// Agenten-Konfiguration für Dashboard-Darstellung
export const AGENTS = [
  { id: 'forge-orchestrator', label: 'Orchestrator', emoji: '🎯', phase: 'Durchgehend — Koordination & Loop-Wächter',    model: 'Gemini 2.5 Flash-Lite', x: 350, y: 55  },
  { id: 'forge-model-scout',  label: 'Model Scout',  emoji: '🔭', phase: '2× pro Woche — Modell-Markt-Recherche',           model: 'Gemini 3 Flash',        x: 700, y: 55  },
  { id: 'forge-requirements', label: 'Requirements', emoji: '📋', phase: 'Phase 1 — User Stories & Akzeptanzkriterien',        model: 'Gemini 3 Flash',        x: 110, y: 180 },
  { id: 'forge-review',       label: 'Review',       emoji: '🔍', phase: 'Phase 1+2 — Quality Gates, Freigabe',               model: 'DeepSeek V4',           x: 350, y: 180 },
  { id: 'forge-architekt',    label: 'Architekt',    emoji: '🏗',  phase: 'Phase 2 — Blueprint, System-Design, Mermaid',        model: 'DeepSeek V4',           x: 600, y: 180 },
  { id: 'forge-webdesigner',  label: 'Webdesigner',  emoji: '🎨', phase: 'Phase 2 — Layout, Style Guide, UX',                  model: 'Gemini 3 Flash',        x: 105, y: 320 },
  { id: 'forge-db',           label: 'DB',           emoji: '🗂',  phase: 'Phase 3 (parallel) — Datenmodell & Migrations',      model: 'Gemini 2.5 Flash-Lite', x: 260, y: 320 },
  { id: 'forge-backend',      label: 'Backend',      emoji: '⚙',  phase: 'Phase 3 (parallel) — Business-Logik & API',          model: 'DeepSeek V3.2',         x: 420, y: 320 },
  { id: 'forge-frontend',     label: 'Frontend',     emoji: '🖼',  phase: 'Phase 3 (parallel) — HTML/CSS/JS',                   model: 'Qwen3 Coder 480B',      x: 575, y: 320 },
  { id: 'forge-qa',           label: 'QA',           emoji: '🧪', phase: 'Phase 3+4 — Unit-, Integrations-, E2E-Tests',        model: 'DeepSeek V3.2',         x: 190, y: 450 },
  { id: 'forge-devops',       label: 'DevOps',       emoji: '🚀', phase: 'Phase 5 — Deploy, nginx, Release Tag, .env.gpg',     model: 'Gemini 2.5 Flash-Lite', x: 420, y: 450 },
  { id: 'forge-retro',        label: 'Retro',        emoji: '📊', phase: 'Phase 6 — Top-3 Analyse & SKILL.md Update',          model: 'DeepSeek V3.2',         x: 600, y: 450 },
];

// Pipeline-Verbindungen aus Konzept v7 — Abschnitt 8+9
export const PIPELINE_CONNECTIONS = [
  // Orchestrierung (immer aktiv)
  { from: 'forge-orchestrator', to: 'forge-requirements', type: 'orch',   info: 'Phase 1 starten' },
  { from: 'forge-orchestrator', to: 'forge-architekt',    type: 'orch',   info: 'Phase 2 starten' },
  { from: 'forge-orchestrator', to: 'forge-webdesigner',  type: 'orch',   info: 'Phase 2 starten' },
  { from: 'forge-orchestrator', to: 'forge-backend',      type: 'orch',   info: 'Phase 3 parallel' },
  { from: 'forge-orchestrator', to: 'forge-db',           type: 'orch',   info: 'Phase 3 parallel' },
  { from: 'forge-orchestrator', to: 'forge-frontend',     type: 'orch',   info: 'Phase 3 parallel' },
  { from: 'forge-model-scout',  to: 'forge-orchestrator', type: 'orch',   info: 'Modelle 2×/Woche', dash: true },
  // Phase 1
  { from: 'forge-requirements', to: 'forge-review',       type: 'p1',    info: 'Review Gate 1' },
  { from: 'forge-review',       to: 'forge-orchestrator', type: 'p1',    info: 'Gate Freigabe' },
  // Phase 2
  { from: 'forge-architekt',    to: 'forge-review',       type: 'p2',    info: 'Review Gate 2' },
  { from: 'forge-webdesigner',  to: 'forge-review',       type: 'p2',    info: 'Review Gate 2' },
  { from: 'forge-architekt',    to: 'forge-webdesigner',  type: 'p2',    info: 'Design-Constraints' },
  // Phase 3 — parallele Entwicklung
  { from: 'forge-backend',      to: 'forge-db',           type: 'p3',    info: 'Schema & Datenzugriff', offset: 4 },
  { from: 'forge-db',           to: 'forge-backend',      type: 'p3',    info: 'Migration-Feedback',    offset: -4 },
  { from: 'forge-backend',      to: 'forge-frontend',     type: 'p3',    info: 'API-Contract' },
  { from: 'forge-webdesigner',  to: 'forge-frontend',     type: 'p3',    info: 'Design-Specs' },
  // QA
  { from: 'forge-backend',      to: 'forge-qa',           type: 'qa',    info: 'Backend → Tests' },
  { from: 'forge-frontend',     to: 'forge-qa',           type: 'qa',    info: 'Frontend → Tests' },
  { from: 'forge-db',           to: 'forge-qa',           type: 'qa',    info: 'Migrations → Tests' },
  // Deployment
  { from: 'forge-qa',           to: 'forge-devops',       type: 'deploy',info: 'QA Freigabe → Deploy' },
  // Retro & Feedback
  { from: 'forge-devops',       to: 'forge-retro',        type: 'retro', info: 'Release → Retro' },
  { from: 'forge-retro',        to: 'forge-orchestrator', type: 'retro', info: 'SKILL.md → Orchestrator', dash: true },
];

export const CONN_COLORS = {
  orch:   '#7F77DD',
  p1:     '#378ADD',
  p2:     '#1D9E75',
  p3:     '#639922',
  qa:     '#BA7517',
  deploy: '#D85A30',
  retro:  '#888780',
};

export const CONN_LABELS = {
  orch:   'Orchestrierung',
  p1:     'Phase 1',
  p2:     'Phase 2',
  p3:     'Phase 3',
  qa:     'QA',
  deploy: 'Deployment',
  retro:  'Retro & Feedback',
};

export const STATUS_COLORS = {
  backlog:     'var(--text3)',
  in_progress: 'var(--blue)',
  test:        'var(--amber)',
  approved:    'var(--green)',
  done:        'var(--green)',
  blocked:     'var(--red)',
};

export const STATUS_LABELS = {
  backlog:     'Backlog',
  in_progress: 'In Arbeit',
  test:        'Test',
  approved:    'Freigegeben',
  done:        'Fertig',
  blocked:     'Blockiert',
};

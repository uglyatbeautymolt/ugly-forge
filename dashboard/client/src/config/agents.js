// Agenten-Konfiguration für Dashboard-Darstellung
export const AGENTS = [
  { id: 'forge-orchestrator', label: 'Orchestrator', emoji: '🎯', phase: 'core', model: 'Gemini Flash-Lite', x: 350, y: 50 },
  { id: 'forge-requirements', label: 'Requirements', emoji: '📋', phase: '1', model: 'Gemini Flash', x: 100, y: 160 },
  { id: 'forge-review', label: 'Review', emoji: '🔍', phase: '1+2', model: 'DeepSeek R1', x: 350, y: 160 },
  { id: 'forge-architekt', label: 'Architekt', emoji: '🏗️', phase: '2', model: 'DeepSeek R1', x: 600, y: 160 },
  { id: 'forge-webdesigner', label: 'Webdesigner', emoji: '🎨', phase: '2', model: 'Gemini Flash', x: 100, y: 300 },
  { id: 'forge-db', label: 'DB', emoji: '🗃️', phase: '3', model: 'Gemini Flash-Lite', x: 250, y: 300 },
  { id: 'forge-backend', label: 'Backend', emoji: '⚙️', phase: '3', model: 'DeepSeek Chat', x: 400, y: 300 },
  { id: 'forge-frontend', label: 'Frontend', emoji: '🖼️', phase: '3', model: 'Qwen3 Coder', x: 550, y: 300 },
  { id: 'forge-qa', label: 'QA', emoji: '🧪', phase: '4', model: 'DeepSeek Chat', x: 200, y: 430 },
  { id: 'forge-devops', label: 'DevOps', emoji: '🚀', phase: '4', model: 'Gemini Flash-Lite', x: 400, y: 430 },
  { id: 'forge-retro', label: 'Retro', emoji: '📊', phase: 'end', model: 'DeepSeek Chat', x: 600, y: 430 },
  { id: 'forge-model-scout', label: 'Model Scout', emoji: '🔭', phase: 'auto', model: 'Gemini Flash', x: 700, y: 50 },
];

export const STATUS_COLORS = {
  backlog: 'var(--text3)',
  in_progress: 'var(--blue)',
  test: 'var(--amber)',
  approved: 'var(--green)',
  done: 'var(--green)',
  blocked: 'var(--red)',
};

export const STATUS_LABELS = {
  backlog: 'Backlog',
  in_progress: 'In Arbeit',
  test: 'Test',
  approved: 'Freigegeben',
  done: 'Fertig',
  blocked: 'Blockiert',
};

// Nur 2 Top-Level-Tabs — Live Monitor und Scrum Board sind
// per-Projekt-Views und werden über Buttons in ProjectsView geöffnet.
const TABS = [
  { id: 'projects', label: 'Projekte', icon: '◫' },
  { id: 'team',     label: 'Team',     icon: '◈' },
];

export default function Nav({ active, onChange }) {
  return (
    <nav style={{
      background: 'var(--bg2)',
      borderBottom: '1px solid var(--border)',
      padding: '0 1.5rem',
      display: 'flex',
      gap: '2px',
      flexShrink: 0
    }}>
      {TABS.map(tab => (
        <button
          key={tab.id}
          onClick={() => onChange(tab.id)}
          style={{
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            padding: '10px 14px',
            fontSize: '13px',
            color: active === tab.id ? 'var(--accent2)' : 'var(--text2)',
            borderBottom: active === tab.id ? '2px solid var(--accent)' : '2px solid transparent',
            marginBottom: '-1px',
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            transition: 'color 0.15s'
          }}
        >
          <span style={{ fontSize: '12px', opacity: 0.8 }}>{tab.icon}</span>
          {tab.label}
        </button>
      ))}
    </nav>
  );
}

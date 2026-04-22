import { STATUS_COLORS, STATUS_LABELS } from '../config/agents.js';

const LANES = ['backlog', 'in_progress', 'test', 'approved', 'done', 'blocked'];

// Singleton-Komponente — wird von App.jsx mit pro-Projekt-gefilterten
// tasks befüttert. Kein eigener Projekt-State.
export default function ScrumBoard({ tasks, projects, project, onBack }) {
  const projectMap = Object.fromEntries((projects || []).map(p => [p.id, p]));

  const byLane = LANES.reduce((acc, lane) => {
    acc[lane] = (tasks || []).filter(t => t.status === lane);
    return acc;
  }, {});

  return (
    <div className="fade-in">
      {/* Zurück-Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '1.25rem' }}>
        <button
          onClick={onBack}
          style={{ background: 'none', border: '1px solid var(--border)', borderRadius: '6px', padding: '5px 12px', cursor: 'pointer', color: 'var(--text2)', fontSize: '12px', fontFamily: 'var(--mono)', display: 'flex', alignItems: 'center', gap: '5px' }}
        >
          ← Projekte
        </button>
        {project && (
          <>
            <span style={{ color: 'var(--border)', fontSize: '16px' }}>/</span>
            <span style={{ fontWeight: 500, fontSize: '14px' }}>{project.name}</span>
            <span style={{ fontSize: '11px', color: 'var(--text3)', background: 'var(--bg4)', padding: '2px 8px', borderRadius: '4px', fontFamily: 'var(--mono)' }}>{project.status}</span>
          </>
        )}
        <span style={{ marginLeft: 'auto', fontSize: '11px', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>SCRUM BOARD</span>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${LANES.length}, minmax(0, 1fr))`,
        gap: '12px',
        height: 'calc(100vh - 180px)',
        alignItems: 'start'
      }}>
        {LANES.map(lane => (
          <Lane key={lane} lane={lane} tasks={byLane[lane]} projectMap={projectMap} />
        ))}
      </div>
    </div>
  );
}

function Lane({ lane, tasks, projectMap }) {
  const color = STATUS_COLORS[lane];
  const label = STATUS_LABELS[lane];
  return (
    <div style={{ background: 'var(--bg2)', border: '1px solid var(--border)', borderRadius: '10px', overflow: 'hidden' }}>
      <div style={{ padding: '10px 12px', borderBottom: '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: color }} />
          <span style={{ fontSize: '12px', fontWeight: 500 }}>{label}</span>
        </div>
        <span style={{ background: 'var(--bg4)', color: 'var(--text2)', fontSize: '11px', padding: '1px 7px', borderRadius: '10px', fontFamily: 'var(--mono)' }}>{tasks.length}</span>
      </div>
      <div style={{ padding: '8px', display: 'flex', flexDirection: 'column', gap: '6px', maxHeight: 'calc(100vh - 260px)', overflow: 'auto' }}>
        {tasks.length === 0 ? (
          <div style={{ padding: '1rem', textAlign: 'center', color: 'var(--text3)', fontSize: '12px' }}>Leer</div>
        ) : (
          tasks.map(task => (
            <TaskCard key={task.id} task={task} project={projectMap[task.project_id]} />
          ))
        )}
      </div>
    </div>
  );
}

function TaskCard({ task, project }) {
  const agentEmoji = {
    'forge-orchestrator': '🎯', 'forge-requirements': '📋', 'forge-review': '🔍',
    'forge-architekt': '🏗️', 'forge-webdesigner': '🎨', 'forge-db': '🗃️',
    'forge-backend': '⚙️', 'forge-frontend': '🖼️', 'forge-qa': '🧪',
    'forge-devops': '🚀', 'forge-retro': '📊', 'forge-model-scout': '🔭'
  }[task.agent] || '🤖';

  const costDiff = task.cost_real - task.cost_estimated;
  const costOk   = costDiff <= 0 || task.cost_estimated === 0;

  return (
    <div style={{ background: 'var(--bg3)', border: '1px solid var(--border)', borderRadius: '8px', padding: '10px', fontSize: '12px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px', fontFamily: 'var(--mono)', fontSize: '10px' }}>
        <span style={{ color: 'var(--text3)' }}>est. ${(task.cost_estimated || 0).toFixed(3)}</span>
        <span style={{ color: costOk ? 'var(--text2)' : 'var(--amber)' }}>real ${(task.cost_real || 0).toFixed(3)}</span>
      </div>
      <div style={{ fontWeight: 500, marginBottom: '8px', lineHeight: 1.3 }}>{task.title}</div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          <span>{agentEmoji}</span>
          <span style={{ color: 'var(--text3)', fontSize: '10px', fontFamily: 'var(--mono)' }}>{task.agent?.replace('forge-', '')}</span>
        </div>
        <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
          {task.iterations > 0 && (
            <span style={{ background: 'var(--bg4)', color: 'var(--text3)', fontSize: '10px', padding: '1px 5px', borderRadius: '4px', fontFamily: 'var(--mono)' }}>×{task.iterations}</span>
          )}
        </div>
      </div>
    </div>
  );
}

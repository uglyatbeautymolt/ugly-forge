import { STATUS_COLORS, STATUS_LABELS } from '../config/agents.js';

export default function ProjectsView({ projects, tasks }) {
  if (!projects || projects.length === 0) {
    return (
      <div className="fade-in" style={{ textAlign: 'center', paddingTop: '4rem', color: 'var(--text3)' }}>
        <div style={{ fontSize: '2rem', marginBottom: '1rem' }}>🦞</div>
        <div>Noch keine Projekte.</div>
        <div style={{ fontSize: '12px', marginTop: '8px' }}>Starte forge-orchestrator um ein neues Projekt anzulegen.</div>
      </div>
    );
  }

  return (
    <div className="fade-in" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
      {projects.map(project => (
        <ProjectCard
          key={project.id}
          project={project}
          tasks={(tasks || []).filter(t => t.project_id === project.id)}
        />
      ))}
    </div>
  );
}

function ProjectCard({ project, tasks }) {
  const progress = project.tasks_total > 0
    ? Math.round((project.tasks_done / project.tasks_total) * 100)
    : 0;

  const budgetPct = project.budget_estimated > 0
    ? Math.min(100, Math.round((project.budget_used / project.budget_estimated) * 100))
    : 0;

  const budgetOk = budgetPct < 80;
  const budgetWarn = budgetPct >= 80 && budgetPct < 100;

  const tasksByStatus = tasks.reduce((acc, t) => {
    acc[t.status] = (acc[t.status] || 0) + 1;
    return acc;
  }, {});

  return (
    <div style={{
      background: 'var(--bg2)',
      border: '1px solid var(--border)',
      borderRadius: '12px',
      padding: '1.25rem',
      display: 'grid',
      gridTemplateColumns: '1fr auto',
      gap: '1rem'
    }}>
      {/* Links: Info */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
          <div style={{
            width: '8px', height: '8px', borderRadius: '50%',
            background: project.status === 'deployed' ? 'var(--green)'
              : project.status === 'developing' ? 'var(--blue)'
              : project.status === 'planning' ? 'var(--text3)'
              : 'var(--amber)'
          }} />
          <span style={{ fontWeight: 500, fontSize: '15px' }}>{project.name}</span>
          <span style={{
            fontSize: '11px',
            color: 'var(--text3)',
            background: 'var(--bg4)',
            padding: '2px 8px',
            borderRadius: '4px',
            fontFamily: 'var(--mono)'
          }}>{project.status}</span>
        </div>

        {project.github_repo && (
          <div style={{ fontSize: '12px', color: 'var(--text3)', marginBottom: '10px', fontFamily: 'var(--mono)' }}>
            github.com/{project.github_repo}
          </div>
        )}

        {/* Task-Status-Badges */}
        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
          {Object.entries(tasksByStatus).map(([status, count]) => (
            <span key={status} style={{
              fontSize: '11px',
              padding: '2px 8px',
              borderRadius: '4px',
              background: STATUS_COLORS[status] + '22',
              color: STATUS_COLORS[status],
              fontFamily: 'var(--mono)'
            }}>
              {STATUS_LABELS[status] || status} {count}
            </span>
          ))}
        </div>
      </div>

      {/* Rechts: Metriken */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', minWidth: '160px' }}>
        {/* Tasks Progress */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text3)', marginBottom: '4px' }}>
            <span>Tasks</span>
            <span style={{ fontFamily: 'var(--mono)' }}>{project.tasks_done}/{project.tasks_total}</span>
          </div>
          <div style={{ height: '4px', background: 'var(--bg4)', borderRadius: '2px', overflow: 'hidden' }}>
            <div style={{ height: '100%', width: `${progress}%`, background: 'var(--blue)', borderRadius: '2px', transition: 'width 0.3s' }} />
          </div>
        </div>

        {/* Budget Progress */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text3)', marginBottom: '4px' }}>
            <span>Budget</span>
            <span style={{ fontFamily: 'var(--mono)', color: budgetOk ? 'var(--text2)' : budgetWarn ? 'var(--amber)' : 'var(--red)' }}>
              ${(project.budget_used || 0).toFixed(2)} / ${(project.budget_estimated || 0).toFixed(2)}
            </span>
          </div>
          <div style={{ height: '4px', background: 'var(--bg4)', borderRadius: '2px', overflow: 'hidden' }}>
            <div style={{
              height: '100%',
              width: `${budgetPct}%`,
              background: budgetOk ? 'var(--green)' : budgetWarn ? 'var(--amber)' : 'var(--red)',
              borderRadius: '2px',
              transition: 'width 0.3s'
            }} />
          </div>
        </div>
      </div>
    </div>
  );
}

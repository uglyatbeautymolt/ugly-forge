import { AGENTS } from '../config/agents.js';

const W = 780;
const H = 520;
const NODE_R = 36;

export default function LiveMonitor({ agents, communications, tasks }) {
  const agentMap = Object.fromEntries((agents || []).map(a => [a.id, a]));

  // Letzte 20 Kommunikationen
  const recent = (communications || []).slice(0, 20);

  // Aktive Verbindungen (wer hat mit wem in letzten 5 Min gesprochen)
  const activeLinks = [];
  const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
  recent.forEach(c => {
    if (new Date(c.created_at) > fiveMinAgo) {
      activeLinks.push({ from: c.from_agent, to: c.to_agent, type: c.type });
    }
  });

  return (
    <div className="fade-in">
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: '1.5rem' }}>
        {/* Netzwerk-Graph */}
        <div style={{
          background: 'var(--bg2)',
          border: '1px solid var(--border)',
          borderRadius: '12px',
          padding: '1.5rem',
          overflow: 'hidden'
        }}>
          <div style={{ fontSize: '12px', color: 'var(--text3)', marginBottom: '1rem', fontFamily: 'var(--mono)' }}>
            AGENTEN-NETZWERK
          </div>
          <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }}>
            <defs>
              <marker id="arrow-blue" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                <path d="M0,0 L0,6 L6,3 z" fill="var(--blue)" />
              </marker>
              <marker id="arrow-amber" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                <path d="M0,0 L0,6 L6,3 z" fill="var(--amber)" />
              </marker>
              <marker id="arrow-green" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                <path d="M0,0 L0,6 L6,3 z" fill="var(--green)" />
              </marker>
            </defs>

            {/* Verbindungslinien */}
            {activeLinks.map((link, i) => {
              const fromAgent = AGENTS.find(a => a.id === link.from);
              const toAgent = AGENTS.find(a => a.id === link.to);
              if (!fromAgent || !toAgent) return null;
              const color = link.type === 'delegation' ? 'var(--blue)'
                : link.type === 'question' ? 'var(--amber)'
                : 'var(--green)';
              const markerId = link.type === 'question' ? 'arrow-amber'
                : link.type === 'delegation' ? 'arrow-blue' : 'arrow-green';
              return (
                <line
                  key={i}
                  x1={fromAgent.x} y1={fromAgent.y}
                  x2={toAgent.x} y2={toAgent.y}
                  stroke={color}
                  strokeWidth="1.5"
                  strokeDasharray={link.type === 'question' ? '4 3' : 'none'}
                  markerEnd={`url(#${markerId})`}
                  opacity="0.7"
                />
              );
            })}

            {/* Agenten-Knoten */}
            {AGENTS.map(agent => {
              const status = agentMap[agent.id];
              const isActive = status?.active || false;
              const hasTask = (tasks || []).some(
                t => t.agent === agent.id && t.status === 'in_progress'
              );

              return (
                <g key={agent.id} transform={`translate(${agent.x}, ${agent.y})`}>
                  {/* Glow bei aktivem Agent */}
                  {isActive && (
                    <circle r={NODE_R + 8} fill="var(--accent)" opacity="0.1" className="pulse" />
                  )}
                  {/* Haupt-Kreis */}
                  <circle
                    r={NODE_R}
                    fill={isActive ? 'var(--bg3)' : 'var(--bg2)'}
                    stroke={isActive ? 'var(--accent)' : 'var(--border2)'}
                    strokeWidth={isActive ? '1.5' : '1'}
                  />
                  {/* Emoji */}
                  <text textAnchor="middle" dominantBaseline="middle" fontSize="18" y="-5">{agent.emoji}</text>
                  {/* Label */}
                  <text
                    textAnchor="middle"
                    y="14"
                    fontSize="9"
                    fontFamily="var(--font)"
                    fill={isActive ? 'var(--text)' : 'var(--text3)'}
                  >
                    {agent.label}
                  </text>
                  {/* Task-Indikator */}
                  {hasTask && (
                    <circle r="5" cx="22" cy="-22" fill="var(--blue)" className="pulse" />
                  )}
                </g>
              );
            })}
          </svg>

          {/* Legende */}
          <div style={{ display: 'flex', gap: '16px', marginTop: '12px', fontSize: '11px', color: 'var(--text3)' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
              <span style={{ width: '16px', height: '2px', background: 'var(--blue)', display: 'inline-block' }} />
              Delegation
            </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
              <span style={{ width: '16px', height: '2px', background: 'var(--amber)', display: 'inline-block', borderTop: '1px dashed var(--amber)' }} />
              Frage
            </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
              <span style={{ width: '16px', height: '2px', background: 'var(--green)', display: 'inline-block' }} />
              Announce
            </span>
          </div>
        </div>

        {/* Rechte Spalte: Kommunikations-Log */}
        <div style={{
          background: 'var(--bg2)',
          border: '1px solid var(--border)',
          borderRadius: '12px',
          padding: '1.5rem',
          overflow: 'hidden',
          display: 'flex',
          flexDirection: 'column'
        }}>
          <div style={{ fontSize: '12px', color: 'var(--text3)', marginBottom: '1rem', fontFamily: 'var(--mono)' }}>
            KOMMUNIKATIONS-LOG
          </div>
          <div style={{ flex: 1, overflow: 'auto' }}>
            {recent.length === 0 ? (
              <div style={{ color: 'var(--text3)', fontSize: '13px', textAlign: 'center', paddingTop: '2rem' }}>
                Noch keine Kommunikation
              </div>
            ) : (
              recent.map((c, i) => (
                <CommEntry key={i} comm={c} />
              ))
            )}
          </div>
        </div>
      </div>

      {/* Agenten-Status-Grid */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
        gap: '8px',
        marginTop: '1.5rem'
      }}>
        {AGENTS.map(agent => {
          const status = agentMap[agent.id];
          const isActive = status?.active || false;
          const tokens = status?.totalTokens || 0;
          const cost = status?.totalCost || 0;
          return (
            <div key={agent.id} style={{
              background: 'var(--bg2)',
              border: `1px solid ${isActive ? 'var(--accent)' : 'var(--border)'}`,
              borderRadius: '8px',
              padding: '10px 12px',
              opacity: isActive ? 1 : 0.6
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '6px' }}>
                <span style={{ fontSize: '14px' }}>{agent.emoji}</span>
                <span style={{ fontSize: '12px', fontWeight: 500 }}>{agent.label}</span>
                {isActive && (
                  <span style={{
                    marginLeft: 'auto', width: '6px', height: '6px',
                    borderRadius: '50%', background: 'var(--green)',
                    animation: 'pulse 2s infinite'
                  }} />
                )}
              </div>
              <div style={{ fontSize: '10px', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>
                {agent.model}
              </div>
              {tokens > 0 && (
                <div style={{ fontSize: '10px', color: 'var(--text2)', marginTop: '4px', fontFamily: 'var(--mono)' }}>
                  {tokens >= 1000 ? `${Math.round(tokens / 1000)}K` : tokens} tok · ${cost.toFixed(3)}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function CommEntry({ comm }) {
  const typeColor = {
    delegation: 'var(--blue)',
    question: 'var(--amber)',
    announce: 'var(--green)',
    answer: 'var(--cyan)'
  }[comm.type] || 'var(--text3)';

  const time = new Date(comm.created_at).toLocaleTimeString('de-DE', {
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  });

  return (
    <div style={{
      padding: '8px 0',
      borderBottom: '1px solid var(--border)',
      fontSize: '11px'
    }}>
      <div style={{ display: 'flex', gap: '6px', alignItems: 'center', marginBottom: '3px' }}>
        <span style={{
          padding: '1px 6px',
          borderRadius: '3px',
          background: typeColor + '22',
          color: typeColor,
          fontSize: '10px',
          fontFamily: 'var(--mono)'
        }}>{comm.type}</span>
        <span style={{ color: 'var(--text2)' }}>{shortId(comm.from_agent)}</span>
        <span style={{ color: 'var(--text3)' }}>→</span>
        <span style={{ color: 'var(--text2)' }}>{shortId(comm.to_agent)}</span>
        <span style={{ marginLeft: 'auto', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>{time}</span>
      </div>
      {comm.message && (
        <div style={{ color: 'var(--text3)', paddingLeft: '2px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {comm.message}
        </div>
      )}
    </div>
  );
}

function shortId(id) {
  return id?.replace('forge-', '') || '?';
}

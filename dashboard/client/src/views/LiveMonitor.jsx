import { useState, useMemo } from 'react';
import { AGENTS, PIPELINE_CONNECTIONS, CONN_COLORS, CONN_LABELS } from '../config/agents.js';

const W = 780;
const H = 520;
const R = 32;

function edgePts(from, to, offset = 0) {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len < 1) return null;
  const px = (-dy / len) * offset;
  const py = (dx / len) * offset;
  return {
    x1: from.x + (dx / len) * (R + 2) + px,
    y1: from.y + (dy / len) * (R + 2) + py,
    x2: to.x   - (dx / len) * (R + 8) + px,
    y2: to.y   - (dy / len) * (R + 8) + py,
  };
}

// Singleton-Komponente — wird von App.jsx mit pro-Projekt-gefilterten
// communications + tasks befüttert. Kein eigener Projekt-State.
export default function LiveMonitor({ agents, communications, tasks, project, onBack, onSwitch }) {
  const [selected, setSelected] = useState(null);
  const agentMap = Object.fromEntries((agents || []).map(a => [a.id, a]));
  const nodeMap  = Object.fromEntries(AGENTS.map(a => [a.id, a]));

  const recent = (communications || []).slice(0, 20);

  const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
  const liveLinks = useMemo(() => {
    const links = [];
    recent.forEach(c => {
      if (new Date(c.created_at) > fiveMinAgo) {
        links.push({ from: c.from_agent, to: c.to_agent, commType: c.type });
      }
    });
    return links;
  }, [recent]);

  const adjacency = useMemo(() => {
    const adj = {};
    AGENTS.forEach(a => { adj[a.id] = new Set(); });
    PIPELINE_CONNECTIONS.forEach((c, i) => {
      adj[c.from]?.add(i);
      adj[c.to]?.add(i);
    });
    return adj;
  }, []);

  const connectedNodes = useMemo(() => {
    if (!selected) return new Set();
    const nodes = new Set([selected]);
    PIPELINE_CONNECTIONS.forEach(c => {
      if (c.from === selected) nodes.add(c.to);
      if (c.to === selected)   nodes.add(c.from);
    });
    return nodes;
  }, [selected]);

  function handleNodeClick(id) {
    setSelected(prev => prev === id ? null : id);
  }

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
        <span style={{ marginLeft: 'auto', fontSize: '11px', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>LIVE MONITOR</span>
        {onSwitch && (
          <button
            onClick={onSwitch}
            style={{ background: 'none', border: '1px solid var(--blue)44', borderRadius: '6px', padding: '5px 12px', cursor: 'pointer', color: 'var(--blue)', fontSize: '12px', fontFamily: 'var(--mono)', display: 'flex', alignItems: 'center', gap: '5px' }}
          >
            ⊞ Scrum
          </button>
        )}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: '1.5rem' }}>

        {/* Netzwerk-Graph */}
        <div style={{ background: 'var(--bg2)', border: '1px solid var(--border)', borderRadius: '12px', padding: '1.5rem', overflow: 'hidden' }}>
          <div style={{ fontSize: '12px', color: 'var(--text3)', marginBottom: '1rem', fontFamily: 'var(--mono)' }}>AGENTEN-NETZWERK</div>

          <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }}>
            <defs>
              {Object.entries(CONN_COLORS).map(([type, color]) => (
                <marker key={type} id={`arr-${type}`} viewBox="0 0 10 10" refX="8" refY="5"
                  markerWidth="5" markerHeight="5" orient="auto-start-reverse">
                  <path d="M2 1L8 5L2 9" fill="none" stroke={color}
                    strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </marker>
              ))}
              <marker id="arr-live-blue"  viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M2 1L8 5L2 9" fill="none" stroke="var(--blue)"  strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></marker>
              <marker id="arr-live-amber" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M2 1L8 5L2 9" fill="none" stroke="var(--amber)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></marker>
              <marker id="arr-live-green" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M2 1L8 5L2 9" fill="none" stroke="var(--green)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></marker>
            </defs>

            {PIPELINE_CONNECTIONS.map((conn, i) => {
              const from = nodeMap[conn.from];
              const to   = nodeMap[conn.to];
              if (!from || !to) return null;
              const p = edgePts(from, to, conn.offset || 0);
              if (!p) return null;
              const color = CONN_COLORS[conn.type];
              const isHighlighted = selected && adjacency[selected]?.has(i);
              const isDimmed = selected && !isHighlighted;
              return (
                <line key={`struct-${i}`}
                  x1={p.x1} y1={p.y1} x2={p.x2} y2={p.y2}
                  stroke={color}
                  strokeWidth={isHighlighted ? 2.5 : 1.3}
                  strokeDasharray={conn.dash ? '5 3' : 'none'}
                  opacity={isDimmed ? 0.06 : isHighlighted ? 1 : 0.45}
                  markerEnd={`url(#arr-${conn.type})`}
                  style={{ transition: 'opacity 0.2s, stroke-width 0.15s' }}
                />
              );
            })}

            {liveLinks.map((link, i) => {
              const from = nodeMap[link.from];
              const to   = nodeMap[link.to];
              if (!from || !to) return null;
              const p = edgePts(from, to);
              if (!p) return null;
              const liveColor = link.commType === 'question' ? 'var(--amber)' : link.commType === 'answer' ? 'var(--cyan)' : 'var(--blue)';
              const markerId  = link.commType === 'question' ? 'arr-live-amber' : 'arr-live-blue';
              return (
                <line key={`live-${i}`}
                  x1={p.x1} y1={p.y1} x2={p.x2} y2={p.y2}
                  stroke={liveColor}
                  strokeWidth="2.5"
                  strokeDasharray={link.commType === 'question' ? '4 3' : 'none'}
                  opacity="0.9"
                  markerEnd={`url(#${markerId})`}
                  className="pulse"
                />
              );
            })}

            {AGENTS.map(agent => {
              const status   = agentMap[agent.id];
              const isActive = status?.active || false;
              const hasTask  = (tasks || []).some(t => t.agent === agent.id && t.status === 'in_progress');
              const isSelected   = selected === agent.id;
              const isConnected  = selected && connectedNodes.has(agent.id) && !isSelected;
              const isDimmedNode = selected && !connectedNodes.has(agent.id);
              return (
                <g key={agent.id} onClick={() => handleNodeClick(agent.id)} style={{ cursor: 'pointer' }}>
                  {isActive && (<circle cx={agent.x} cy={agent.y} r={R + 10} fill="var(--accent)" opacity="0.08" className="pulse" />)}
                  {isSelected && (<circle cx={agent.x} cy={agent.y} r={R + 5} fill="none" stroke="white" strokeWidth="1.5" opacity="0.3" />)}
                  <circle cx={agent.x} cy={agent.y} r={R}
                    fill={isSelected ? 'var(--bg3)' : isActive ? 'var(--bg3)' : 'var(--bg2)'}
                    stroke={isSelected ? 'white' : isConnected ? 'var(--text2)' : isActive ? 'var(--accent)' : 'var(--border2)'}
                    strokeWidth={isSelected || isActive ? 1.8 : 1}
                    opacity={isDimmedNode ? 0.18 : 1}
                    style={{ transition: 'opacity 0.2s' }}
                  />
                  <text x={agent.x} y={agent.y - 4} textAnchor="middle" dominantBaseline="middle" fontSize="17" opacity={isDimmedNode ? 0.2 : 1} style={{ transition: 'opacity 0.2s' }}>{agent.emoji}</text>
                  <text x={agent.x} y={agent.y + 15} textAnchor="middle" fontSize="9" fontFamily="var(--font)" fill={isActive ? 'var(--text)' : 'var(--text3)'} opacity={isDimmedNode ? 0.2 : 1} style={{ transition: 'opacity 0.2s' }}>{agent.label}</text>
                  {hasTask && (<circle cx={agent.x + R - 4} cy={agent.y - R + 4} r="5" fill="var(--blue)" className="pulse" />)}
                </g>
              );
            })}
          </svg>

          {selected && (() => {
            const node = nodeMap[selected];
            return node ? (
              <div style={{ marginTop: '8px', padding: '8px 12px', background: 'var(--bg3)', borderRadius: '6px', fontSize: '11px', color: 'var(--text2)', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{ fontSize: '14px' }}>{node.emoji}</span>
                <span style={{ fontWeight: 500 }}>{node.label}</span>
                <span style={{ color: 'var(--text3)' }}>—</span>
                <span>{node.phase}</span>
                <span style={{ marginLeft: 'auto', fontFamily: 'var(--mono)', fontSize: '10px', color: 'var(--text3)' }}>{node.model}</span>
              </div>
            ) : null;
          })()}

          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px 14px', marginTop: selected ? '8px' : '12px', fontSize: '11px', color: 'var(--text3)' }}>
            {Object.entries(CONN_COLORS).map(([type, color]) => (
              <span key={type} style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                <svg width="18" height="8"><line x1="0" y1="4" x2="18" y2="4" stroke={color} strokeWidth="1.5" strokeDasharray={type === 'retro' ? '4 2' : 'none'} /></svg>
                {CONN_LABELS[type]}
              </span>
            ))}
          </div>
        </div>

        {/* Kommunikations-Log */}
        <div style={{ background: 'var(--bg2)', border: '1px solid var(--border)', borderRadius: '12px', padding: '1.5rem', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          <div style={{ fontSize: '12px', color: 'var(--text3)', marginBottom: '1rem', fontFamily: 'var(--mono)' }}>KOMMUNIKATIONS-LOG</div>
          <div style={{ flex: 1, overflow: 'auto' }}>
            {recent.length === 0 ? (
              <div style={{ color: 'var(--text3)', fontSize: '13px', textAlign: 'center', paddingTop: '2rem' }}>Noch keine Kommunikation</div>
            ) : (
              recent.map((c, i) => <CommEntry key={i} comm={c} />)
            )}
          </div>
        </div>
      </div>

      {/* Agenten-Status-Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '8px', marginTop: '1.5rem' }}>
        {AGENTS.map(agent => {
          const status   = agentMap[agent.id];
          const isActive = status?.active || false;
          const tokens   = status?.totalTokens || 0;
          const cost     = status?.totalCost   || 0;
          return (
            <div key={agent.id}
              onClick={() => handleNodeClick(agent.id)}
              style={{ background: 'var(--bg2)', border: `1px solid ${isActive ? 'var(--accent)' : selected === agent.id ? 'var(--text2)' : 'var(--border)'}`, borderRadius: '8px', padding: '10px 12px', opacity: isActive ? 1 : 0.65, cursor: 'pointer' }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '6px' }}>
                <span style={{ fontSize: '14px' }}>{agent.emoji}</span>
                <span style={{ fontSize: '12px', fontWeight: 500 }}>{agent.label}</span>
                {isActive && (<span style={{ marginLeft: 'auto', width: '6px', height: '6px', borderRadius: '50%', background: 'var(--green)', animation: 'pulse 2s infinite' }} />)}
              </div>
              <div style={{ fontSize: '10px', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>{agent.model}</div>
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
    question:   'var(--amber)',
    announce:   'var(--green)',
    answer:     'var(--cyan)',
  }[comm.type] || 'var(--text3)';
  const time = new Date(comm.created_at).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  return (
    <div style={{ padding: '8px 0', borderBottom: '1px solid var(--border)', fontSize: '11px' }}>
      <div style={{ display: 'flex', gap: '6px', alignItems: 'center', marginBottom: '3px' }}>
        <span style={{ padding: '1px 6px', borderRadius: '3px', background: typeColor + '22', color: typeColor, fontSize: '10px', fontFamily: 'var(--mono)' }}>{comm.type}</span>
        <span style={{ color: 'var(--text2)' }}>{shortId(comm.from_agent)}</span>
        <span style={{ color: 'var(--text3)' }}>→</span>
        <span style={{ color: 'var(--text2)' }}>{shortId(comm.to_agent)}</span>
        <span style={{ marginLeft: 'auto', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>{time}</span>
      </div>
      {comm.message && (
        <div style={{ color: 'var(--text3)', paddingLeft: '2px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{comm.message}</div>
      )}
    </div>
  );
}

function shortId(id) { return id?.replace('forge-', '') || '?'; }

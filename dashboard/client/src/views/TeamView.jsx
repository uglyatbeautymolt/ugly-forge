import { AGENTS } from '../config/agents.js';

export default function TeamView({ agents }) {
  const agentMap = Object.fromEntries((agents || []).map(a => [a.id, a]));

  return (
    <div className="fade-in">
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
        gap: '1rem'
      }}>
        {AGENTS.map(agent => {
          const status = agentMap[agent.id];
          return (
            <AgentCard key={agent.id} agent={agent} status={status} />
          );
        })}
      </div>
    </div>
  );
}

function AgentCard({ agent, status }) {
  const isActive = status?.active || false;
  const tokens = status?.totalTokens || 0;
  const cost = status?.totalCost || 0;

  return (
    <div style={{
      background: 'var(--bg2)',
      border: `1px solid ${isActive ? 'var(--accent)' : 'var(--border)'}`,
      borderRadius: '12px',
      padding: '1.25rem',
      transition: 'border-color 0.2s'
    }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
        <div style={{
          width: '42px', height: '42px',
          background: isActive ? 'var(--bg4)' : 'var(--bg3)',
          borderRadius: '10px',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: '20px',
          border: `1px solid ${isActive ? 'var(--accent)' : 'var(--border)'}`
        }}>
          {agent.emoji}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 500, fontSize: '14px' }}>{agent.label}</div>
          <div style={{ fontSize: '11px', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>{agent.id}</div>
        </div>
        {isActive && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            <div style={{ width: '6px', height: '6px', borderRadius: '50%', background: 'var(--green)', animation: 'pulse 2s infinite' }} />
            <span style={{ fontSize: '11px', color: 'var(--green)' }}>aktiv</span>
          </div>
        )}
      </div>

      {/* Details */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
        <InfoRow label="Modell" value={agent.model} mono />
        <InfoRow label="Phase" value={agent.phase} />
        {tokens > 0 && (
          <InfoRow
            label="Token gesamt"
            value={tokens >= 1000 ? `${Math.round(tokens / 1000)}K` : String(tokens)}
            mono
          />
        )}
        {cost > 0 && (
          <InfoRow label="Kosten gesamt" value={`$${cost.toFixed(4)}`} mono />
        )}
      </div>
    </div>
  );
}

function InfoRow({ label, value, mono }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '12px' }}>
      <span style={{ color: 'var(--text3)' }}>{label}</span>
      <span style={{
        color: 'var(--text2)',
        fontFamily: mono ? 'var(--mono)' : 'var(--font)',
        fontSize: mono ? '11px' : '12px'
      }}>{value}</span>
    </div>
  );
}

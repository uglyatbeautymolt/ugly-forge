export default function Header({ connected, lastUpdate, stats }) {
  return (
    <div style={{
      background: 'var(--bg2)',
      borderBottom: '1px solid var(--border)',
      padding: '0 1.5rem',
      height: '52px',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      flexShrink: 0
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
        <span style={{ fontSize: '18px' }}>🦞</span>
        <span style={{ fontWeight: 500, fontSize: '15px', letterSpacing: '-0.01em' }}>ugly-forge</span>
        <span style={{
          fontSize: '11px',
          background: 'var(--bg4)',
          color: 'var(--text2)',
          padding: '2px 8px',
          borderRadius: '4px',
          fontFamily: 'var(--mono)'
        }}>dashboard</span>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: '24px' }}>
        {stats && (
          <div style={{ display: 'flex', gap: '20px' }}>
            <Stat label="Projekte" value={stats.totalProjects} />
            <Stat label="Tasks" value={`${stats.doneTasks ?? 0}/${stats.totalTasks ?? 0}`} />
            <Stat label="Kosten" value={`$${(stats.totalCost ?? 0).toFixed(2)}`} color="var(--amber)" />
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          <div style={{
            width: '8px', height: '8px', borderRadius: '50%',
            background: connected ? 'var(--green)' : 'var(--red)',
            animation: connected ? 'pulse 2s infinite' : 'none'
          }} />
          <span style={{ fontSize: '12px', color: 'var(--text2)' }}>
            {connected ? 'Live' : 'Verbinde...'}
          </span>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value, color }) {
  return (
    <div style={{ textAlign: 'right' }}>
      <div style={{ fontSize: '11px', color: 'var(--text3)', marginBottom: '1px' }}>{label}</div>
      <div style={{ fontSize: '13px', fontWeight: 500, color: color || 'var(--text)', fontFamily: 'var(--mono)' }}>{value}</div>
    </div>
  );
}

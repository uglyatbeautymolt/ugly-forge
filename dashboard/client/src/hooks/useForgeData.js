import { useState, useEffect, useRef, useCallback } from 'react';

const WS_URL = typeof window !== 'undefined'
  ? `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/ws`
  : 'ws://localhost:3001';

export function useForgeData() {
  const [data, setData] = useState({
    projects: [], tasks: [], communications: [], stats: null, agents: []
  });
  const [connected, setConnected] = useState(false);
  const [lastUpdate, setLastUpdate] = useState(null);
  const wsRef = useRef(null);
  const reconnectRef = useRef(null);

  const connect = useCallback(() => {
    try {
      const ws = new WebSocket(WS_URL);
      wsRef.current = ws;

      ws.onopen = () => {
        setConnected(true);
        console.log('WS verbunden');
        if (reconnectRef.current) {
          clearTimeout(reconnectRef.current);
          reconnectRef.current = null;
        }
      };

      ws.onmessage = (evt) => {
        try {
          const msg = JSON.parse(evt.data);
          if (msg.type === 'snapshot' || msg.type === 'update') {
            setData(prev => ({
              ...prev,
              ...msg.data,
              agents: buildAgentStatus(msg.data.communications || prev.communications)
            }));
            setLastUpdate(new Date());
          }
        } catch (e) {
          console.error('WS Parse Fehler:', e);
        }
      };

      ws.onclose = () => {
        setConnected(false);
        reconnectRef.current = setTimeout(connect, 3000);
      };

      ws.onerror = () => {
        ws.close();
      };
    } catch (e) {
      reconnectRef.current = setTimeout(connect, 5000);
    }
  }, []);

  useEffect(() => {
    connect();
    return () => {
      if (wsRef.current) wsRef.current.close();
      if (reconnectRef.current) clearTimeout(reconnectRef.current);
    };
  }, [connect]);

  // Agents-Status aus API laden (ergänzt WS-Daten)
  useEffect(() => {
    const load = () => {
      fetch('/api/agents/status')
        .then(r => r.json())
        .then(agents => setData(prev => ({ ...prev, agents })))
        .catch(() => {});
    };
    load();
    const iv = setInterval(load, 5000);
    return () => clearInterval(iv);
  }, []);

  return { data, connected, lastUpdate };
}

function buildAgentStatus(communications) {
  const agents = [
    'forge-orchestrator', 'forge-requirements', 'forge-review',
    'forge-architekt', 'forge-webdesigner', 'forge-db',
    'forge-backend', 'forge-frontend', 'forge-qa',
    'forge-devops', 'forge-retro', 'forge-model-scout'
  ];
  const cutoff = new Date(Date.now() - 10 * 60 * 1000);
  return agents.map(id => {
    const recent = communications.filter(
      c => (c.from_agent === id || c.to_agent === id) &&
           new Date(c.created_at) > cutoff
    );
    return { id, active: recent.length > 0, recentComms: recent };
  });
}

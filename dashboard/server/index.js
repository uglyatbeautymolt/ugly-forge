const express = require('express');
const cors = require('cors');
const { WebSocketServer } = require('ws');
const Database = require('better-sqlite3');
const http = require('http');
const path = require('path');
const fs = require('fs');
const https = require('https');

const PORT = process.env.PORT || 3001;
const DB_PATH = process.env.DB_PATH || '/home/node/forge-db/projects.db';
const WWW_PATH = process.env.WWW_PATH || '/home/node/www';
const WORKSPACE_PATH = process.env.WORKSPACE_PATH || '/home/node/workspace/projects';

const app = express();
app.use(cors());
app.use(express.json());

app.use(express.static(path.join(__dirname, '../client/dist')));

let db;
try {
  db = new Database(DB_PATH, { readonly: false });
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  console.log(`DB verbunden: ${DB_PATH}`);
} catch (err) {
  console.error('DB Fehler:', err.message);
  db = null;
}

function query(sql, params = []) {
  if (!db) return getMockData(sql);
  try { return db.prepare(sql).all(...params); }
  catch (e) { console.error('Query Fehler:', e.message); return []; }
}

function queryOne(sql, params = []) {
  if (!db) return null;
  try { return db.prepare(sql).get(...params); }
  catch (e) { return null; }
}

function getMockData(sql) {
  if (sql.includes('projects')) return [{ id: 'mock-1', name: 'Demo Projekt', slug: 'demo-projekt', status: 'developing', budget_estimated: 2.50, budget_used: 1.20, tasks_total: 8, tasks_done: 3, created_at: new Date().toISOString() }];
  if (sql.includes('tasks')) return [
    { id: 't1', project_id: 'mock-1', title: 'DB Schema erstellen', agent: 'forge-db', status: 'done', cost_estimated: 0.05, cost_real: 0.04, iterations: 1 },
    { id: 't2', project_id: 'mock-1', title: 'API Endpoints', agent: 'forge-backend', status: 'in_progress', cost_estimated: 0.40, cost_real: 0.22, iterations: 2 },
  ];
  if (sql.includes('model_performance')) return [];
  if (sql.includes('communications')) return [];
  if (sql.includes('agent_learnings')) return [];
  return [];
}

function cfRequest(method, cfPath, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: 'api.cloudflare.com',
      path: cfPath,
      method,
      headers: {
        'Authorization': `Bearer ${process.env.CF_TOKEN}`,
        'Content-Type': 'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {})
      },
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch(e) { reject(new Error('CF JSON: ' + data.slice(0, 100))); } });
    });
    req.on('error', reject);
    req.on('timeout', () => reject(new Error('CF timeout')));
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

app.get('/api/health', (req, res) => {
  res.json({ ok: true, db: !!db, timestamp: new Date().toISOString() });
});

// ─── File Browser API ─────────────────────────────────────────────────────────
// Liest aus WORKSPACE_PATH (workspace/projects/[slug]/) -- alle Projektdateien
// forge-devops deployed am Ende nach WWW_PATH -- dort liegt nur das fertige Output

function safeResolvePath(base, requested) {
  const baseResolved = path.resolve(base);
  const full = path.resolve(base, requested || '');
  if (!full.startsWith(baseResolved)) return null;
  return full;
}

app.get('/api/files', (req, res) => {
  const reqPath = req.query.path || '';
  const fullPath = safeResolvePath(WORKSPACE_PATH, reqPath);

  if (!fullPath) return res.status(403).json({ error: 'Ungültiger Pfad' });

  try {
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      const entries = fs.readdirSync(fullPath, { withFileTypes: true })
        .sort((a, b) => {
          if (a.isDirectory() && !b.isDirectory()) return -1;
          if (!a.isDirectory() && b.isDirectory()) return 1;
          return a.name.localeCompare(b.name);
        })
        .map(e => ({
          name: e.name,
          type: e.isDirectory() ? 'dir' : 'file',
          path: reqPath ? `${reqPath}/${e.name}` : e.name
        }));
      return res.json(entries);
    }
    if (stat.size > 512 * 1024) {
      return res.json({ content: `(Datei zu groß: ${Math.round(stat.size / 1024)}KB)`, name: path.basename(fullPath) });
    }
    const content = fs.readFileSync(fullPath, 'utf8');
    return res.json({ content, name: path.basename(fullPath) });
  } catch (e) {
    if (e.code === 'ENOENT') return res.json([]);
    return res.status(500).json({ error: e.message });
  }
});

// ─── REST API ─────────────────────────────────────────────────────────────────

app.get('/api/projects', (req, res) => {
  const projects = query('SELECT * FROM projects ORDER BY created_at DESC');
  res.json(projects);
});

app.get('/api/projects/:id', (req, res) => {
  const project = queryOne('SELECT * FROM projects WHERE id = ?', [req.params.id]);
  if (!project) return res.status(404).json({ error: 'Nicht gefunden' });
  res.json(project);
});

app.get('/api/projects/:id/tasks', (req, res) => {
  const tasks = query('SELECT * FROM tasks WHERE project_id = ? ORDER BY created_at ASC', [req.params.id]);
  res.json(tasks);
});

app.get('/api/tasks', (req, res) => {
  const tasks = query('SELECT t.*, p.name as project_name FROM tasks t LEFT JOIN projects p ON t.project_id = p.id ORDER BY t.updated_at DESC');
  res.json(tasks);
});

app.get('/api/communications', (req, res) => {
  const limit = parseInt(req.query.limit) || 50;
  res.json(query('SELECT * FROM communications ORDER BY created_at DESC LIMIT ?', [limit]));
});

app.get('/api/communications/recent', (req, res) => {
  const since = req.query.since || new Date(Date.now() - 5 * 60 * 1000).toISOString();
  res.json(query('SELECT * FROM communications WHERE created_at > ? ORDER BY created_at DESC LIMIT 100', [since]));
});

app.get('/api/performance', (req, res) => {
  const projectId = req.query.project_id;
  res.json(projectId
    ? query('SELECT * FROM model_performance WHERE project_id = ? ORDER BY created_at DESC', [projectId])
    : query('SELECT * FROM model_performance ORDER BY created_at DESC LIMIT 200'));
});

app.get('/api/learnings', (req, res) => {
  const agent = req.query.agent;
  res.json(agent
    ? query('SELECT * FROM agent_learnings WHERE agent = ? ORDER BY created_at DESC', [agent])
    : query('SELECT * FROM agent_learnings ORDER BY created_at DESC'));
});

app.get('/api/agents/status', (req, res) => {
  const agents = ['forge-orchestrator','forge-requirements','forge-review','forge-architekt','forge-webdesigner','forge-db','forge-backend','forge-frontend','forge-qa','forge-devops','forge-retro','forge-model-scout'];
  const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const status = agents.map(agentId => {
    const recentComm = queryOne('SELECT * FROM communications WHERE (from_agent = ? OR to_agent = ?) AND created_at > ? ORDER BY created_at DESC LIMIT 1', [agentId, agentId, since]);
    const activeTask = queryOne("SELECT * FROM tasks WHERE agent = ? AND status IN ('in_progress','running') ORDER BY updated_at DESC LIMIT 1", [agentId]);
    const perf = queryOne('SELECT SUM(tokens_input + tokens_output) as tokens, SUM(cost) as cost FROM model_performance WHERE agent = ?', [agentId]);
    return { id: agentId, active: !!recentComm || !!activeTask, lastSeen: recentComm?.created_at || null, activeTask: activeTask || null, totalTokens: perf?.tokens || 0, totalCost: perf?.cost || 0 };
  });
  res.json(status);
});

app.get('/api/stats', (req, res) => {
  const projects = queryOne('SELECT COUNT(*) as count FROM projects') || { count: 0 };
  const active = queryOne("SELECT COUNT(*) as count FROM projects WHERE status NOT IN ('completed', 'planning')") || { count: 0 };
  const cost = queryOne('SELECT SUM(cost) as total FROM model_performance') || { total: 0 };
  const tasks = queryOne("SELECT COUNT(*) as total, SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as done FROM tasks") || { total: 0, done: 0 };
  res.json({ totalProjects: projects.count, activeProjects: active.count, totalCost: Math.round((cost.total || 0) * 100) / 100, totalTasks: tasks.total, doneTasks: tasks.done || 0 });
});

app.post('/api/projects/:id/teardown', async (req, res) => {
  const project = queryOne('SELECT * FROM projects WHERE id = ?', [req.params.id]);
  if (!project) return res.status(404).json({ error: 'Nicht gefunden' });
  const slug = project.slug;
  if (!slug) return res.status(400).json({ error: 'Kein Slug' });

  const results = [];
  const errors  = [];
  const domain   = process.env.FORGE_DOMAIN || 'beautymolt.com';
  const hostname = project.app_url
    ? project.app_url.replace(/^https?:\/\//, '').replace(/\/$/, '')
    : `${slug}.${domain}`;

  // 1. nginx conf löschen
  try {
    fs.unlinkSync(`/home/node/nginx-conf/${slug}.conf`);
    results.push('nginx conf entfernt');
  } catch (e) {
    (e.code === 'ENOENT' ? results : errors).push(`nginx conf: ${e.code === 'ENOENT' ? 'nicht vorhanden (ok)' : e.message}`);
  }

  // 2. nginx reload via Docker Socket (SIGHUP)
  try {
    await new Promise((resolve, reject) => {
      const r = http.request({ socketPath: '/var/run/docker.sock', path: '/containers/nginx/kill?signal=HUP', method: 'POST', timeout: 5000 }, (res2) => { res2.resume(); resolve(); });
      r.on('error', reject); r.on('timeout', () => reject(new Error('timeout'))); r.end();
    });
    results.push('nginx reloaded');
  } catch (e) { errors.push(`nginx reload: ${e.message}`); }

  // 3. Cloudflare Tunnel Ingress + DNS entfernen
  const { CF_TOKEN, CF_ACCOUNT_ID, CF_TUNNEL_ID, CF_ZONE_ID } = process.env;
  if (CF_TOKEN && CF_ACCOUNT_ID && CF_TUNNEL_ID) {
    try {
      const tunnelBase = `/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations`;
      const cfg = await cfRequest('GET', tunnelBase);
      if (cfg.success) {
        const ingress = cfg.result.config.ingress.filter(e => e.hostname !== hostname);
        const config = { ingress };
        if (cfg.result.config['warp-routing'] != null) config['warp-routing'] = cfg.result.config['warp-routing'];
        const put = await cfRequest('PUT', tunnelBase, { config });
        (put.success ? results : errors).push(put.success ? 'CF Tunnel Ingress entfernt' : `CF Tunnel: ${JSON.stringify(put.errors)}`);
      }
    } catch (e) { errors.push(`CF Tunnel: ${e.message}`); }

    if (CF_ZONE_ID) {
      try {
        const dnsBase = `/client/v4/zones/${CF_ZONE_ID}/dns_records`;
        const found = await cfRequest('GET', `${dnsBase}?type=CNAME&name=${hostname}`);
        if (found.success && found.result.length > 0) {
          for (const rec of found.result) {
            const del = await cfRequest('DELETE', `${dnsBase}/${rec.id}`);
            (del.success ? results : errors).push(del.success ? 'CF DNS CNAME entfernt' : `CF DNS: ${JSON.stringify(del.errors)}`);
          }
        } else { results.push('CF DNS: kein Eintrag (ok)'); }
      } catch (e) { errors.push(`CF DNS: ${e.message}`); }
    }
  } else { errors.push('CF Variablen fehlen'); }

  // 4. DB: archived
  try {
    if (db) db.prepare("UPDATE projects SET status='archived', updated_at=CURRENT_TIMESTAMP WHERE id=?").run(req.params.id);
    results.push('DB: status=archived');
  } catch (e) { errors.push(`DB: ${e.message}`); }

  res.json({ ok: errors.length === 0, results, errors });
});

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../client/dist/index.html'));
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  sendSnapshot(ws);
  ws.on('close', () => { clients.delete(ws); });
  ws.on('error', (err) => { clients.delete(ws); });
});

function sendSnapshot(ws) {
  try {
    const payload = JSON.stringify({ type: 'snapshot', data: {
      projects: query('SELECT * FROM projects ORDER BY created_at DESC'),
      tasks: query('SELECT t.*, p.name as project_name FROM tasks t LEFT JOIN projects p ON t.project_id = p.id ORDER BY t.updated_at DESC'),
      communications: query('SELECT * FROM communications ORDER BY created_at DESC LIMIT 100'),
      stats: getStats()
    }, timestamp: new Date().toISOString() });
    if (ws.readyState === 1) ws.send(payload);
  } catch (e) { console.error('Snapshot Fehler:', e.message); }
}

function getStats() {
  const projects = queryOne('SELECT COUNT(*) as count FROM projects') || { count: 0 };
  const cost = queryOne('SELECT SUM(cost) as total FROM model_performance') || { total: 0 };
  const tasks = queryOne("SELECT COUNT(*) as total, SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as done FROM tasks") || { total: 0, done: 0 };
  return { totalProjects: projects.count, totalCost: Math.round((cost.total || 0) * 100) / 100, totalTasks: tasks.total, doneTasks: tasks.done || 0 };
}

function broadcast(type, data) {
  const msg = JSON.stringify({ type, data, timestamp: new Date().toISOString() });
  for (const ws of clients) { if (ws.readyState === 1) ws.send(msg); }
}

let lastTaskUpdate = '';
let lastCommUpdate = '';

setInterval(() => {
  if (!db) return;
  try {
    const latestTask = queryOne('SELECT updated_at FROM tasks ORDER BY updated_at DESC LIMIT 1');
    const latestComm = queryOne('SELECT created_at FROM communications ORDER BY created_at DESC LIMIT 1');
    const taskTs = latestTask?.updated_at || '';
    const commTs = latestComm?.created_at || '';
    if (taskTs !== lastTaskUpdate || commTs !== lastCommUpdate) {
      lastTaskUpdate = taskTs;
      lastCommUpdate = commTs;
      if (clients.size > 0) {
        broadcast('update', {
          tasks: query('SELECT t.*, p.name as project_name FROM tasks t LEFT JOIN projects p ON t.project_id = p.id ORDER BY t.updated_at DESC'),
          communications: query('SELECT * FROM communications ORDER BY created_at DESC LIMIT 100'),
          stats: getStats()
        });
      }
    }
  } catch (e) {}
}, 3000);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ugly-forge Dashboard Backend läuft auf Port ${PORT}`);
  console.log(`WORKSPACE: ${WORKSPACE_PATH}`);
  console.log(`WWW:       ${WWW_PATH}`);
});

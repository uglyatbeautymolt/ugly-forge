const express = require('express');
const cors = require('cors');
const { WebSocketServer } = require('ws');
const { Pool } = require('pg');
const http = require('http');
const path = require('path');
const fs = require('fs');
const https = require('https');

const PORT = process.env.PORT || 3001;
const WWW_PATH = process.env.WWW_PATH || '/home/node/www';
const WORKSPACE_PATH = process.env.WORKSPACE_PATH || '/home/node/workspace/projects';

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../client/dist')));

const pool = new Pool({
  connectionString: process.env.DATABASE_URL ||
    `postgresql://forge:${process.env.FORGE_DB_PASSWORD}@forge-postgres:5432/forge`
});

pool.connect()
  .then(c => { c.release(); console.log('DB verbunden'); })
  .catch(err => console.error('DB Fehler:', err.message));

async function query(sql, params = []) {
  try {
    const result = await pool.query(sql, params);
    return result.rows;
  } catch (e) {
    console.error('Query Fehler:', e.message);
    return [];
  }
}

async function queryOne(sql, params = []) {
  try {
    const result = await pool.query(sql, params);
    return result.rows[0] || null;
  } catch (e) {
    return null;
  }
}

function dockerRequest(method, dockerPath) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      socketPath: '/var/run/docker.sock',
      path: dockerPath, method,
      timeout: 15000
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data ? (() => { try { return JSON.parse(data); } catch { return data; } })() : null }));
    });
    req.on('error', reject);
    req.on('timeout', () => reject(new Error('Docker timeout')));
    req.end();
  });
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
  res.json({ ok: true, timestamp: new Date().toISOString() });
});

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
        .map(e => ({ name: e.name, type: e.isDirectory() ? 'dir' : 'file', path: reqPath ? `${reqPath}/${e.name}` : e.name }));
      return res.json(entries);
    }
    if (stat.size > 512 * 1024) return res.json({ content: `(Datei zu groß: ${Math.round(stat.size / 1024)}KB)`, name: path.basename(fullPath) });
    return res.json({ content: fs.readFileSync(fullPath, 'utf8'), name: path.basename(fullPath) });
  } catch (e) {
    if (e.code === 'ENOENT') return res.json([]);
    return res.status(500).json({ error: e.message });
  }
});

app.get('/api/projects', async (req, res) => {
  res.json(await query('SELECT * FROM projects ORDER BY created_at DESC'));
});

app.get('/api/projects/:id', async (req, res) => {
  const project = await queryOne('SELECT * FROM projects WHERE id = $1', [req.params.id]);
  if (!project) return res.status(404).json({ error: 'Nicht gefunden' });
  res.json(project);
});

app.get('/api/projects/:id/tasks', async (req, res) => {
  res.json(await query('SELECT * FROM tasks WHERE project_id = $1 ORDER BY created_at ASC', [req.params.id]));
});

app.get('/api/tasks', async (req, res) => {
  res.json(await query('SELECT t.*, p.name as project_name FROM tasks t LEFT JOIN projects p ON t.project_id = p.id ORDER BY t.updated_at DESC'));
});

app.get('/api/communications', async (req, res) => {
  const limit = parseInt(req.query.limit) || 50;
  res.json(await query('SELECT * FROM communications ORDER BY created_at DESC LIMIT $1', [limit]));
});

app.get('/api/communications/recent', async (req, res) => {
  const since = req.query.since || new Date(Date.now() - 5 * 60 * 1000).toISOString();
  res.json(await query('SELECT * FROM communications WHERE created_at > $1 ORDER BY created_at DESC LIMIT 100', [since]));
});

app.get('/api/performance', async (req, res) => {
  const projectId = req.query.project_id;
  res.json(projectId
    ? await query('SELECT * FROM model_performance WHERE project_id = $1 ORDER BY created_at DESC', [projectId])
    : await query('SELECT * FROM model_performance ORDER BY created_at DESC LIMIT 200'));
});

app.get('/api/learnings', async (req, res) => {
  const agent = req.query.agent;
  res.json(agent
    ? await query('SELECT * FROM agent_learnings WHERE agent = $1 ORDER BY created_at DESC', [agent])
    : await query('SELECT * FROM agent_learnings ORDER BY created_at DESC'));
});

app.get('/api/agents/status', async (req, res) => {
  const agents = ['forge-orchestrator','forge-requirements','forge-review','forge-architekt','forge-webdesigner','forge-db','forge-backend','forge-frontend','forge-qa','forge-devops','forge-retro','forge-model-scout'];
  const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const status = await Promise.all(agents.map(async agentId => {
    const recentComm = await queryOne('SELECT * FROM communications WHERE (from_agent = $1 OR to_agent = $1) AND created_at > $2 ORDER BY created_at DESC LIMIT 1', [agentId, since]);
    const activeTask = await queryOne("SELECT * FROM tasks WHERE agent = $1 AND status IN ('in_progress','running') ORDER BY updated_at DESC LIMIT 1", [agentId]);
    const perf = await queryOne('SELECT SUM(tokens_input + tokens_output) as tokens, SUM(cost) as cost FROM model_performance WHERE agent = $1', [agentId]);
    return { id: agentId, active: !!recentComm || !!activeTask, lastSeen: recentComm?.created_at || null, activeTask: activeTask || null, totalTokens: perf?.tokens || 0, totalCost: perf?.cost || 0 };
  }));
  res.json(status);
});

app.get('/api/stats', async (req, res) => {
  const projects = await queryOne('SELECT COUNT(*) as count FROM projects') || { count: 0 };
  const active = await queryOne("SELECT COUNT(*) as count FROM projects WHERE status NOT IN ('completed', 'planning')") || { count: 0 };
  const cost = await queryOne('SELECT SUM(cost) as total FROM model_performance') || { total: 0 };
  const tasks = await queryOne("SELECT COUNT(*) as total, SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as done FROM tasks") || { total: 0, done: 0 };
  res.json({ totalProjects: Number(projects.count), activeProjects: Number(active.count), totalCost: Math.round((cost.total || 0) * 100) / 100, totalTasks: Number(tasks.total), doneTasks: Number(tasks.done || 0) });
});

app.post('/api/projects/:id/teardown', async (req, res) => {
  const project = await queryOne('SELECT * FROM projects WHERE id = $1', [req.params.id]);
  if (!project) return res.status(404).json({ error: 'Nicht gefunden' });
  const slug = project.slug;
  if (!slug) return res.status(400).json({ error: 'Kein Slug' });

  const results = [];
  const errors = [];
  const domain = process.env.FORGE_DOMAIN || 'beautymolt.com';
  const hostname = project.app_url
    ? project.app_url.replace(/^https?:\/\//, '').replace(/\/$/, '')
    : `${slug}.${domain}`;

  try {
    fs.unlinkSync(`/home/node/nginx-conf/${slug}.conf`);
    results.push('nginx conf entfernt');
  } catch (e) {
    (e.code === 'ENOENT' ? results : errors).push(`nginx conf: ${e.code === 'ENOENT' ? 'nicht vorhanden (ok)' : e.message}`);
  }

  try {
    await new Promise((resolve, reject) => {
      const r = http.request({ socketPath: '/var/run/docker.sock', path: '/containers/nginx/kill?signal=HUP', method: 'POST', timeout: 5000 }, (res2) => { res2.resume(); resolve(); });
      r.on('error', reject); r.on('timeout', () => reject(new Error('timeout'))); r.end();
    });
    results.push('nginx reloaded');
  } catch (e) { errors.push(`nginx reload: ${e.message}`); }

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

  for (const suffix of ['frontend', 'backend']) {
    const cname = `${slug}-${suffix}`;
    try {
      await dockerRequest('POST', `/containers/${cname}/stop?t=10`);
      await dockerRequest('DELETE', `/containers/${cname}`);
      results.push(`Container ${cname} gestoppt`);
    } catch (e) {
      results.push(`Container ${cname}: nicht gefunden oder bereits gestoppt`);
    }
  }

  try {
    await pool.query("UPDATE projects SET status='archived', updated_at=NOW() WHERE id=$1", [req.params.id]);
    results.push('DB: status=archived');
  } catch (e) { errors.push(`DB: ${e.message}`); }

  res.json({ ok: errors.length === 0, results, errors });
});

app.post('/api/projects/:id/delete', async (req, res) => {
  const project = await queryOne('SELECT * FROM projects WHERE id = $1', [req.params.id]);
  if (!project) return res.status(404).json({ error: 'Nicht gefunden' });
  const slug = project.slug;
  if (!slug) return res.status(400).json({ error: 'Kein Slug' });

  const results = [];
  const errors = [];

  // Workspace-Dateien löschen
  const wsPath = `${WORKSPACE_PATH}/${slug}`;
  try {
    fs.rmSync(wsPath, { recursive: true, force: true });
    results.push(`Workspace ${slug}/ gelöscht`);
  } catch (e) {
    (e.code === 'ENOENT' ? results : errors).push(`Workspace: ${e.code === 'ENOENT' ? 'nicht vorhanden (ok)' : e.message}`);
  }

  // DB: status=deleted, Metadaten bleiben erhalten
  try {
    await pool.query("UPDATE projects SET status='deleted', updated_at=NOW() WHERE id=$1", [req.params.id]);
    results.push('DB: status=deleted');
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
  ws.on('close', () => clients.delete(ws));
  ws.on('error', () => clients.delete(ws));
});

async function sendSnapshot(ws) {
  try {
    const [projects, tasks, communications, stats] = await Promise.all([
      query('SELECT * FROM projects ORDER BY created_at DESC'),
      query('SELECT t.*, p.name as project_name FROM tasks t LEFT JOIN projects p ON t.project_id = p.id ORDER BY t.updated_at DESC'),
      query('SELECT * FROM communications ORDER BY created_at DESC LIMIT 100'),
      getStats()
    ]);
    const payload = JSON.stringify({ type: 'snapshot', data: { projects, tasks, communications, stats }, timestamp: new Date().toISOString() });
    if (ws.readyState === 1) ws.send(payload);
  } catch (e) { console.error('Snapshot Fehler:', e.message); }
}

async function getStats() {
  const projects = await queryOne('SELECT COUNT(*) as count FROM projects') || { count: 0 };
  const cost = await queryOne('SELECT SUM(cost) as total FROM model_performance') || { total: 0 };
  const tasks = await queryOne("SELECT COUNT(*) as total, SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as done FROM tasks") || { total: 0, done: 0 };
  return { totalProjects: Number(projects.count), totalCost: Math.round((cost.total || 0) * 100) / 100, totalTasks: Number(tasks.total), doneTasks: Number(tasks.done || 0) };
}

async function broadcast(type, data) {
  const msg = JSON.stringify({ type, data, timestamp: new Date().toISOString() });
  for (const ws of clients) { if (ws.readyState === 1) ws.send(msg); }
}

let lastTaskUpdate = '';
let lastCommUpdate = '';

setInterval(async () => {
  if (clients.size === 0) return;
  try {
    const latestTask = await queryOne('SELECT updated_at FROM tasks ORDER BY updated_at DESC LIMIT 1');
    const latestComm = await queryOne('SELECT created_at FROM communications ORDER BY created_at DESC LIMIT 1');
    const taskTs = latestTask?.updated_at?.toISOString() || '';
    const commTs = latestComm?.created_at?.toISOString() || '';
    if (taskTs !== lastTaskUpdate || commTs !== lastCommUpdate) {
      lastTaskUpdate = taskTs;
      lastCommUpdate = commTs;
      const [tasks, communications, stats] = await Promise.all([
        query('SELECT t.*, p.name as project_name FROM tasks t LEFT JOIN projects p ON t.project_id = p.id ORDER BY t.updated_at DESC'),
        query('SELECT * FROM communications ORDER BY created_at DESC LIMIT 100'),
        getStats()
      ]);
      broadcast('update', { tasks, communications, stats });
    }
  } catch (e) {}
}, 3000);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ugly-forge Dashboard Backend läuft auf Port ${PORT}`);
  console.log(`WORKSPACE: ${WORKSPACE_PATH}`);
  console.log(`WWW:       ${WWW_PATH}`);
});

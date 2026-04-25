---
name: forge_devops
description: "Deployment, nginx-Konfiguration, Cloudflare Tunnel, Release-Tags und .env.gpg Verschluesselung via openpgp.js. Kein Deploy ohne QA-Freigabe. Aktiviert bei: deployen, release, nginx konfigurieren, deployment, CI/CD, teardown, abschalten."
---

# DevOps Agent — Der Deployer

## Beim Start
1. Prüfe FORGE-INDEX.md: Ist QA approved? (oder Teardown-Modus?)
2. Wenn kein QA und kein Teardown: STOPP.
3. Lese blueprint.md — Deployment-Strategie
4. `git status` — alles committed?
5. Task anlegen (running):
```bash
exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=INSERT INTO tasks (id, project_id, title, agent, status) VALUES (gen_random_uuid()::text, '[project_id]', 'Deployment und Release', 'forge-devops', 'running');"
```

## DB-Container Entscheidung

Lese blueprint.md — welcher DB-Typ wurde vom Architekten gewählt?

### Template: PostgreSQL ([slug]-postgres)
```yaml
  [slug]-postgres:
    image: postgres:16-alpine
    container_name: [slug]-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: [slug]
      POSTGRES_USER: [slug]
      POSTGRES_PASSWORD: ${[SLUG]_DB_PASSWORD}
    volumes:
      - [slug]-db-data:/var/lib/postgresql/data
    networks:
      - ugly-net
```

### Template: MariaDB ([slug]-mariadb)
```yaml
  [slug]-mariadb:
    image: mariadb:11-jammy
    container_name: [slug]-mariadb
    restart: unless-stopped
    environment:
      MARIADB_DATABASE: [slug]
      MARIADB_USER: [slug]
      MARIADB_PASSWORD: ${[SLUG]_DB_PASSWORD}
      MARIADB_ROOT_PASSWORD: ${[SLUG]_DB_ROOT_PASSWORD}
    volumes:
      - [slug]-db-data:/var/lib/mysql
    networks:
      - ugly-net
```

### Template: Redis ([slug]-redis)
```yaml
  [slug]-redis:
    image: redis:7-alpine
    container_name: [slug]-redis
    restart: unless-stopped
    volumes:
      - [slug]-redis-data:/data
    networks:
      - ugly-net
```

### Template: SQLite (kein extra Container, Bind-Mount)
```yaml
    volumes:
      - /home/alex/ugly-forge/projects/[slug]/data:/data
    environment:
      - DB_PATH=/data/[slug].db
```

---

## Deploy — Docker Compose

Projektverzeichnis: `/home/node/.openclaw/workspace/projects/[slug]/`

**Schritt 1: docker-compose.yml schreiben** — DB-Container aus blueprint.md wählen:
```bash
exec: cat > /home/node/.openclaw/workspace/projects/[slug]/docker-compose.yml << 'COMPOSEEOF'
networks:
  ugly-net:
    external: true
    name: ugly-net

services:
  # DB-Container hier einfügen (Template oben)
  # [slug]-postgres ODER [slug]-mariadb ODER [slug]-redis

  frontend:
    build:
      context: .
      dockerfile: docker/Dockerfile.frontend
    container_name: [slug]-frontend
    restart: unless-stopped
    networks:
      - ugly-net

  backend:
    build:
      context: .
      dockerfile: docker/Dockerfile.backend
    container_name: [slug]-backend
    restart: unless-stopped
    networks:
      - ugly-net
    environment:
      - NODE_ENV=production
      - PORT=3000
      - DATABASE_URL=postgresql://[slug]:${[SLUG]_DB_PASSWORD}@[slug]-postgres:5432/[slug]
    depends_on:
      - [slug]-postgres

volumes:
  [slug]-db-data:
    name: [slug]-db-data
COMPOSEEOF
```

**Schritt 2: Container bauen und starten:**
```bash
exec: docker compose -p [slug] -f /home/node/.openclaw/workspace/projects/[slug]/docker-compose.yml up --build -d
```

**Schritt 3: Warten bis healthy:**
```bash
exec: sleep 10 && docker ps --filter "name=[slug]" --format "{{.Names}}: {{.Status}}"
```

**Nur Frontend (statische Site):** Dateien liegen in `/home/node/www/[slug]/` — kein Docker Compose nötig, nginx serviert direkt.

## Deploy — nginx (pro Projekt eine eigene Datei)

**WICHTIG:** Immer separate Datei `/home/node/nginx-conf/[slug].conf` — niemals `default.conf` editieren.

```bash
exec: cat > /home/node/nginx-conf/[slug].conf << 'NGINXEOF'
server {
    listen 80;
    server_name [slug].beautymolt.com;
    location / {
        set $upstream http://[slug]-frontend:80;
        proxy_pass $upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXEOF
```

nginx via Docker-Socket neu laden (kein docker binary nötig):
```bash
exec: curl -s --unix-socket /var/run/docker.sock -X POST "http://localhost/containers/nginx/kill?signal=HUP"
```

## Deploy — Cloudflare Tunnel + DNS

Zwei Schritte: Tunnel-Ingress + DNS-CNAME. Beide nötig!
Variablen `$CF_TOKEN`, `$CF_ACCOUNT_ID`, `$CF_TUNNEL_ID`, `$CF_ZONE_ID` sind im Container verfügbar.

```bash
exec: python3 << 'PYEOF'
import json, urllib.request, os, sys

token      = os.environ['CF_TOKEN']
account_id = os.environ['CF_ACCOUNT_ID']
tunnel_id  = os.environ['CF_TUNNEL_ID']
zone_id    = os.environ['CF_ZONE_ID']
hostname   = '[slug].beautymolt.com'
headers    = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

def api(method, url, data=None):
    body = json.dumps(data).encode() if data else None
    req  = urllib.request.Request(url, data=body, headers=headers, method=method)
    return json.loads(urllib.request.urlopen(req).read())

# 1. Tunnel-Ingress hinzufügen
base = f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations'
resp = api('GET', base)
if not resp.get('success'): print('CF GET fehlgeschlagen:', resp); sys.exit(1)

ingress = [e for e in resp['result']['config']['ingress']
           if e.get('hostname') and e.get('service') != 'http_status:404'
           and e.get('hostname') != hostname]
ingress.append({'hostname': hostname, 'service': 'http://nginx:80'})
ingress.append({'service': 'http_status:404'})
config = {'ingress': ingress}
if resp['result']['config'].get('warp-routing') is not None:
    config['warp-routing'] = resp['result']['config']['warp-routing']
r = api('PUT', base, {'config': config})
print('Tunnel:', 'OK' if r.get('success') else f'FEHLER {r}')

# 2. DNS CNAME erstellen (idempotent: erst prüfen ob schon vorhanden)
dns_base = f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records'
existing = api('GET', f'{dns_base}?type=CNAME&name={hostname}')
if existing.get('result'):
    print('DNS: bereits vorhanden')
else:
    r2 = api('POST', dns_base, {
        'type': 'CNAME', 'name': '[slug]',
        'content': f'{tunnel_id}.cfargotunnel.com',
        'ttl': 1, 'proxied': True
    })
    print('DNS:', 'OK' if r2.get('success') else f'FEHLER {r2}')
PYEOF
```

## Deploy — Checkliste
- [ ] QA: approved
- [ ] docker-compose.yml im Projektordner vorhanden
- [ ] Container gestartet und healthy
- [ ] nginx conf `/home/node/nginx-conf/[slug].conf` geschrieben
- [ ] nginx reloaded (HUP via Docker-Socket)
- [ ] Cloudflare Tunnel Ingress gesetzt
- [ ] URL verifiziert: https://[slug].beautymolt.com

## Pre-Commit Hook (bei Repo-Init, einmalig)
```bash
#!/bin/bash
# .git/hooks/pre-commit
if git diff --cached | grep -E '(password|secret|api_key|token|GITHUB_TOKEN)\s*=\s*["'\''`][^"'\''`]{8,}' > /dev/null 2>&1; then
  echo "Potenzielle Secrets gefunden! Commit blockiert."
  exit 1
fi
if git diff --cached --name-only | grep -E '^\.env$' > /dev/null 2>&1; then
  echo ".env Datei! Commit blockiert."
  exit 1
fi
echo "Keine Secrets"
```

## Release Tag (Octokit, check-before-act)
```javascript
try {
  await octokit.repos.getReleaseByTag({ owner, repo, tag: 'v1.0.0' });
} catch (e) {
  if (e.status === 404) {
    await octokit.repos.createRelease({ owner, repo, tag_name: 'v1.0.0' });
  }
}
```

## FORGE-INDEX.md Update
```bash
exec: sed -i 's/| forge-devops | pending/| forge-devops | done/' [pfad]/FORGE-INDEX.md
exec: sed -i 's/Status: testing/Status: deployed/' [pfad]/FORGE-INDEX.md
```

## DB Update
```bash
exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=UPDATE tasks SET status='done', updated_at=NOW() WHERE agent='forge-devops' AND project_id='[id]' AND status='running';"
exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=UPDATE projects SET status='deployed', app_url='https://[slug].beautymolt.com', updated_at=NOW() WHERE id='[id]';"
```

## Announce
```
Deployment abgeschlossen: [Projektname] v[Version]
URL: https://[slug].beautymolt.com
Release Tag: v[version]
```

---

## Teardown

Wird vom Orchestrator aufgerufen wenn der Nutzer ein Projekt abschalten will.
Trigger-Beispiele: "Projekt X abschalten", "Color Blink decommissionen", "Teardown [slug]"

### Wann wird zurückgebaut?
- Explizite Nutzer-Anfrage via Telegram/Orchestrator
- NICHT automatisch — jedes Projekt läuft bis es explizit abgeschaltet wird

### Teardown Schritt 0 — app_url aus DB lesen
```bash
exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=SELECT app_url FROM projects WHERE id='[id]';"
```
Ergebnis speichern — daraus Hostname extrahieren (z.B. `colorblink.beautymolt.com` aus `https://colorblink.beautymolt.com`).
Alle folgenden Schritte nutzen diesen Hostname, NICHT `[slug].beautymolt.com`.

### Teardown Schritt 1 — nginx Conf entfernen
```bash
exec: rm -f /home/node/nginx-conf/[slug].conf
exec: curl -s --unix-socket /var/run/docker.sock -X POST "http://localhost/containers/nginx/kill?signal=HUP"
```

### Teardown Schritt 2 — Cloudflare Tunnel Ingress + DNS entfernen
```bash
exec: python3 << 'PYEOF'
import json, urllib.request, os, sys

token      = os.environ['CF_TOKEN']
account_id = os.environ['CF_ACCOUNT_ID']
tunnel_id  = os.environ['CF_TUNNEL_ID']
zone_id    = os.environ['CF_ZONE_ID']
hostname   = '[slug].beautymolt.com'
headers    = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

def api(method, url, data=None):
    body = json.dumps(data).encode() if data else None
    req  = urllib.request.Request(url, data=body, headers=headers, method=method)
    return json.loads(urllib.request.urlopen(req).read())

# 1. Tunnel-Ingress entfernen
base = f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations'
resp = api('GET', base)
ingress = [e for e in resp['result']['config']['ingress'] if e.get('hostname') != hostname]
config = {'ingress': ingress}
if resp['result']['config'].get('warp-routing') is not None:
    config['warp-routing'] = resp['result']['config']['warp-routing']
r = api('PUT', base, {'config': config})
print('Tunnel:', 'OK - Ingress entfernt' if r.get('success') else f'FEHLER {r}')

# 2. DNS CNAME löschen
dns_base = f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records'
existing = api('GET', f'{dns_base}?type=CNAME&name={hostname}')
for record in existing.get('result', []):
    r2 = api('DELETE', f'{dns_base}/{record["id"]}')
    print('DNS:', 'OK - Record gelöscht' if r2.get('success') else f'FEHLER {r2}')
PYEOF
```

### Teardown Schritt 3 — Docker Container stoppen
Die App-Container laufen auf dem Host ausserhalb des OpenClaw-Containers.
Nutzer informieren (via sessions_send an Orchestrator → Telegram):
```
Teardown [Projektname] abgeschlossen:
- nginx: [slug].conf entfernt, reload OK
- Cloudflare: Ingress [slug].beautymolt.com entfernt
- Manuell auf Host: cd [projektpfad] && docker compose down
```

### Teardown Schritt 4 — DB Update
```bash
exec: curl -s -X POST http://forge-db-api:3002/query --data-urlencode "sql=UPDATE projects SET status='archived' WHERE id='[id]';"
```

## Nicht erlaubt
- Deployment ohne QA-Freigabe
- .env committen
- default.conf direkt editieren (immer eigene [slug].conf!)
- Teardown ohne explizite Nutzer-Bestätigung

## Commit
```
chore: deploy v[version] - [projektname]
```

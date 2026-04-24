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
5. SQLite Task anlegen (running):
```bash
exec: sqlite3 /home/node/forge-db/projects.db "INSERT INTO tasks (id, project_id, title, agent, status, created_at, updated_at) VALUES (lower(hex(randomblob(4)))||'-'||lower(hex(randomblob(2)))||'-4'||substr(lower(hex(randomblob(2))),2)||'-'||substr('89ab',abs(random())%4+1,1)||substr(lower(hex(randomblob(2))),2)||'-'||lower(hex(randomblob(6))), '[project_id]', 'Deployment und Release', 'forge-devops', 'running', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);"
```

## Deploy — Docker Compose

Projektverzeichnis: `/home/node/.openclaw/workspace/projects/[slug]/`

Die docker-compose.yml liegt im Projektordner und wird vom DevOps-Agent erstellt.
Container-Namen immer `[slug]-frontend` und `[slug]-backend`.

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

## Deploy — Cloudflare Tunnel

Fügt `[slug].beautymolt.com → http://nginx:80` zum Tunnel hinzu.
Variablen `$CF_TOKEN`, `$CF_ACCOUNT_ID`, `$CF_TUNNEL_ID` sind im Container verfügbar.

```bash
exec: python3 << 'PYEOF'
import json, urllib.request, os, sys

token      = os.environ['CF_TOKEN']
account_id = os.environ['CF_ACCOUNT_ID']
tunnel_id  = os.environ['CF_TUNNEL_ID']
hostname   = '[slug].beautymolt.com'
base_url   = f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations'
headers    = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

req  = urllib.request.Request(base_url, headers=headers)
resp = json.loads(urllib.request.urlopen(req).read())
if not resp.get('success'):
    print('CF GET fehlgeschlagen:', resp); sys.exit(1)

ingress = [e for e in resp['result']['config']['ingress']
           if e.get('hostname') and e.get('service') != 'http_status:404'
           and e.get('hostname') != hostname]
ingress.append({'hostname': hostname, 'service': 'http://nginx:80'})
ingress.append({'service': 'http_status:404'})

config = {'ingress': ingress}
if resp['result']['config'].get('warp-routing') is not None:
    config['warp-routing'] = resp['result']['config']['warp-routing']

body = json.dumps({'config': config}).encode()
req2 = urllib.request.Request(base_url, data=body, headers=headers, method='PUT')
res2 = json.loads(urllib.request.urlopen(req2).read())
print('OK' if res2.get('success') else f'FEHLER: {res2}')
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

## SQLite Update
```bash
exec: sqlite3 /home/node/forge-db/projects.db "UPDATE tasks SET status='done', updated_at=CURRENT_TIMESTAMP WHERE agent='forge-devops' AND project_id='[id]' AND status='running';"
exec: sqlite3 /home/node/forge-db/projects.db "UPDATE projects SET status='deployed' WHERE id='[id]';"
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

### Teardown Schritt 1 — nginx Conf entfernen
```bash
exec: rm -f /home/node/nginx-conf/[slug].conf
exec: curl -s --unix-socket /var/run/docker.sock -X POST "http://localhost/containers/nginx/kill?signal=HUP"
```

### Teardown Schritt 2 — Cloudflare Tunnel Ingress entfernen
```bash
exec: python3 << 'PYEOF'
import json, urllib.request, os, sys

token      = os.environ['CF_TOKEN']
account_id = os.environ['CF_ACCOUNT_ID']
tunnel_id  = os.environ['CF_TUNNEL_ID']
hostname   = '[slug].beautymolt.com'
base_url   = f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations'
headers    = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

req  = urllib.request.Request(base_url, headers=headers)
resp = json.loads(urllib.request.urlopen(req).read())
if not resp.get('success'):
    print('CF GET fehlgeschlagen:', resp); sys.exit(1)

ingress = [e for e in resp['result']['config']['ingress']
           if e.get('hostname') != hostname]

config = {'ingress': ingress}
if resp['result']['config'].get('warp-routing') is not None:
    config['warp-routing'] = resp['result']['config']['warp-routing']

body = json.dumps({'config': config}).encode()
req2 = urllib.request.Request(base_url, data=body, headers=headers, method='PUT')
res2 = json.loads(urllib.request.urlopen(req2).read())
print('OK - Ingress entfernt' if res2.get('success') else f'FEHLER: {res2}')
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

### Teardown Schritt 4 — SQLite Update
```bash
exec: sqlite3 /home/node/forge-db/projects.db "UPDATE projects SET status='archived' WHERE id='[id]';"
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

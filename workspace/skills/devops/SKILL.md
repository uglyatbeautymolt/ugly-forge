---
name: forge_devops
description: "Deployment, nginx-Konfiguration, Release-Tags und .env.gpg Verschluesselung via openpgp.js. Kein Deploy ohne QA-Freigabe. Aktiviert bei: deployen, release, nginx konfigurieren, deployment, CI/CD."
---

# DevOps Agent — Der Deployer

## Beim Start
1. Prüfe FORGE-INDEX.md: Ist QA approved?
2. Wenn nein: STOPP. QA muss zuerst grünes Licht geben.
3. Lese blueprint.md — Deployment-Strategie
4. `git status` — alles committed?
5. SQLite Task anlegen (running):
```bash
exec: sqlite3 /home/node/forge-db/projects.db "INSERT INTO tasks (id, project_id, title, agent, status, created_at, updated_at) VALUES (lower(hex(randomblob(4)))||'-'||lower(hex(randomblob(2)))||'-4'||substr(lower(hex(randomblob(2))),2)||'-'||substr('89ab',abs(random())%4+1,1)||substr(lower(hex(randomblob(2))),2)||'-'||lower(hex(randomblob(6))), '[project_id]', 'Deployment und Release', 'forge-devops', 'running', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);"
```

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

## .env.gpg (openpgp.js, AES-256)
```javascript
const openpgp = require('openpgp');
const fs = require('fs');

async function encrypt() {
  const content = fs.readFileSync('.env', 'utf8');
  const msg = await openpgp.createMessage({ text: content });
  const encrypted = await openpgp.encrypt({
    message: msg,
    passwords: [process.env.PROJEKT_GPG_KEY],
    config: { preferredSymmetricAlgorithm: openpgp.enums.symmetric.aes256 }
  });
  fs.writeFileSync('.env.gpg', encrypted);
}
encrypt();
```
Kompatibel mit `gpg --decrypt .env.gpg`

## nginx (statische Sites)
```nginx
server {
  listen 80;
  server_name [subdomain].beautymolt.com;
  root /var/www/html/[projektname];
  index index.html;
  location / { try_files $uri $uri/ /index.html; }
  gzip on;
}
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

## Deployment-Checkliste
- [ ] QA: approved
- [ ] Tests gruen
- [ ] Pre-Commit Hook installiert
- [ ] .env.gpg erstellt und committed
- [ ] nginx konfiguriert
- [ ] Release Tag erstellt
- [ ] Deployment verifiziert

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
URL: [URL]
Release Tag: v[version]
```

## Nicht erlaubt
- Deployment ohne QA-Freigabe
- .env committen
- Deployment ohne Rollback-Plan

## Commit
```
chore: deploy v[version] - [projektname]
```

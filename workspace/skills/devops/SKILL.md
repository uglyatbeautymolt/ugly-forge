---
name: forge_devops
description: Deployment, nginx-Konfiguration, Release-Tags, .env.gpg via openpgp.js. Kein Deploy ohne QA-Freigabe. Aktiviert bei: deployen, release, nginx, deployment.
---

# DevOps Agent — Der Deployer

## Beim Start
1. Prüfe FORGE-INDEX.md: Ist QA = approved?
2. Wenn nein: STOPP. Melde "QA muss zuerst grünes Licht geben."
3. Lese blueprint.md — Deployment-Strategie
4. `git status` — alles committed?

## Pre-Commit Hook (bei Repo-Init, einmalig)
```bash
#!/bin/bash
# .git/hooks/pre-commit
if git diff --cached | grep -E '(password|secret|api_key|token|GITHUB_TOKEN)\s*=\s*["'\''`][^"'\''`]{8,}' > /dev/null 2>&1; then
  echo "❌ Potenzielle Secrets gefunden! Commit blockiert."
  exit 1
fi
if git diff --cached --name-only | grep -E '^\.env$' > /dev/null 2>&1; then
  echo "❌ .env Datei! Commit blockiert."
  exit 1
fi
echo "✅ Keine Secrets"
```

## .env.gpg (openpgp.js — AES-256)
```javascript
// exec: node -e "..."
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
  console.log('Encrypted!');
}
encrypt();
```
Kompatibel mit `gpg --decrypt .env.gpg` ✔️

## nginx (statische Sites)
```nginx
server {
  listen 80;
  server_name [subdomain].beautymolt.com;
  root /var/www/html/[projektname];
  index index.html;
  location / { try_files $uri $uri/ /index.html; }
  gzip on;
  gzip_types text/plain text/css application/javascript;
}
```

## Release Tag (Octokit, check-before-act)
```javascript
try {
  await octokit.repos.getReleaseByTag({ owner, repo, tag: 'v1.0.0' });
  // Existiert bereits
} catch (e) {
  if (e.status === 404) {
    await octokit.repos.createRelease({ owner, repo, tag_name: 'v1.0.0' });
  }
}
```

## Deployment-Checkliste
- [ ] QA: approved
- [ ] Tests grün
- [ ] Pre-Commit Hook installiert
- [ ] .env.gpg erstellt und committed
- [ ] nginx konfiguriert
- [ ] Release Tag erstellt
- [ ] Deployment verifiziert

## Rollback
```bash
exec: git checkout [vorheriger-tag]
# nginx neu laden
# Orchestrator informieren
```

## FORGE-INDEX.md Update
```bash
exec: sed -i 's/| DevOps | pending/| DevOps | done/' [pfad]/FORGE-INDEX.md
exec: sed -i 's/Status: testing/Status: deployed/' [pfad]/FORGE-INDEX.md
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

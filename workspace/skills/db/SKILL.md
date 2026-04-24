---
name: forge_db
description: "Erstellt Datenbankschema, Migrations und Queries. Immer ZUERST fertig in Entwicklungsphase. Backend und Frontend warten auf dieses Schema. Aktiviert bei: Datenbankschema erstellen, Migrations, DB-Design, Tabellen definieren."
---

# DB Agent — Der Datenbankarchitekt

## Beim Start
1. Lese `blueprint.md` — Datenbankschema Sektion
2. Prüfe FORGE-INDEX.md: Ist Architekt fertig?
3. Prüfe: SQLite oder PostgreSQL?
4. SQLite Task anlegen (running):
```bash
exec: sqlite3 /home/node/forge-db/projects.db "INSERT INTO tasks (id, project_id, title, agent, status, created_at, updated_at) VALUES (lower(hex(randomblob(4)))||'-'||lower(hex(randomblob(2)))||'-4'||substr(lower(hex(randomblob(2))),2)||'-'||substr('89ab',abs(random())%4+1,1)||substr(lower(hex(randomblob(2))),2)||'-'||lower(hex(randomblob(6))), '[project_id]', 'Datenbankschema erstellen', 'forge-db', 'running', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);"
```

## KRITISCH: Du bist IMMER ZUERST fertig
Backend UND Frontend warten auf dein Schema.
Meldepflicht sofort nach Fertigstellung!

## SQLite (Standard)

```sql
-- Immer IF NOT EXISTS (Idempotenz)
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
PRAGMA foreign_keys = ON;
```

## Migrations-Prinzip
```
migrations/
  001_initial_schema.sql
  002_add_column_x.sql
NIEMALS bestehende Migrations aendern!
```

## Idempotentes Upsert
```sql
INSERT INTO users (id, email, name) VALUES (?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  email = excluded.email,
  updated_at = CURRENT_TIMESTAMP;
```

## Output
1. `schema.sql` — vollständiges Schema
2. `migrations/001_initial.sql`
3. `seed.sql` — Testdaten (optional)
4. blueprint.md mit finalisiertem Schema updaten

## FORGE-INDEX.md Update
```bash
exec: sed -i 's/| forge-db | pending/| forge-db | done/' [pfad]/FORGE-INDEX.md
```

## SQLite Update (projects.db)
```bash
exec: sqlite3 /home/node/forge-db/projects.db "UPDATE tasks SET status='done', updated_at=CURRENT_TIMESTAMP WHERE agent='forge-db' AND project_id='[id]' AND status='running';"
```

## Announce (SOFORT!)
```
DB Schema fertig: [Projektname]
Tabellen: [Liste]
Datei: [pfad]/schema.sql
Backend Agent und Frontend Agent koennen jetzt starten.
```

## Nicht erlaubt
- Kein Application-Code
- Bestehende Migrations aendern
- Ohne Announce-Nachricht fertig sein

## Commit
```
feat: database schema & migrations - [projektname]
```

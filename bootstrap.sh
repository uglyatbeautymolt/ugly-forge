# Migration: slug Spalte idempotent hinzufuegen (Fehler ignorieren falls bereits vorhanden)
sqlite3 "$FORGE_DB_DIR/projects.db" "ALTER TABLE projects ADD COLUMN slug TEXT;" 2>/dev/null || true
echo -e "  v slug Spalte OK"

# Fehlende Slugs aus Namen generieren (idempotent)
sqlite3 "$FORGE_DB_DIR/projects.db" <<'SQL'
UPDATE projects
SET slug = lower(trim(replace(replace(replace(replace(replace(
  name,
  ' ', '-'), '_', '-'), '.', '-'), '/', '-'), '--', '-')))
WHERE slug IS NULL OR slug = '';
SQL

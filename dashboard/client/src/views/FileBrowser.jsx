import { useState, useEffect, useCallback } from 'react';

const API = '/api/files';

const EXT_ICON = {
  html: '🌐', css: '🎨', js: '⚡', json: '{}', md: '📝',
  png: '🖼', jpg: '🖼', jpeg: '🖼', svg: '🖼', gif: '🖼',
  txt: '📄', sh: '⚙️'
};

const isImage = (name) => /\.(png|jpg|jpeg|gif|svg|webp)$/i.test(name);
const isText  = (name) => /\.(html|css|js|json|md|txt|sh|xml|csv)$/i.test(name);

function fileIcon(name, isDir) {
  if (isDir) return '📁';
  const ext = name.split('.').pop().toLowerCase();
  return EXT_ICON[ext] || '📄';
}

function FileTree({ entries, currentPath, onSelect, selected }) {
  return (
    <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
      {entries.map(e => (
        <li key={e.path}>
          <button
            onClick={() => onSelect(e)}
            style={{
              width: '100%', textAlign: 'left', background: selected === e.path ? 'var(--bg3)' : 'none',
              border: 'none', cursor: 'pointer', padding: '5px 8px', borderRadius: '4px',
              fontSize: '12px', color: 'var(--text1)', display: 'flex', alignItems: 'center', gap: '6px',
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'
            }}
          >
            <span>{fileIcon(e.name, e.type === 'dir')}</span>
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.name}</span>
          </button>
          {e.children && e.children.length > 0 && (
            <div style={{ paddingLeft: '16px' }}>
              <FileTree entries={e.children} currentPath={currentPath} onSelect={onSelect} selected={selected} />
            </div>
          )}
        </li>
      ))}
    </ul>
  );
}

export default function FileBrowser() {
  const [tree, setTree]         = useState([]);
  const [expanded, setExpanded] = useState({});
  const [selected, setSelected] = useState(null);
  const [fileContent, setFileContent] = useState(null);
  const [loading, setLoading]   = useState(false);
  const [error, setError]       = useState(null);

  // Verzeichnis laden
  const loadDir = useCallback(async (dirPath = '') => {
    try {
      const res = await fetch(`${API}?path=${encodeURIComponent(dirPath)}`);
      if (!res.ok) throw new Error(await res.text());
      return await res.json();
    } catch (e) {
      return [];
    }
  }, []);

  // Root beim Start laden
  useEffect(() => {
    loadDir('').then(entries => setTree(entries || []));
  }, [loadDir]);

  const handleSelect = async (entry) => {
    setSelected(entry.path);
    setFileContent(null);
    setError(null);

    if (entry.type === 'dir') {
      // Unterordner toggeln
      if (expanded[entry.path]) {
        setExpanded(prev => ({ ...prev, [entry.path]: false }));
        setTree(prev => removeChildren(prev, entry.path));
      } else {
        setLoading(true);
        const children = await loadDir(entry.path);
        setExpanded(prev => ({ ...prev, [entry.path]: true }));
        setTree(prev => injectChildren(prev, entry.path, children));
        setLoading(false);
      }
    } else {
      // Datei anzeigen
      setLoading(true);
      try {
        const res = await fetch(`${API}?path=${encodeURIComponent(entry.path)}`);
        if (!res.ok) throw new Error('Datei nicht lesbar');
        const data = await res.json();
        setFileContent({ name: entry.name, path: entry.path, ...data });
      } catch (e) {
        setError(e.message);
      }
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', gap: '1rem', height: '100%', minHeight: 0 }}>

      {/* Sidebar — Dateibaum */}
      <div style={{
        width: '260px', flexShrink: 0,
        background: 'var(--bg2)', borderRadius: '8px',
        border: '1px solid var(--border)', padding: '12px',
        overflowY: 'auto'
      }}>
        <div style={{ fontSize: '11px', color: 'var(--text3)', marginBottom: '10px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
          📂 Generierte Dateien
        </div>
        {tree.length === 0 ? (
          <div style={{ fontSize: '12px', color: 'var(--text3)', padding: '8px' }}>
            Noch keine Dateien — Agenten sind am Werk...
          </div>
        ) : (
          <FileTree entries={tree} currentPath="" onSelect={handleSelect} selected={selected} />
        )}
      </div>

      {/* Hauptbereich — Dateiinhalt */}
      <div style={{
        flex: 1, background: 'var(--bg2)', borderRadius: '8px',
        border: '1px solid var(--border)', overflow: 'hidden',
        display: 'flex', flexDirection: 'column'
      }}>
        {!fileContent && !loading && !error && (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text3)', fontSize: '13px' }}>
            ← Datei auswählen
          </div>
        )}

        {loading && (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text3)', fontSize: '13px' }}>
            Lade...
          </div>
        )}

        {error && (
          <div style={{ padding: '1rem', color: 'var(--red)', fontSize: '13px' }}>⚠ {error}</div>
        )}

        {fileContent && !loading && (
          <>
            {/* Pfad-Anzeige */}
            <div style={{
              padding: '10px 16px', borderBottom: '1px solid var(--border)',
              fontSize: '12px', color: 'var(--text2)', display: 'flex', alignItems: 'center', gap: '6px'
            }}>
              <span style={{ color: 'var(--text3)' }}>www /</span>
              {fileContent.path.split('/').map((part, i, arr) => (
                <span key={i} style={{ color: i === arr.length - 1 ? 'var(--accent2)' : 'var(--text2)' }}>
                  {part}{i < arr.length - 1 ? ' /' : ''}
                </span>
              ))}
            </div>

            {/* Inhalt */}
            <div style={{ flex: 1, overflow: 'auto' }}>
              {isImage(fileContent.name) ? (
                <div style={{ padding: '1rem', textAlign: 'center' }}>
                  <img
                    src={`/api/files/raw?path=${encodeURIComponent(fileContent.path)}`}
                    alt={fileContent.name}
                    style={{ maxWidth: '100%', maxHeight: '70vh', borderRadius: '4px' }}
                  />
                </div>
              ) : fileContent.name.endsWith('.html') ? (
                <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
                  <div style={{ padding: '6px 16px', background: 'var(--bg3)', fontSize: '11px', color: 'var(--text3)', display: 'flex', gap: '12px' }}>
                    <span>Vorschau</span>
                  </div>
                  <iframe
                    srcDoc={fileContent.content}
                    style={{ flex: 1, border: 'none', background: '#fff' }}
                    sandbox="allow-scripts"
                    title={fileContent.name}
                  />
                </div>
              ) : (
                <pre style={{
                  margin: 0, padding: '1rem',
                  fontSize: '12px', lineHeight: '1.6',
                  color: 'var(--text1)', fontFamily: 'monospace',
                  whiteSpace: 'pre-wrap', wordBreak: 'break-all'
                }}>
                  {fileContent.content || '(Leere Datei)'}
                </pre>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

// Hilfsfunktionen für den Baum
function injectChildren(entries, targetPath, children) {
  return entries.map(e => {
    if (e.path === targetPath) return { ...e, children };
    if (e.children) return { ...e, children: injectChildren(e.children, targetPath, children) };
    return e;
  });
}

function removeChildren(entries, targetPath) {
  return entries.map(e => {
    if (e.path === targetPath) return { ...e, children: [] };
    if (e.children) return { ...e, children: removeChildren(e.children, targetPath) };
    return e;
  });
}

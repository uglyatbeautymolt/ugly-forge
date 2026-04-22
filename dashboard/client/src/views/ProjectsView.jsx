import { useState, useEffect, useCallback } from 'react';
import { STATUS_COLORS, STATUS_LABELS } from '../config/agents.js';

const EXT_ICON = {
  html: '🌐', css: '🎨', js: '⚡', json: '{}', md: '📝',
  png: '🖼', jpg: '🖼', jpeg: '🖼', svg: '🖼', gif: '🖼',
  txt: '📄', sh: '⚙️', sql: '🗄'
};

function slugify(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function fileIcon(name, isDir) {
  if (isDir) return '📁';
  const ext = name.split('.').pop().toLowerCase();
  return EXT_ICON[ext] || '📄';
}

function isImage(name) { return /\.(png|jpg|jpeg|gif|svg|webp)$/i.test(name); }

export default function ProjectsView({ projects, tasks, onOpenProject }) {
  const [openProject, setOpenProject] = useState(null);

  if (!projects || projects.length === 0) {
    return (
      <div className="fade-in" style={{ textAlign: 'center', paddingTop: '4rem', color: 'var(--text3)' }}>
        <div style={{ fontSize: '2rem', marginBottom: '1rem' }}>🦞</div>
        <div>Noch keine Projekte.</div>
        <div style={{ fontSize: '12px', marginTop: '8px' }}>Starte forge-orchestrator um ein neues Projekt anzulegen.</div>
      </div>
    );
  }

  return (
    <div className="fade-in" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
      {projects.map(project => (
        <ProjectCard
          key={project.id}
          project={project}
          tasks={(tasks || []).filter(t => t.project_id === project.id)}
          isOpen={openProject === project.id}
          onToggle={() => setOpenProject(openProject === project.id ? null : project.id)}
          onOpenProject={onOpenProject}
        />
      ))}
    </div>
  );
}

function ProjectCard({ project, tasks, isOpen, onToggle, onOpenProject }) {
  const [files, setFiles] = useState([]);
  const [noFiles, setNoFiles] = useState(false);
  const [expanded, setExpanded] = useState({});
  const [selectedFile, setSelectedFile] = useState(null);
  const [fileContent, setFileContent] = useState(null);
  const [loadingFile, setLoadingFile] = useState(false);

  const progress = project.tasks_total > 0
    ? Math.round((project.tasks_done / project.tasks_total) * 100) : 0;
  const budgetPct = project.budget_estimated > 0
    ? Math.min(100, Math.round((project.budget_used / project.budget_estimated) * 100)) : 0;
  const budgetOk   = budgetPct < 80;
  const budgetWarn = budgetPct >= 80 && budgetPct < 100;
  const tasksByStatus = tasks.reduce((acc, t) => { acc[t.status] = (acc[t.status] || 0) + 1; return acc; }, {});

  const slug = project.slug || slugify(project.name);

  useEffect(() => {
    if (!isOpen) return;
    setFiles([]);
    setNoFiles(false);
    setSelectedFile(null);
    setFileContent(null);
    fetch(`/api/files?path=${encodeURIComponent(slug)}`)
      .then(r => r.json())
      .then(data => {
        if (Array.isArray(data) && data.length > 0) {
          setFiles(data);
          setNoFiles(false);
        } else {
          setFiles([]);
          setNoFiles(true);
        }
      })
      .catch(() => { setFiles([]); setNoFiles(true); });
  }, [isOpen, slug]);

  const handleFileClick = useCallback(async (entry) => {
    if (entry.type === 'dir') {
      setExpanded(prev => ({ ...prev, [entry.path]: !prev[entry.path] }));
      if (!expanded[entry.path]) {
        const children = await fetch(`/api/files?path=${encodeURIComponent(entry.path)}`)
          .then(r => r.json()).catch(() => []);
        setFiles(prev => injectChildren(prev, entry.path, children));
      }
      return;
    }
    setSelectedFile(entry.path);
    setLoadingFile(true);
    setFileContent(null);
    try {
      const data = await fetch(`/api/files?path=${encodeURIComponent(entry.path)}`).then(r => r.json());
      setFileContent({ ...data, name: entry.name, path: entry.path });
    } catch (e) {
      setFileContent({ content: 'Fehler beim Laden', name: entry.name, path: entry.path });
    }
    setLoadingFile(false);
  }, [expanded]);

  // Button-Style helper
  const btnStyle = (accent) => ({
    background: 'none',
    border: `1px solid ${accent}44`,
    color: accent,
    borderRadius: '5px',
    padding: '3px 10px',
    fontSize: '11px',
    cursor: 'pointer',
    fontFamily: 'var(--mono)',
    transition: 'background 0.12s',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  });

  return (
    <div style={{ background: 'var(--bg2)', border: '1px solid var(--border)', borderRadius: '12px', overflow: 'hidden' }}>
      <div
        onClick={onToggle}
        style={{ padding: '1.25rem', cursor: 'pointer', display: 'grid', gridTemplateColumns: '1fr auto', gap: '1rem', borderBottom: isOpen ? '1px solid var(--border)' : 'none' }}
      >
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
            <div style={{ width: '8px', height: '8px', borderRadius: '50%', flexShrink: 0, background: project.status === 'deployed' ? 'var(--green)' : project.status === 'developing' ? 'var(--blue)' : project.status === 'planning' ? 'var(--text3)' : 'var(--amber)' }} />
            <span style={{ fontWeight: 500, fontSize: '15px' }}>{project.name}</span>
            <span style={{ fontSize: '11px', color: 'var(--text3)', background: 'var(--bg4)', padding: '2px 8px', borderRadius: '4px', fontFamily: 'var(--mono)' }}>{project.status}</span>
            <span style={{ fontSize: '11px', color: 'var(--text3)', fontFamily: 'var(--mono)', opacity: 0.5 }}>{slug}/</span>
            {/* Live + Scrum Buttons — öffnen Singleton-Views in App */}
            <div
              style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: '6px' }}
              onClick={e => e.stopPropagation()}
            >
              <button
                style={btnStyle('var(--accent)')}
                onClick={() => onOpenProject?.(project.id, 'live')}
                title="Live Monitor für dieses Projekt"
              >
                ⬡ Live
              </button>
              <button
                style={btnStyle('var(--blue)')}
                onClick={() => onOpenProject?.(project.id, 'scrum')}
                title="Scrum Board für dieses Projekt"
              >
                ⊞ Scrum
              </button>
              <span style={{ fontSize: '12px', color: 'var(--text3)', paddingLeft: '4px' }}>{isOpen ? '▲' : '▼'}</span>
            </div>
          </div>
          {project.github_repo && (
            <div style={{ fontSize: '12px', color: 'var(--text3)', marginBottom: '10px', fontFamily: 'var(--mono)' }}>github.com/{project.github_repo}</div>
          )}
          <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
            {Object.entries(tasksByStatus).map(([status, count]) => (
              <span key={status} style={{ fontSize: '11px', padding: '2px 8px', borderRadius: '4px', background: STATUS_COLORS[status] + '22', color: STATUS_COLORS[status], fontFamily: 'var(--mono)' }}>{STATUS_LABELS[status] || status} {count}</span>
            ))}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', minWidth: '160px' }}>
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text3)', marginBottom: '4px' }}><span>Tasks</span><span style={{ fontFamily: 'var(--mono)' }}>{project.tasks_done}/{project.tasks_total}</span></div>
            <div style={{ height: '4px', background: 'var(--bg4)', borderRadius: '2px', overflow: 'hidden' }}><div style={{ height: '100%', width: `${progress}%`, background: 'var(--blue)', borderRadius: '2px', transition: 'width 0.3s' }} /></div>
          </div>
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text3)', marginBottom: '4px' }}><span>Budget</span><span style={{ fontFamily: 'var(--mono)', color: budgetOk ? 'var(--text2)' : budgetWarn ? 'var(--amber)' : 'var(--red)' }}>${(project.budget_used || 0).toFixed(2)} / ${(project.budget_estimated || 0).toFixed(2)}</span></div>
            <div style={{ height: '4px', background: 'var(--bg4)', borderRadius: '2px', overflow: 'hidden' }}><div style={{ height: '100%', width: `${budgetPct}%`, background: budgetOk ? 'var(--green)' : budgetWarn ? 'var(--amber)' : 'var(--red)', borderRadius: '2px', transition: 'width 0.3s' }} /></div>
          </div>
        </div>
      </div>

      {isOpen && (
        <div style={{ display: 'flex', height: 'calc(100vh - 280px)' }}>
          <div style={{ width: '240px', flexShrink: 0, borderRight: '1px solid var(--border)', overflowY: 'auto', padding: '10px' }}>
            <div style={{ fontSize: '10px', color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '8px', padding: '0 4px' }}>
              📂 projects/{slug}/
            </div>
            {noFiles ? (
              <div style={{ fontSize: '12px', color: 'var(--text3)', padding: '8px 4px', lineHeight: '1.6' }}>
                Noch keine Dateien.<br/>
                <span style={{ fontSize: '11px', opacity: 0.7 }}>Agenten schreiben in<br/>workspace/projects/{slug}/</span>
              </div>
            ) : (
              <FileTree entries={files} selected={selectedFile} onSelect={handleFileClick} expanded={expanded} />
            )}
          </div>
          <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
            {!selectedFile && !noFiles && (
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text3)', fontSize: '13px' }}>← Datei auswählen</div>
            )}
            {noFiles && (
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: '8px', color: 'var(--text3)' }}>
                <div style={{ fontSize: '2rem' }}>🔨</div>
                <div style={{ fontSize: '13px' }}>Agenten arbeiten noch...</div>
                <div style={{ fontSize: '11px', fontFamily: 'var(--mono)', opacity: 0.6 }}>projects/{slug}/ noch nicht erstellt</div>
              </div>
            )}
            {loadingFile && (
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text3)', fontSize: '13px' }}>Lade...</div>
            )}
            {fileContent && !loadingFile && (
              <>
                <div style={{ padding: '8px 12px', borderBottom: '1px solid var(--border)', fontSize: '11px', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>{fileContent.path}</div>
                <div style={{ flex: 1, overflow: 'auto' }}>
                  {isImage(fileContent.name) ? (
                    <div style={{ padding: '1rem', textAlign: 'center' }}><img src={`/api/files/raw?path=${encodeURIComponent(fileContent.path)}`} alt={fileContent.name} style={{ maxWidth: '100%', maxHeight: '80vh' }} /></div>
                  ) : fileContent.name?.endsWith('.html') ? (
                    <iframe srcDoc={fileContent.content} style={{ width: '100%', height: '100%', border: 'none', background: '#fff' }} sandbox="allow-scripts" title={fileContent.name} />
                  ) : (
                    <pre style={{ margin: 0, padding: '1rem', fontSize: '12px', lineHeight: '1.6', color: 'var(--text1)', fontFamily: 'monospace', whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>{fileContent.content || '(Leere Datei)'}</pre>
                  )}
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function FileTree({ entries, selected, onSelect, expanded }) {
  return (
    <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
      {entries.map(e => (
        <li key={e.path}>
          <button onClick={() => onSelect(e)} style={{ width: '100%', textAlign: 'left', background: selected === e.path ? 'var(--bg3)' : 'none', border: 'none', cursor: 'pointer', padding: '4px 6px', borderRadius: '4px', fontSize: '12px', color: 'var(--text1)', display: 'flex', alignItems: 'center', gap: '5px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            <span style={{ flexShrink: 0 }}>{fileIcon(e.name, e.type === 'dir')}</span>
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.name}</span>
          </button>
          {e.type === 'dir' && expanded[e.path] && e.children?.length > 0 && (
            <div style={{ paddingLeft: '14px' }}><FileTree entries={e.children} selected={selected} onSelect={onSelect} expanded={expanded} /></div>
          )}
        </li>
      ))}
    </ul>
  );
}

function injectChildren(entries, targetPath, children) {
  return entries.map(e => {
    if (e.path === targetPath) return { ...e, children };
    if (e.children) return { ...e, children: injectChildren(e.children, targetPath, children) };
    return e;
  });
}

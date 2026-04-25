import { useState } from 'react';
import { useForgeData } from './hooks/useForgeData.js';
import Header from './components/Header.jsx';
import Nav from './components/Nav.jsx';
import TeamView from './views/TeamView.jsx';
import ProjectsView from './views/ProjectsView.jsx';
import LiveMonitor from './views/LiveMonitor.jsx';
import ScrumBoard from './views/ScrumBoard.jsx';

export default function App() {
  const [view, setView] = useState('projects');
  const [selectedProjectId, setSelectedProjectId] = useState(null);
  const [projectTab, setProjectTab] = useState(null); // 'live' | 'scrum' | null
  const { data, connected, lastUpdate } = useForgeData();

  function openProject(projectId, tab) {
    setSelectedProjectId(projectId);
    setProjectTab(tab);
  }

  function closeProject() {
    setSelectedProjectId(null);
    setProjectTab(null);
  }

  function switchTab(tab) {
    setProjectTab(tab);
  }

  function handleNavChange(nextView) {
    setView(nextView);
    closeProject();
  }

  // Singleton-Pattern: Daten werden pro Projekt gefiltert und
  // in die EINE LiveMonitor / ScrumBoard Instanz hineingegeben.
  // Fallback !c.project_id fängt Daten ohne project_id-Feld ab.
  const selectedProject = (data.projects || []).find(p => p.id === selectedProjectId) || null;

  const projectTasks = selectedProjectId
    ? (data.tasks || []).filter(t => !t.project_id || t.project_id === selectedProjectId)
    : data.tasks || [];

  const projectComms = selectedProjectId
    ? (data.communications || []).filter(c => !c.project_id || c.project_id === selectedProjectId)
    : data.communications || [];

  const showProjectDetail = selectedProjectId && projectTab;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden' }}>
      <Header connected={connected} lastUpdate={lastUpdate} stats={data.stats} />
      <Nav active={view} onChange={handleNavChange} />
      <main style={{ flex: 1, overflow: 'auto', padding: '1.5rem' }}>

        {view === 'team' && (
          <TeamView agents={data.agents} />
        )}

        {view === 'projects' && !showProjectDetail && (
          <ProjectsView
            projects={data.projects}
            tasks={data.tasks}
            onOpenProject={openProject}
          />
        )}

        {/* SINGLETON LiveMonitor — eine Instanz, bekommt pro Projekt gefilterte Daten */}
        {view === 'projects' && showProjectDetail && projectTab === 'live' && (
          <LiveMonitor
            agents={data.agents}
            communications={projectComms}
            tasks={projectTasks}
            project={selectedProject}
            onBack={closeProject}
            onSwitch={() => switchTab('scrum')}
          />
        )}

        {/* SINGLETON ScrumBoard — eine Instanz, bekommt pro Projekt gefilterte Tasks */}
        {view === 'projects' && showProjectDetail && projectTab === 'scrum' && (
          <ScrumBoard
            tasks={projectTasks}
            projects={data.projects}
            project={selectedProject}
            onBack={closeProject}
            onSwitch={() => switchTab('live')}
          />
        )}

      </main>
    </div>
  );
}

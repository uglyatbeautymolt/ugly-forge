import { useState } from 'react';
import { useForgeData } from './hooks/useForgeData.js';
import Header from './components/Header.jsx';
import Nav from './components/Nav.jsx';
import TeamView from './views/TeamView.jsx';
import ProjectsView from './views/ProjectsView.jsx';
import LiveMonitor from './views/LiveMonitor.jsx';
import ScrumBoard from './views/ScrumBoard.jsx';

export default function App() {
  const [view, setView] = useState('live');
  const { data, connected, lastUpdate } = useForgeData();

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden' }}>
      <Header connected={connected} lastUpdate={lastUpdate} stats={data.stats} />
      <Nav active={view} onChange={setView} />
      <main style={{ flex: 1, overflow: 'auto', padding: '1.5rem' }}>
        {view === 'live' && <LiveMonitor agents={data.agents} communications={data.communications} tasks={data.tasks} />}
        {view === 'scrum' && <ScrumBoard tasks={data.tasks} projects={data.projects} />}
        {view === 'projects' && <ProjectsView projects={data.projects} tasks={data.tasks} />}
        {view === 'team' && <TeamView agents={data.agents} />}
      </main>
    </div>
  );
}

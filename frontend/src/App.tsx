import { useEffect, useMemo, useState } from 'react';
import './App.css';
import { MapPage } from './pages/map/MapPage';
import { AdminPage } from './pages/admin/AdminPage';
import { LoginScreen } from './widgets/login-screen/LoginScreen';
import { useAuth } from './app/providers/AuthProvider';
import { useTheme } from './app/providers/ThemeProvider';
import { exitIcon, themeIcon } from './assets/icons';

type AppSection = 'map' | 'admin';

function LoadingScreen() {
  return (
    <div className="app-loading-screen">
      <div className="app-loading-card">Инициализация рабочего пространства…</div>
    </div>
  );
}

export default function App() {
  const { initialized, authenticated, user, mode, error, login, logout, switchRole } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const [activeSection, setActiveSection] = useState<AppSection>('map');

  const navSections = useMemo(() => {
    if (!user) {
      return ['map'] as AppSection[];
    }

    return user.role === 'admin'
      ? (['map', 'admin'] as AppSection[])
      : (['map'] as AppSection[]);
  }, [user]);

  useEffect(() => {
    if (!navSections.includes(activeSection)) {
      setActiveSection('map');
    }
  }, [activeSection, navSections]);

  if (!initialized) {
    return <LoadingScreen />;
  }

  if (!authenticated || !user) {
    return <LoginScreen mode={mode} error={error} onLogin={login} />;
  }

  return (
    <div className="app-shell">
      <header className="top-bar">
        <div className="top-bar-left">
          <div
            className={`top-nav-item ${activeSection === 'map' ? 'active' : ''}`}
            onClick={() => setActiveSection('map')}
          >
            Карта
          </div>
          {user.role === 'admin' ? (
            <div
              className={`top-nav-item ${activeSection === 'admin' ? 'active' : ''}`}
              onClick={() => setActiveSection('admin')}
            >
              Администрирование
            </div>
          ) : null}
        </div>

        <div className="top-bar-right">
          <button className="theme-toggle" type="button" onClick={toggleTheme}>
            <span><img src={themeIcon} className="bottom-icon" alt="Переключить тему" /></span>
          </button>
          <div className="user-profile">
            <span className="user-name">{user.fullName} · {user.role} · {theme}</span>
          </div>
          <button className="logout-btn" type="button" onClick={() => void logout()}>
            <span><img src={exitIcon} className="bottom-icon" alt="Выйти" /></span>
          </button>
        </div>
      </header>

      <div className="app-content">
        {activeSection === 'map' ? (
          <MapPage />
        ) : (
          <AdminPage user={user} mode={mode} onSwitchRole={switchRole} />
        )}
      </div>
    </div>
  );
}

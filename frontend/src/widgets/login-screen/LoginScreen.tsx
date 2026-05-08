import { useEffect, useRef } from 'react';
import '../../App.css';
import type { UserRole } from '../../features/auth/types';

type Props = {
  mode: 'keycloak' | 'mock';
  error: string | null;
  onLogin: (role?: UserRole) => Promise<void>;
};

export function LoginScreen({ mode, error, onLogin }: Props) {
  const startedRef = useRef(false);

  useEffect(() => {
    if (mode !== 'keycloak' || startedRef.current) {
      return;
    }
    startedRef.current = true;
    void onLogin();
  }, [mode, onLogin]);

  return (
    <div className="login-screen">
      <div className="login-card">
        <div className="login-card__eyebrow">Forestmap</div>
        <h1 className="login-card__title">Карта аномалий лесничества</h1>
        <p className="login-card__text">
          {mode === 'keycloak'
            ? 'Перенаправляем на страницу авторизации…'
            : 'Авторизуйся, чтобы открыть рабочее пространство карты и фильтры.'}
        </p>

        {error ? <div className="login-card__error">{error}</div> : null}

        {mode === 'mock' ? (
          <div className="login-card__actions">
            <button className="login-card__primary" type="button" onClick={() => void onLogin('viewer')}>
              Войти как viewer
            </button>
            <button className="login-card__secondary" type="button" onClick={() => void onLogin('admin')}>
              Войти как admin
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}

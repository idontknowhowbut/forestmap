import '../../App.css';
import type { AuthMode, AuthUser, UserRole } from '../../features/auth/types';

type Props = {
  user: AuthUser;
  mode: AuthMode;
  onSwitchRole: (role: UserRole) => Promise<void>;
};

export function AdminPage({ user, mode, onSwitchRole }: Props) {
  return (
    <div className="admin-page">
      <div className="admin-grid">
        <section className="admin-card">
          <div className="admin-card__eyebrow">Администрирование</div>
          <h2 className="admin-card__title">Профиль доступа</h2>
          <div className="admin-card__list">
            <div className="admin-card__row">
              <span>Пользователь</span>
              <strong>{user.fullName}</strong>
            </div>
            <div className="admin-card__row">
              <span>Email</span>
              <strong>{user.email || '—'}</strong>
            </div>
            <div className="admin-card__row">
              <span>Текущая роль</span>
              <strong>{user.role}</strong>
            </div>
            <div className="admin-card__row">
              <span>Режим авторизации</span>
              <strong>{mode}</strong>
            </div>
            <div className="admin-card__row">
              <span>Компания</span>
              <strong>{user.companyName || 'Будет получена с backend'}</strong>
            </div>
          </div>
        </section>

        <section className="admin-card">
          <div className="admin-card__eyebrow">Контур</div>
          <h2 className="admin-card__title">Базовые административные действия</h2>
          <p className="admin-card__text">
            На первом этапе здесь достаточно базового административного контура: информация о пользователе,
            режиме авторизации и возможности проверить роль доступа.
          </p>

          {mode === 'mock' ? (
            <div className="admin-card__actions">
              <button type="button" className="admin-card__action" onClick={() => void onSwitchRole('viewer')}>
                Переключить на viewer
              </button>
              <button type="button" className="admin-card__action" onClick={() => void onSwitchRole('admin')}>
                Переключить на admin
              </button>
            </div>
          ) : (
            <div className="admin-card__hint">
              Роль в production определяется Keycloak и backend.
            </div>
          )}
        </section>
      </div>
    </div>
  );
}

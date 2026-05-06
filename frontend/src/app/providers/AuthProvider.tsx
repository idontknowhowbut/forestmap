import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { setAccessToken } from '../../features/auth/session';
import type { AuthContextValue, AuthMode, AuthUser, UserRole } from '../../features/auth/types';

const AuthContext = createContext<AuthContextValue | null>(null);

type ProviderProps = {
  children: ReactNode;
};

type KeycloakLike = {
  token?: string;
  authenticated?: boolean;
  tokenParsed?: Record<string, unknown>;
  init: (options: Record<string, unknown>) => Promise<boolean>;
  login: (options?: Record<string, unknown>) => Promise<void>;
  logout: (options?: Record<string, unknown>) => Promise<void>;
  updateToken: (minValidity: number) => Promise<boolean>;
};

const MOCK_AUTH_STORAGE_KEY = 'forestmap.mock.auth';

function readMockAuth(): AuthUser | null {
  try {
    const raw = localStorage.getItem(MOCK_AUTH_STORAGE_KEY);
    if (!raw) {
      return null;
    }

    const parsed = JSON.parse(raw) as AuthUser;
    if (!parsed?.role || !parsed?.fullName) {
      return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

function writeMockAuth(user: AuthUser | null) {
  if (!user) {
    localStorage.removeItem(MOCK_AUTH_STORAGE_KEY);
    return;
  }

  localStorage.setItem(MOCK_AUTH_STORAGE_KEY, JSON.stringify(user));
}

function buildMockUser(role: UserRole): AuthUser {
  return {
    id: `mock-${role}`,
    fullName: role === 'admin' ? 'Mock Admin' : 'Mock Viewer',
    email: role === 'admin' ? 'admin@forestmap.local' : 'viewer@forestmap.local',
    role,
    roles: role === 'admin' ? ['viewer', 'admin'] : ['viewer'],
    companyName: 'СЕВ-ЗАП Лесничество',
  };
}

function collectRolesFromClaims(tokenParsed: Record<string, unknown> | undefined): string[] {
  const realmAccess = tokenParsed?.realm_access as { roles?: string[] } | undefined;
  const resourceAccess = tokenParsed?.resource_access as Record<string, { roles?: string[] }> | undefined;
  const resourceRoles = resourceAccess
    ? Object.values(resourceAccess).flatMap((resource) => resource.roles ?? [])
    : [];

  return Array.from(new Set([...(realmAccess?.roles ?? []), ...resourceRoles]));
}

function resolveRoleFromClaims(tokenParsed: Record<string, unknown> | undefined): UserRole {
  const roles = collectRolesFromClaims(tokenParsed);
  return roles.includes('admin') ? 'admin' : 'viewer';
}

function buildUserFromKeycloak(tokenParsed: Record<string, unknown> | undefined): AuthUser {
  const role = resolveRoleFromClaims(tokenParsed);
  const rolesFromToken = collectRolesFromClaims(tokenParsed);
  const roles: UserRole[] = rolesFromToken.includes('admin') ? ['viewer', 'admin'] : ['viewer'];

  return {
    id: String(tokenParsed?.sub ?? 'kc-user'),
    fullName: String(tokenParsed?.name ?? tokenParsed?.preferred_username ?? 'Keycloak User'),
    email: String(tokenParsed?.email ?? ''),
    role,
    roles,
    companyName: null,
  };
}

async function importKeycloak(): Promise<{ default: new (config: Record<string, unknown>) => KeycloakLike }> {
  const loader = new Function('specifier', 'return import(specifier)') as (specifier: string) => Promise<{ default: new (config: Record<string, unknown>) => KeycloakLike }>;
  return loader('keycloak-js');
}

function hasKeycloakConfig() {
  return Boolean(
    import.meta.env.VITE_KEYCLOAK_URL &&
      import.meta.env.VITE_KEYCLOAK_REALM &&
      import.meta.env.VITE_KEYCLOAK_CLIENT_ID,
  );
}

export function AuthProvider({ children }: ProviderProps) {
  const [initialized, setInitialized] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);
  const [mode, setMode] = useState<AuthMode>('mock');
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const keycloakRef = useRef<KeycloakLike | null>(null);

  const setAuthState = useCallback((next: {
    authenticated: boolean;
    token: string | null;
    user: AuthUser | null;
    mode: AuthMode;
    error?: string | null;
  }) => {
    setAuthenticated(next.authenticated);
    setToken(next.token);
    setUser(next.user);
    setMode(next.mode);
    setError(next.error ?? null);
    setAccessToken(next.token);
  }, []);

  useEffect(() => {
    let isMounted = true;
    let refreshIntervalId: number | null = null;

    async function initializeAuth() {
      if (hasKeycloakConfig()) {
        try {
          const { default: Keycloak } = await importKeycloak();
          const keycloak = new Keycloak({
            url: import.meta.env.VITE_KEYCLOAK_URL,
            realm: import.meta.env.VITE_KEYCLOAK_REALM,
            clientId: import.meta.env.VITE_KEYCLOAK_CLIENT_ID,
          });

          keycloakRef.current = keycloak;

          const isAuthenticated = await keycloak.init({
            onLoad: 'check-sso',
            pkceMethod: 'S256',
            checkLoginIframe: false,
          });

          if (!isMounted) {
            return;
          }

          if (isAuthenticated && keycloak.token) {
            const nextUser = buildUserFromKeycloak(keycloak.tokenParsed);

            setAuthState({
              authenticated: true,
              token: keycloak.token,
              user: nextUser,
              mode: 'keycloak',
            });

            refreshIntervalId = window.setInterval(async () => {
              try {
                const refreshed = await keycloak.updateToken(30);
                if (refreshed && keycloak.token && isMounted) {
                  setToken(keycloak.token);
                  setAccessToken(keycloak.token);
                }
              } catch {
                // ignore, next action will re-auth
              }
            }, 20000);
          } else {
            setAuthState({
              authenticated: false,
              token: null,
              user: null,
              mode: 'keycloak',
            });
          }

          setInitialized(true);
          return;
        } catch (authError) {
          if (!isMounted) {
            return;
          }

          setError(authError instanceof Error ? authError.message : 'Не удалось инициализировать Keycloak');
        }
      }

      const storedUser = readMockAuth();

      if (storedUser) {
        setAuthState({
          authenticated: true,
          token: `mock-token-${storedUser.role}`,
          user: storedUser,
          mode: 'mock',
        });
      } else {
        setAuthState({
          authenticated: false,
          token: null,
          user: null,
          mode: 'mock',
        });
      }

      setInitialized(true);
    }

    void initializeAuth();

    return () => {
      isMounted = false;
      if (refreshIntervalId) {
        window.clearInterval(refreshIntervalId);
      }
    };
  }, [setAuthState]);

  const login = useCallback(async (role?: UserRole) => {
    if (mode === 'keycloak' && keycloakRef.current) {
      await keycloakRef.current.login({
        redirectUri: window.location.href,
      });
      return;
    }

    const mockRole = role ?? 'viewer';
    const nextUser = buildMockUser(mockRole);
    writeMockAuth(nextUser);
    setAuthState({
      authenticated: true,
      token: `mock-token-${mockRole}`,
      user: nextUser,
      mode: 'mock',
      error: null,
    });
    setInitialized(true);
  }, [mode, setAuthState]);

  const logout = useCallback(async () => {
    if (mode === 'keycloak' && keycloakRef.current) {
      await keycloakRef.current.logout({
        redirectUri: window.location.origin,
      });
      return;
    }

    writeMockAuth(null);
    setAuthState({
      authenticated: false,
      token: null,
      user: null,
      mode: 'mock',
      error: null,
    });
  }, [mode, setAuthState]);

  const switchRole = useCallback(async (role: UserRole) => {
    if (mode !== 'mock') {
      return;
    }

    const nextUser = buildMockUser(role);
    writeMockAuth(nextUser);
    setAuthState({
      authenticated: true,
      token: `mock-token-${role}`,
      user: nextUser,
      mode: 'mock',
      error: null,
    });
  }, [mode, setAuthState]);

  const value = useMemo<AuthContextValue>(() => ({
    initialized,
    authenticated,
    mode,
    token,
    user,
    error,
    login,
    logout,
    switchRole,
  }), [authenticated, error, initialized, login, logout, mode, switchRole, token, user]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }

  return context;
}

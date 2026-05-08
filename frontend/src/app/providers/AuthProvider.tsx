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
import type Keycloak from 'keycloak-js';
import type { KeycloakConfig, KeycloakTokenParsed } from 'keycloak-js';
import { setAccessToken } from '../../features/auth/session';
import type { AuthContextValue, AuthMode, AuthUser, UserRole } from '../../features/auth/types';

const AuthContext = createContext<AuthContextValue | null>(null);

type ProviderProps = {
  children: ReactNode;
};

type KeycloakModule = {
  default: new (config: string | KeycloakConfig) => Keycloak;
};

type MeResponse = {
  data?: {
    id?: string;
    keycloakUserId?: string;
    email?: string;
    fullName?: string;
    roles?: string[];
    company?: {
      id?: string;
      name?: string;
      code?: string;
    };
  };
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
    companyCode: 'TEST',
  };
}

function collectRolesFromClaims(tokenParsed: KeycloakTokenParsed | undefined): string[] {
  const realmAccess = (tokenParsed as KeycloakTokenParsed & {
    realm_access?: { roles?: string[] };
  } | undefined)?.realm_access;

  const resourceAccess = (tokenParsed as KeycloakTokenParsed & {
    resource_access?: Record<string, { roles?: string[] }>;
  } | undefined)?.resource_access;

  const resourceRoles = resourceAccess
    ? Object.values(resourceAccess).flatMap((resource) => resource.roles ?? [])
    : [];

  return Array.from(new Set([...(realmAccess?.roles ?? []), ...resourceRoles]));
}

function normalizeRoles(roles: string[]): UserRole[] {
  const result = new Set<UserRole>();

  if (roles.includes('viewer')) {
    result.add('viewer');
  }
  if (roles.includes('admin')) {
    result.add('admin');
  }
  if (roles.includes('drone')) {
    result.add('drone');
  }

  if (result.size === 0) {
    result.add('viewer');
  }

  return Array.from(result);
}

function resolveRoleFromRoles(roles: string[]): UserRole {
  if (roles.includes('admin')) {
    return 'admin';
  }
  if (roles.includes('drone')) {
    return 'drone';
  }
  return 'viewer';
}

function buildUserFromKeycloak(tokenParsed: KeycloakTokenParsed | undefined): AuthUser {
  const rawRoles = collectRolesFromClaims(tokenParsed);
  const roles = normalizeRoles(rawRoles);

  return {
    id: String(tokenParsed?.sub ?? 'kc-user'),
    fullName: String(tokenParsed?.name ?? tokenParsed?.preferred_username ?? 'Keycloak User'),
    email: String(tokenParsed?.email ?? ''),
    role: resolveRoleFromRoles(rawRoles),
    roles,
    companyId: null,
    companyCode: null,
    companyName: null,
  };
}

function mergeUserProfile(baseUser: AuthUser, payload: MeResponse['data']): AuthUser {
  const profileRoles = normalizeRoles(payload?.roles ?? []);
  const effectiveRoles = profileRoles.length > 0 ? profileRoles : baseUser.roles;

  return {
    id: payload?.id ?? baseUser.id,
    fullName: payload?.fullName ?? baseUser.fullName,
    email: payload?.email ?? baseUser.email,
    role: resolveRoleFromRoles(effectiveRoles),
    roles: effectiveRoles,
    companyId: payload?.company?.id ?? baseUser.companyId ?? null,
    companyCode: payload?.company?.code ?? baseUser.companyCode ?? null,
    companyName: payload?.company?.name ?? baseUser.companyName ?? null,
  };
}

async function importKeycloak(): Promise<KeycloakModule> {
  return import('keycloak-js');
}

function hasKeycloakConfig() {
  return Boolean(
    import.meta.env.VITE_KEYCLOAK_URL &&
      import.meta.env.VITE_KEYCLOAK_REALM &&
      import.meta.env.VITE_KEYCLOAK_CLIENT_ID,
  );
}

async function fetchMe(token: string): Promise<MeResponse['data'] | null> {
  const response = await fetch('/api/v1/me', {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch /v1/me: ${response.status}`);
  }

  const json = (await response.json()) as MeResponse;
  return json.data ?? null;
}

export function AuthProvider({ children }: ProviderProps) {
  const [initialized, setInitialized] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);
  const [mode, setMode] = useState<AuthMode>('mock');
  const [token, setToken] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);
  const [error, setError] = useState<string | null>(null);
  const keycloakRef = useRef<Keycloak | null>(null);

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
      const useMocks = import.meta.env.VITE_USE_MOCKS !== 'false';

      if (!useMocks && hasKeycloakConfig()) {
        writeMockAuth(null);

        try {
          const { default: KeycloakCtor } = await importKeycloak();
          const keycloak = new KeycloakCtor({
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
            const baseUser = buildUserFromKeycloak(keycloak.tokenParsed);
            let enrichedUser = baseUser;

            setAccessToken(keycloak.token);

            try {
              const profile = await fetchMe(keycloak.token);
              if (profile) {
                enrichedUser = mergeUserProfile(baseUser, profile);
              }
            } catch (profileError) {
              console.warn('Failed to load /v1/me, falling back to token claims', profileError);
            }

            setAuthState({
              authenticated: true,
              token: keycloak.token,
              user: enrichedUser,
              mode: 'keycloak',
              error: null,
            });

            refreshIntervalId = window.setInterval(async () => {
              try {
                const refreshed = await keycloak.updateToken(30);
                if (refreshed && keycloak.token && isMounted) {
                  setToken(keycloak.token);
                  setAccessToken(keycloak.token);
                }
              } catch {
                // ignore
              }
            }, 20000);
          } else {
            setAuthState({
              authenticated: false,
              token: null,
              user: null,
              mode: 'keycloak',
              error: null,
            });
          }

          setInitialized(true);
          return;
        } catch (authError) {
          if (!isMounted) {
            return;
          }

          setAuthState({
            authenticated: false,
            token: null,
            user: null,
            mode: 'keycloak',
            error:
              authError instanceof Error
                ? authError.message
                : 'Не удалось инициализировать Keycloak',
          });

          setInitialized(true);
          return;
        }
      }

      const storedUser = readMockAuth();

      if (storedUser) {
        setAuthState({
          authenticated: true,
          token: `mock-token-${storedUser.role}`,
          user: storedUser,
          mode: 'mock',
          error: null,
        });
      } else {
        setAuthState({
          authenticated: false,
          token: null,
          user: null,
          mode: 'mock',
          error: null,
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
    if (mode === 'keycloak') {
      if (!keycloakRef.current) {
        setError('Keycloak не инициализирован');
        return;
      }

      await keycloakRef.current.login({
        redirectUri: window.location.origin,
        locale: 'ru',
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
      setAccessToken(null);
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

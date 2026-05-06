export type UserRole = 'viewer' | 'admin' | 'drone';
export type AuthMode = 'keycloak' | 'mock';

export type AuthUser = {
  id: string;
  fullName: string;
  email: string;
  role: UserRole;
  roles: UserRole[];
  companyId?: string | null;
  companyCode?: string | null;
  companyName?: string | null;
};

export type AuthContextValue = {
  initialized: boolean;
  authenticated: boolean;
  mode: AuthMode;
  token: string | null;
  user: AuthUser | null;
  error: string | null;
  login: (role?: UserRole) => Promise<void>;
  logout: () => Promise<void>;
  switchRole: (role: UserRole) => Promise<void>;
};

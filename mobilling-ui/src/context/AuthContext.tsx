import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { User, getMe, login as apiLogin, register as apiRegister, logout as apiLogout, LoginData, RegisterData } from '../api/auth';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isImpersonating: boolean;
  login: (data: LoginData) => Promise<User>;
  register: (data: RegisterData) => Promise<void>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  impersonate: (user: User, token: string) => void;
  exitImpersonation: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [isImpersonating, setIsImpersonating] = useState(() => !!localStorage.getItem('admin_token'));

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      getMe()
        .then((res) => setUser(res.data.user))
        .catch(() => localStorage.removeItem('token'))
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (data: LoginData): Promise<User> => {
    const res = await apiLogin(data);
    localStorage.setItem('token', res.data.token);
    setUser(res.data.user);
    return res.data.user;
  };

  const register = async (data: RegisterData) => {
    const res = await apiRegister(data);
    localStorage.setItem('token', res.data.token);
    setUser(res.data.user);
  };

  const logout = async () => {
    await apiLogout();
    localStorage.removeItem('token');
    localStorage.removeItem('admin_token');
    setUser(null);
    setIsImpersonating(false);
  };

  const refreshUser = async () => {
    const res = await getMe();
    setUser(res.data.user);
  };

  const impersonate = (impersonatedUser: User, token: string) => {
    // Save the super admin token
    const adminToken = localStorage.getItem('token');
    if (adminToken) {
      localStorage.setItem('admin_token', adminToken);
    }
    // Switch to impersonated user
    localStorage.setItem('token', token);
    setUser(impersonatedUser);
    setIsImpersonating(true);
  };

  const exitImpersonation = () => {
    const adminToken = localStorage.getItem('admin_token');
    if (adminToken) {
      localStorage.setItem('token', adminToken);
      localStorage.removeItem('admin_token');
      setIsImpersonating(false);
      // Reload to get the admin user back
      getMe().then((res) => setUser(res.data.user));
    }
  };

  return (
    <AuthContext.Provider value={{ user, loading, isImpersonating, login, register, logout, refreshUser, impersonate, exitImpersonation }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
}

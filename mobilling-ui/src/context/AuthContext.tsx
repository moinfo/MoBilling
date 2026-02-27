import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { User, getMe, login as apiLogin, register as apiRegister, logout as apiLogout, LoginData, RegisterData } from '../api/auth';
import { setTenantCurrency } from '../utils/formatCurrency';

type SubscriptionStatus = 'trial' | 'subscribed' | 'expired' | 'deactivated' | null;

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isImpersonating: boolean;
  permissions: string[];
  subscriptionStatus: SubscriptionStatus;
  daysRemaining: number;
  hasAccess: boolean;
  login: (data: LoginData) => Promise<User>;
  register: (data: RegisterData) => Promise<void>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  impersonate: (user: User, token: string, subStatus?: SubscriptionStatus, subDays?: number) => void;
  exitImpersonation: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [isImpersonating, setIsImpersonating] = useState(() => !!localStorage.getItem('admin_token'));
  const [permissions, setPermissions] = useState<string[]>([]);
  const [subscriptionStatus, setSubscriptionStatus] = useState<SubscriptionStatus>(null);
  const [daysRemaining, setDaysRemaining] = useState(0);

  const hasAccess = subscriptionStatus === 'trial' || subscriptionStatus === 'subscribed';

  const updateUser = (u: User | null) => {
    setUser(u);
    if (u?.tenant?.currency) setTenantCurrency(u.tenant.currency);
  };

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      getMe()
        .then((res) => {
          updateUser(res.data.user);
          setPermissions(res.data.permissions ?? []);
          setSubscriptionStatus(res.data.subscription_status ?? null);
          setDaysRemaining(res.data.days_remaining ?? 0);
        })
        .catch(() => localStorage.removeItem('token'))
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (data: LoginData): Promise<User> => {
    const res = await apiLogin(data);
    localStorage.setItem('token', res.data.token);
    updateUser(res.data.user);
    setPermissions(res.data.permissions ?? []);
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
    return res.data.user;
  };

  const register = async (data: RegisterData) => {
    const res = await apiRegister(data);
    localStorage.setItem('token', res.data.token);
    updateUser(res.data.user);
    setPermissions(res.data.permissions ?? []);
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
  };

  const logout = async () => {
    await apiLogout();
    localStorage.removeItem('token');
    localStorage.removeItem('admin_token');
    updateUser(null);
    setPermissions([]);
    setIsImpersonating(false);
    setSubscriptionStatus(null);
    setDaysRemaining(0);
  };

  const refreshUser = async () => {
    const res = await getMe();
    setUser(res.data.user);
    setPermissions(res.data.permissions ?? []);
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
  };

  const impersonate = (impersonatedUser: User, token: string, subStatus?: SubscriptionStatus, subDays?: number) => {
    // Save the super admin token
    const adminToken = localStorage.getItem('token');
    if (adminToken) {
      localStorage.setItem('admin_token', adminToken);
    }
    // Switch to impersonated user
    localStorage.setItem('token', token);
    updateUser(impersonatedUser);
    setIsImpersonating(true);
    // Set subscription state from impersonated tenant
    if (subStatus !== undefined) {
      setSubscriptionStatus(subStatus);
      setDaysRemaining(subDays ?? 0);
    }
    // Refresh permissions for the impersonated user
    getMe().then((res) => {
      setPermissions(res.data.permissions ?? []);
    });
  };

  const exitImpersonation = () => {
    const adminToken = localStorage.getItem('admin_token');
    if (adminToken) {
      localStorage.setItem('token', adminToken);
      localStorage.removeItem('admin_token');
      setIsImpersonating(false);
      // Reload to get the admin user back
      getMe().then((res) => {
        updateUser(res.data.user);
        setPermissions(res.data.permissions ?? []);
        setSubscriptionStatus(res.data.subscription_status ?? null);
        setDaysRemaining(res.data.days_remaining ?? 0);
      });
    }
  };

  return (
    <AuthContext.Provider value={{
      user, loading, isImpersonating, permissions,
      subscriptionStatus, daysRemaining, hasAccess,
      login, register, logout, refreshUser, impersonate, exitImpersonation,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
}

import { createContext, useContext, useState, useEffect, useRef, ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { notifications } from '@mantine/notifications';
import { User, UserType, getMe, login as apiLogin, register as apiRegister, logout as apiLogout, LoginData, RegisterData } from '../api/auth';
import { setTenantCurrency } from '../utils/formatCurrency';

// Auto sign-out after this many minutes with no real interaction (mouse,
// keyboard, touch, scroll) — matches the server-side backstop in
// IdleTimeout.php, but this is what actually fires while someone is sitting
// on the page: background polling (e.g. the notification bell) alone must
// never keep a truly-idle session alive, so this only resets on real input.
const IDLE_MINUTES = 15;

type SubscriptionStatus = 'trial' | 'subscribed' | 'expired' | 'deactivated' | null;

interface AuthContextType {
  user: User | null;
  userType: UserType | null;
  loading: boolean;
  isImpersonating: boolean;
  isImpersonatingClient: boolean;
  permissions: string[];
  subscriptionStatus: SubscriptionStatus;
  daysRemaining: number;
  hasAccess: boolean;
  login: (data: LoginData) => Promise<{ user: User; userType: UserType }>;
  register: (data: RegisterData) => Promise<void>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  impersonate: (user: User, token: string, subStatus?: SubscriptionStatus, subDays?: number) => Promise<void>;
  exitImpersonation: () => void;
  /** Staff "Login as client" — a distinct session swap from tenant impersonation above. */
  impersonateClient: (clientUser: unknown, token: string, permissions: string[]) => void;
  exitClientImpersonation: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const idleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastResetRef = useRef(0);
  const [user, setUser] = useState<User | null>(null);
  const [userType, setUserType] = useState<UserType | null>(() => {
    return (localStorage.getItem('user_type') as UserType) || null;
  });
  const [loading, setLoading] = useState(true);
  const [isImpersonating, setIsImpersonating] = useState(() => !!localStorage.getItem('admin_token'));
  const [isImpersonatingClient, setIsImpersonatingClient] = useState(() => !!localStorage.getItem('impersonate_return_token'));
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
          setUserType(res.data.user_type ?? 'tenant');
          setPermissions(res.data.permissions ?? []);
          setSubscriptionStatus(res.data.subscription_status ?? null);
          setDaysRemaining(res.data.days_remaining ?? 0);
        })
        .catch(() => {
          localStorage.removeItem('token');
          localStorage.removeItem('user_type');
        })
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (data: LoginData) => {
    const res = await apiLogin(data);
    localStorage.setItem('token', res.data.token);
    localStorage.setItem('user_type', res.data.user_type);
    updateUser(res.data.user);
    setUserType(res.data.user_type);
    setPermissions(res.data.permissions ?? []);
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
    return { user: res.data.user, userType: res.data.user_type };
  };

  const register = async (data: RegisterData) => {
    const res = await apiRegister(data);
    localStorage.setItem('token', res.data.token);
    localStorage.setItem('user_type', 'tenant');
    updateUser(res.data.user);
    setUserType('tenant');
    setPermissions(res.data.permissions ?? []);
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
  };

  const logout = async () => {
    await apiLogout();
    localStorage.removeItem('token');
    localStorage.removeItem('user_type');
    localStorage.removeItem('admin_token');
    localStorage.removeItem('impersonate_return_token');
    localStorage.removeItem('impersonate_return_user');
    localStorage.removeItem('impersonate_return_user_type');
    updateUser(null);
    setUserType(null);
    setPermissions([]);
    setIsImpersonating(false);
    setIsImpersonatingClient(false);
    setSubscriptionStatus(null);
    setDaysRemaining(0);
  };

  const refreshUser = async () => {
    const res = await getMe();
    setUser(res.data.user);
    setUserType(res.data.user_type ?? 'tenant');
    setPermissions(res.data.permissions ?? []);
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
  };

  const impersonate = async (impersonatedUser: User, token: string, subStatus?: SubscriptionStatus, subDays?: number) => {
    // Only save admin_token if not already impersonating (preserve the original super admin token)
    if (!localStorage.getItem('admin_token')) {
      const adminToken = localStorage.getItem('token');
      if (adminToken) {
        localStorage.setItem('admin_token', adminToken);
      }
    }
    localStorage.setItem('token', token);
    localStorage.setItem('user_type', 'tenant');
    updateUser(impersonatedUser);
    setUserType('tenant');
    setIsImpersonating(true);
    if (subStatus !== undefined && subStatus !== null) {
      setSubscriptionStatus(subStatus);
      setDaysRemaining(subDays ?? 0);
    }
    const res = await getMe();
    setPermissions(res.data.permissions ?? []);
    // Always sync subscription status from getMe so we reflect the impersonated user's tenant
    setSubscriptionStatus(res.data.subscription_status ?? null);
    setDaysRemaining(res.data.days_remaining ?? 0);
  };

  const exitImpersonation = () => {
    const adminToken = localStorage.getItem('admin_token');
    if (adminToken) {
      localStorage.setItem('token', adminToken);
      localStorage.removeItem('admin_token');
      setIsImpersonating(false);
      getMe().then((res) => {
        updateUser(res.data.user);
        setUserType(res.data.user_type ?? 'tenant');
        setPermissions(res.data.permissions ?? []);
        setSubscriptionStatus(res.data.subscription_status ?? null);
        setDaysRemaining(res.data.days_remaining ?? 0);
      });
    }
  };

  // Staff "Login as client": a session swap distinct from tenant-admin
  // impersonation above — different user model (ClientUser, not User), so it
  // gets its own return-token slot rather than reusing admin_token, and its
  // own banner (rendered in PortalShell, since AppShell never mounts here).
  const impersonateClient = (clientUser: unknown, token: string, clientPermissions: string[]) => {
    const currentToken = localStorage.getItem('token');
    const currentUser = localStorage.getItem('user');
    const currentUserType = localStorage.getItem('user_type');
    if (currentToken) localStorage.setItem('impersonate_return_token', currentToken);
    if (currentUser) localStorage.setItem('impersonate_return_user', currentUser);
    if (currentUserType) localStorage.setItem('impersonate_return_user_type', currentUserType);

    localStorage.setItem('token', token);
    localStorage.setItem('user_type', 'client');
    localStorage.setItem('user', JSON.stringify(clientUser));
    updateUser(clientUser as User);
    setUserType('client');
    setPermissions(clientPermissions);
    setIsImpersonatingClient(true);
  };

  const exitClientImpersonation = () => {
    const returnToken = localStorage.getItem('impersonate_return_token');
    const returnUser = localStorage.getItem('impersonate_return_user');
    const returnUserType = localStorage.getItem('impersonate_return_user_type');
    if (!returnToken) return;

    localStorage.setItem('token', returnToken);
    if (returnUserType) localStorage.setItem('user_type', returnUserType);
    if (returnUser) localStorage.setItem('user', returnUser);
    localStorage.removeItem('impersonate_return_token');
    localStorage.removeItem('impersonate_return_user');
    localStorage.removeItem('impersonate_return_user_type');
    setIsImpersonatingClient(false);

    // Full reload: the admin's own permissions/subscription state need a
    // fresh boot, same as exitImpersonation does via getMe() — but the
    // client-portal bundle and admin bundle share no cached query state
    // worth preserving here, so a hard navigation is simpler and safer.
    window.location.href = returnUserType === 'tenant' ? '/dashboard' : '/portal-users';
  };

  // Idle auto sign-out: only real interaction resets the clock. A background
  // refetchInterval (notification bell, dashboards, etc.) firing every N
  // seconds must NOT count as activity, or an unattended-but-open tab would
  // never time out — so this listens for actual input events only.
  useEffect(() => {
    if (!user) {
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current);
      return;
    }

    const handleIdle = () => {
      const wasClient = userType === 'client';
      // Clear local state immediately — don't wait on a network round-trip
      // to reflect "signed out" while idle. Best-effort tell the server too.
      apiLogout().catch(() => {});
      localStorage.removeItem('token');
      localStorage.removeItem('user_type');
      localStorage.removeItem('admin_token');
      localStorage.removeItem('impersonate_return_token');
      localStorage.removeItem('impersonate_return_user');
      localStorage.removeItem('impersonate_return_user_type');
      updateUser(null);
      setUserType(null);
      setPermissions([]);
      setIsImpersonating(false);
      setIsImpersonatingClient(false);
      setSubscriptionStatus(null);
      setDaysRemaining(0);

      notifications.show({
        title: 'Signed out',
        message: `You were signed out after ${IDLE_MINUTES} minutes of inactivity.`,
        color: 'orange',
      });
      navigate(wasClient ? '/portal/login' : '/login');
    };

    const armTimer = () => {
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current);
      idleTimerRef.current = setTimeout(handleIdle, IDLE_MINUTES * 60 * 1000);
    };

    // Throttled — mousemove/scroll can fire dozens of times a second, and
    // this only needs millisecond-scale precision, not that.
    const onActivity = () => {
      const now = Date.now();
      if (now - lastResetRef.current < 1000) return;
      lastResetRef.current = now;
      armTimer();
    };

    const events: (keyof WindowEventMap)[] = ['mousedown', 'mousemove', 'keydown', 'scroll', 'touchstart', 'click'];
    events.forEach((e) => window.addEventListener(e, onActivity, { passive: true }));
    armTimer();

    return () => {
      events.forEach((e) => window.removeEventListener(e, onActivity));
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, userType]);

  return (
    <AuthContext.Provider value={{
      user, userType, loading, isImpersonating, isImpersonatingClient, permissions,
      subscriptionStatus, daysRemaining, hasAccess,
      login, register, logout, refreshUser, impersonate, exitImpersonation,
      impersonateClient, exitClientImpersonation,
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

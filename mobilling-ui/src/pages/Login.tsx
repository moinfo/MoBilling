import { useState } from 'react';
import {
  TextInput, PasswordInput, Button, Stack, Group, Text, Anchor, PinInput, Alert, Divider,
  useMantineColorScheme, useComputedColorScheme,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useNavigate, Link, useLocation } from 'react-router-dom';
import {
  IconAlertCircle, IconArrowLeft, IconAt, IconBrandWhatsapp, IconChartBar, IconCheck,
  IconEye, IconEyeOff, IconFileInvoice, IconLoader2, IconLock, IconMoon, IconShield,
  IconShieldCheck, IconSun,
} from '@tabler/icons-react';
import { useAuth } from '../context/AuthContext';
import { safeNext } from '../utils/safeNext';
import { verifyAndRegisterPortal } from '../api/auth';
import '../theme/marketing.css';
import styles from './Login.module.css';

const BENEFITS = [
  { icon: IconFileInvoice, color: '#56a9e8', text: 'Create invoices, quotations & proformas in seconds' },
  { icon: IconChartBar, color: '#4fd189', text: 'Track payments, bills & statutory obligations' },
  { icon: IconShield, color: '#ffd24a', text: 'Secure multi-tenant platform with role-based access' },
];

const STATS = [
  { value: '500+', label: 'BUSINESSES' },
  { value: '50K+', label: 'INVOICES' },
  { value: '99.9%', label: 'UPTIME' },
];

/** Accepts an email (an `@` with something before it) or a dialable number. */
const PHONE_RE = /^[+0-9 ()-]{9,}$/;

function validateCredentials(identifier: string, password: string): string | null {
  if (!identifier.trim()) return 'Enter your email address or phone number.';
  const looksLikeEmail = identifier.indexOf('@') > 0;
  if (!looksLikeEmail && !PHONE_RE.test(identifier.trim())) {
    return 'That does not look like an email address or phone number.';
  }
  if (password.length < 6) return 'Your password must be at least 6 characters.';
  return null;
}

export default function Login() {
  const { login, completeTwoFactorLogin } = useAuth();
  const navigate = useNavigate();
  // Set when the visitor came from an /order/* link — see OrderRoute.
  const next = safeNext(useLocation().search);
  const { toggleColorScheme } = useMantineColorScheme();
  const scheme = useComputedColorScheme('light');

  // Sign-in form. Held as plain state rather than Mantine's useForm because the
  // design specifies one banner for the first failure, not per-field errors.
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // OTP setup state (portal clients completing their first sign-in)
  const [otpMode, setOtpMode] = useState(false);
  const [otpEmail, setOtpEmail] = useState('');
  const [otpClientName, setOtpClientName] = useState('');
  const [otpValue, setOtpValue] = useState('');
  const [otpLoading, setOtpLoading] = useState(false);
  const [otpDone, setOtpDone] = useState(false);

  // 2FA (authenticator app) login-challenge state
  const [twoFaChallengeId, setTwoFaChallengeId] = useState<string | null>(null);
  const [twoFaCode, setTwoFaCode] = useState('');
  const [twoFaRecoveryCode, setTwoFaRecoveryCode] = useState('');
  const [twoFaUseRecovery, setTwoFaUseRecovery] = useState(false);
  const [twoFaLoading, setTwoFaLoading] = useState(false);

  const setupForm = useForm({
    initialValues: { name: '', password: '', password_confirmation: '', phone: '' },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Required'),
      password: (v) => (v.length >= 8 ? null : 'Min 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  const goAfterLogin = (userType: string, role?: string) => {
    if (userType === 'client') {
      // Came from an /order/* link? Return to the plan they picked.
      navigate(next ?? '/portal/dashboard');
    } else {
      navigate(role === 'super_admin' ? '/admin/tenants' : '/dashboard');
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const invalid = validateCredentials(identifier, password);
    if (invalid) {
      setError(invalid);
      return;
    }

    setLoading(true);
    setError('');
    try {
      const result = await login({ identifier, password });
      if ('requires_2fa' in result) {
        setTwoFaChallengeId(result.challenge_id);
        return;
      }
      goAfterLogin(result.userType, result.user.role);
    } catch (err: any) {
      // 449 means the portal client exists but has never set a password.
      if (err.response?.status === 449 && err.response?.data?.requires_otp) {
        setOtpEmail(identifier);
        setOtpClientName(err.response.data.client_name || '');
        setOtpMode(true);
        notifications.show({
          title: 'Verification required',
          message: 'A verification code has been sent to your email.',
          color: 'blue',
        });
        return;
      }
      setError(err.response?.data?.message || 'We could not sign you in. Check your details and try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleSetupAccount = async (values: typeof setupForm.values) => {
    if (otpValue.length !== 6) {
      notifications.show({ title: 'Error', message: 'Enter the 6-digit code', color: 'red' });
      return;
    }
    setOtpLoading(true);
    try {
      const res = await verifyAndRegisterPortal({
        email: otpEmail,
        otp: otpValue,
        name: values.name,
        password: values.password,
        password_confirmation: values.password_confirmation,
        phone: values.phone || undefined,
      });
      localStorage.setItem('token', res.data.token);
      localStorage.setItem('user_type', 'client');
      setOtpDone(true);
      setTimeout(() => { window.location.href = next ?? '/portal/dashboard'; }, 1500);
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || err.response?.data?.errors?.otp?.[0] || 'Verification failed',
        color: 'red',
      });
    } finally {
      setOtpLoading(false);
    }
  };

  const handleTwoFactorVerify = async () => {
    if (!twoFaChallengeId) return;
    setTwoFaLoading(true);
    try {
      const { user, userType } = await completeTwoFactorLogin(
        twoFaChallengeId,
        twoFaUseRecovery ? { recovery_code: twoFaRecoveryCode.trim() } : { code: twoFaCode },
      );
      goAfterLogin(userType, user.role);
    } catch (err: any) {
      notifications.show({
        title: 'Verification failed',
        message: err.response?.data?.message || err.response?.data?.errors?.code?.[0] || 'That code was not correct.',
        color: 'red',
      });
      setTwoFaCode('');
    } finally {
      setTwoFaLoading(false);
    }
  };

  return (
    <div className="mkt">
      <div className={styles.root}>
        {/* ── Brand panel ── */}
        <aside className={styles.brandPanel}>
          <div className={styles.brandRule} />
          <div className={styles.glowA} />
          <div className={styles.glowB} />

          <div className={styles.brandTop}>
            <Link className={styles.brand} to="/">
              <img src="/moinfotech-logo.png" alt="" />
              <span className={styles.wordmark}>MoBilling</span>
            </Link>
          </div>

          <div className={styles.brandMiddle}>
            <div className={styles.pill}>
              <span className={styles.pillDot} />
              BUILT FOR EAST AFRICA
            </div>
            <h1 className={styles.title}>Billing &amp; statutory management made simple</h1>
            <p className={styles.blurb}>
              Streamline your invoicing, track payments and stay compliant — all in one platform.
            </p>
            <div className={styles.benefits}>
              {BENEFITS.map((b) => (
                <div key={b.text} className={styles.benefit}>
                  <span className={styles.benefitTile}>
                    <b.icon size={20} color={b.color} />
                  </span>
                  {b.text}
                </div>
              ))}
            </div>
            <div className={styles.statStrip}>
              {STATS.map((s, i) => (
                <div key={s.label} style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
                  {i > 0 && <span className={styles.statDivider} />}
                  <div>
                    <div className={styles.statValue}>{s.value}</div>
                    <div className={styles.statLabel}>{s.label}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className={styles.brandBottom}>
            <span>© {new Date().getFullYear()} MOINFOTECH. ALL RIGHTS RESERVED.</span>
            <span>INFO@MOINFO.CO.TZ</span>
          </div>
        </aside>

        {/* ── Form panel ── */}
        <main className={styles.formPanel}>
          <div className={styles.formHeader}>
            <Link className={styles.backLink} to="/">
              <IconArrowLeft size={16} />
              Back home
            </Link>
            <button
              type="button"
              className={styles.iconBtn}
              onClick={toggleColorScheme}
              aria-label={scheme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'}
            >
              {scheme === 'dark' ? <IconSun size={20} /> : <IconMoon size={20} />}
            </button>
          </div>

          <div className={styles.stage}>
            <div className={styles.mobileBrand}>
              <Link className={styles.brand} to="/" style={{ color: 'var(--mk-text)' }}>
                <img src="/moinfotech-logo.png" alt="" />
                <span className={styles.wordmark}>MoBilling</span>
              </Link>
            </div>

            {twoFaChallengeId ? (
              <>
                <h2 className={styles.formTitle}>Two-factor verification</h2>
                <p className={styles.formSub}>
                  {twoFaUseRecovery
                    ? 'Enter one of your recovery codes.'
                    : 'Enter the 6-digit code from your authenticator app.'}
                </p>

                <div className={styles.subPanel}>
                  <Stack gap="md" align="center">
                    {!twoFaUseRecovery ? (
                      <PinInput
                        length={6} type="number" size="md" value={twoFaCode}
                        onChange={setTwoFaCode} oneTimeCode onComplete={handleTwoFactorVerify}
                      />
                    ) : (
                      <TextInput
                        w="100%" label="Recovery code" placeholder="XXXX-XXXX"
                        value={twoFaRecoveryCode}
                        onChange={(e) => setTwoFaRecoveryCode(e.currentTarget.value)}
                      />
                    )}
                    <button
                      type="button"
                      className={styles.submit}
                      disabled={twoFaLoading || (twoFaUseRecovery ? !twoFaRecoveryCode.trim() : twoFaCode.length !== 6)}
                      onClick={handleTwoFactorVerify}
                    >
                      {twoFaLoading ? 'Verifying…' : 'Verify'}
                    </button>
                  </Stack>
                </div>

                <button
                  type="button"
                  className={styles.centerLink}
                  onClick={() => {
                    setTwoFaUseRecovery(!twoFaUseRecovery);
                    setTwoFaCode('');
                    setTwoFaRecoveryCode('');
                  }}
                >
                  {twoFaUseRecovery ? 'Use authenticator code instead' : 'Lost your device? Use a recovery code'}
                </button>
                <button
                  type="button"
                  className={styles.centerLink}
                  onClick={() => {
                    setTwoFaChallengeId(null);
                    setTwoFaCode('');
                    setTwoFaRecoveryCode('');
                    setTwoFaUseRecovery(false);
                  }}
                >
                  Back to sign in
                </button>
              </>
            ) : !otpMode ? (
              <>
                <h2 className={styles.formTitle}>Welcome back</h2>
                <p className={styles.formSub}>Sign in to continue to your dashboard.</p>

                {error && (
                  <div className={styles.errorBanner} role="alert">
                    <IconAlertCircle size={18} style={{ flexShrink: 0, marginTop: 1 }} />
                    <span>{error}</span>
                  </div>
                )}

                <form onSubmit={handleSubmit} noValidate>
                  <div className={styles.field}>
                    <div className={styles.labelRow}>
                      <label className={styles.label} htmlFor="identifier">
                        Email or phone<span className={styles.required}>*</span>
                      </label>
                    </div>
                    <div className={styles.control}>
                      <span className={styles.controlIcon}><IconAt size={20} /></span>
                      <input
                        id="identifier"
                        name="identifier"
                        autoComplete="username"
                        placeholder="you@company.com or 0712 345 678"
                        value={identifier}
                        onChange={(e) => { setIdentifier(e.currentTarget.value); setError(''); }}
                      />
                    </div>
                  </div>

                  <div className={styles.field}>
                    <div className={styles.labelRow}>
                      <label className={styles.label} htmlFor="password">
                        Password<span className={styles.required}>*</span>
                      </label>
                      <Link className={styles.forgot} to="/forgot-password">Forgot password?</Link>
                    </div>
                    <div className={styles.control}>
                      <span className={styles.controlIcon}><IconLock size={20} /></span>
                      <input
                        id="password"
                        name="password"
                        type={showPassword ? 'text' : 'password'}
                        autoComplete="current-password"
                        placeholder="Your password"
                        value={password}
                        onChange={(e) => { setPassword(e.currentTarget.value); setError(''); }}
                      />
                      <button
                        type="button"
                        className={styles.reveal}
                        onClick={() => setShowPassword((v) => !v)}
                        aria-label={showPassword ? 'Hide password' : 'Show password'}
                      >
                        {showPassword ? <IconEyeOff size={20} /> : <IconEye size={20} />}
                      </button>
                    </div>
                  </div>

                  <button type="submit" className={styles.submit} disabled={loading}>
                    {loading && <span className={styles.spinner}><IconLoader2 size={20} /></span>}
                    {loading ? 'Signing in…' : 'Sign in'}
                  </button>
                </form>

                <div className={styles.divider}>OR</div>

                {/* No magic-link login exists; this deep-links to the real
                    WhatsApp one-time-code flow the API already supports. */}
                <Link className={styles.secondary} to="/forgot-password?channel=whatsapp">
                  <IconBrandWhatsapp size={20} color="#2fae60" />
                  Get a WhatsApp sign-in code
                </Link>

                <p className={styles.formFooter}>
                  Don&apos;t have an account? <Link to="/register">Create one free</Link>
                </p>
              </>
            ) : otpDone ? (
              <div className={styles.subPanel}>
                <Stack gap="md" align="center" py="lg">
                  <IconCheck size={44} color="#2fae60" />
                  <h2 className={styles.formTitle} style={{ margin: 0 }}>Account created</h2>
                  <Text c="dimmed" ta="center">Redirecting to your portal…</Text>
                </Stack>
              </div>
            ) : (
              <>
                <h2 className={styles.formTitle}>Set up your account</h2>
                <p className={styles.formSub}>Verify your email and create your portal password.</p>

                <div className={styles.subPanel}>
                  <form onSubmit={setupForm.onSubmit(handleSetupAccount)}>
                    <Stack gap="md">
                      <Alert color="blue" variant="light">
                        Code sent to <b>{otpEmail}</b>
                        {otpClientName && <> for <b>{otpClientName}</b></>}
                      </Alert>

                      <div>
                        <Text size="sm" fw={500} mb={4}>Verification code</Text>
                        <Group justify="center">
                          <PinInput length={6} type="number" size="md" value={otpValue} onChange={setOtpValue} />
                        </Group>
                      </div>

                      <Divider />

                      <TextInput label="Your name" required {...setupForm.getInputProps('name')} />
                      <TextInput label="Phone" {...setupForm.getInputProps('phone')} />
                      <PasswordInput label="Set password" required {...setupForm.getInputProps('password')} />
                      <PasswordInput label="Confirm password" required {...setupForm.getInputProps('password_confirmation')} />

                      <Button fullWidth type="submit" size="md" loading={otpLoading}>
                        Create account
                      </Button>

                      <Anchor size="sm" ta="center" onClick={() => { setOtpMode(false); setOtpValue(''); }}>
                        Back to sign in
                      </Anchor>
                    </Stack>
                  </form>
                </div>
              </>
            )}
          </div>

          <div className={styles.panelNote}>
            <IconShieldCheck size={16} />
            Protected by 2FA and role-based access control
          </div>
        </main>
      </div>
    </div>
  );
}

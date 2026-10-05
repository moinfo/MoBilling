import { useEffect, useRef, useState } from 'react';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { safeNext } from '../../utils/safeNext';
import { requestPortalOtp, verifyAndRegisterPortal } from '../../api/auth';
import { useBranding } from '../../branding';
import styles from './PortalRegister.module.css';
import wl from './WhiteLabelAuth.module.css';

const SunIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
  </svg>
);
const MoonIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <path d="M21 12.6A9 9 0 1 1 11.4 3a7 7 0 0 0 9.6 9.6Z" />
  </svg>
);
const InfoIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="9" /><path d="M12 16v-5M12 8h.01" />
  </svg>
);
const CheckIcon = () => (
  <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 12.5 10 17 19 7" />
  </svg>
);
const BackIcon = () => (
  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
    <path d="M19 12H5M11 18l-6-6 6-6" />
  </svg>
);

function PinInput({ value, onChange, s }: { value: string; onChange: (v: string) => void; s: Record<string, string> }) {
  const refs = useRef<(HTMLInputElement | null)[]>([]);
  const digits = value.split('').concat(Array(6).fill('')).slice(0, 6);

  const setDigit = (i: number, d: string) => {
    const next = digits.slice();
    next[i] = d;
    onChange(next.join('').trimEnd());
    if (d && i < 5) refs.current[i + 1]?.focus();
  };

  return (
    <div className={s.pinRow}>
      {digits.map((d, i) => (
        <input
          key={i}
          ref={(el) => { refs.current[i] = el; }}
          className={s.pinInput}
          inputMode="numeric"
          maxLength={1}
          value={d}
          autoFocus={i === 0}
          onChange={(e) => setDigit(i, e.currentTarget.value.replace(/\D/g, '').slice(-1))}
          onKeyDown={(e) => { if (e.key === 'Backspace' && !d && i > 0) refs.current[i - 1]?.focus(); }}
          onPaste={(e) => {
            const text = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
            if (text) { e.preventDefault(); onChange(text); refs.current[Math.min(text.length, 5)]?.focus(); }
          }}
        />
      ))}
    </div>
  );
}

export default function PortalRegister() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const next = safeNext(window.location.search);
  const branding = useBranding();
  const brandName = branding.branded ? (branding.name ?? 'Client Area') : 'Moinfotech';
  const brandLogo = branding.branded ? branding.logo_url : null;
  const initial = brandName.trim().charAt(0).toUpperCase() || '?';
  // On a white-label domain, "back" goes to the reseller's own storefront
  // root ("/", WhiteLabelLanding) — never to Moinfotech's own site, which
  // the reseller's customers should never see.
  const backHref = branding.branded ? '/' : 'https://moinfo.co.tz';
  const s: Record<string, string> = branding.branded ? wl : styles;

  const THEME_KEY = 'wl_theme';
  const [theme, setTheme] = useState<'light' | 'dark' | null>(() => {
    try { const s = localStorage.getItem(THEME_KEY); return s === 'light' || s === 'dark' ? s : null; } catch { return null; }
  });
  const [systemDark, setSystemDark] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    setSystemDark(mq.matches);
    const onChange = (e: MediaQueryListEvent) => setSystemDark(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);
  const isDark = theme ? theme === 'dark' : systemDark;
  const toggleTheme = () => {
    const cur = theme ?? (systemDark ? 'dark' : 'light');
    const nextTheme = cur === 'dark' ? 'light' : 'dark';
    setTheme(nextTheme);
    try { localStorage.setItem(THEME_KEY, nextTheme); } catch { /* ignore */ }
  };

  const [step, setStep] = useState<'details' | 'verify' | 'done'>('details');
  const [otpValue, setOtpValue] = useState('');
  const [loading, setLoading] = useState(false);
  const [clientName, setClientName] = useState<string | null>(null);
  const [isNewClient, setIsNewClient] = useState(true);
  const [needsDetails, setNeedsDetails] = useState(false);

  const form = useForm({
    initialValues: {
      name: '', company: '', email: searchParams.get('email') ?? '',
      phone: '', address: '', password: '', password_confirmation: '',
    },
    validate: {
      name: (v) => (v.trim().length > 1 ? null : 'Your full name is required'),
      email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'A valid email is required'),
      password: (v) => (v.length >= 8 ? null : 'Minimum 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  useEffect(() => {
    if (searchParams.get('email') && searchParams.get('sent')) {
      setStep('verify');
      setIsNewClient(false);
      setNeedsDetails(true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const sendOtp = async (silent = false) => {
    setLoading(true);
    try {
      const res = await requestPortalOtp(form.values.email.trim().toLowerCase());
      if (res.data.has_account) {
        notifications.show({
          title: 'You already have an account',
          message: 'Please sign in instead — use "Forgot password" if needed.',
          color: 'blue',
        });
        navigate(`/portal/login${next ? `?next=${encodeURIComponent(next)}` : ''}`);
        return;
      }
      setClientName(res.data.client_name ?? null);
      setIsNewClient(res.data.new_client ?? !res.data.client_name);
      setStep('verify');
      if (!silent) notifications.show({ message: 'Verification code sent to your email.', color: 'green' });
    } catch (e: any) {
      notifications.show({
        message: e?.response?.data?.message ?? e?.response?.data?.errors?.email?.[0] ?? 'Could not send the verification code.',
        color: 'red',
      });
    } finally {
      setLoading(false);
    }
  };

  const handleDetails = form.onSubmit(() => sendOtp());

  const handleVerify = async () => {
    if (otpValue.length !== 6) {
      notifications.show({ message: 'Enter the 6-digit code from your email.', color: 'red' });
      return;
    }
    if (!form.values.name.trim() || form.values.password.length < 8
      || form.values.password !== form.values.password_confirmation) {
      notifications.show({ message: 'Fill in your name and a matching password (min 8 characters) below.', color: 'red' });
      return;
    }
    setLoading(true);
    try {
      const res = await verifyAndRegisterPortal({
        email: form.values.email.trim().toLowerCase(),
        otp: otpValue,
        name: form.values.name.trim(),
        password: form.values.password,
        password_confirmation: form.values.password_confirmation,
        phone: form.values.phone || undefined,
        company: form.values.company || undefined,
        address: form.values.address || undefined,
      });
      localStorage.setItem('token', res.data.token);
      localStorage.setItem('user_type', 'client');
      setStep('done');
      setTimeout(() => { window.location.href = next ?? '/portal/dashboard'; }, 1500);
    } catch (e: any) {
      notifications.show({
        message: e?.response?.data?.message ?? e?.response?.data?.errors?.otp?.[0] ?? 'Verification failed.',
        color: 'red',
      });
    } finally {
      setLoading(false);
    }
  };

  const err = (field: keyof typeof form.values) => (form.errors as any)[field] as string | undefined;

  const stepNo = step === 'details' ? 1 : step === 'verify' ? 2 : 3;
  const dotClass = (n: number) => `${s.stepDot}${stepNo >= n ? ` ${s.stepDotOn}` : ''}`;
  return (
    <div className={s.page} data-theme={theme ?? undefined}>
      {branding.branded ? (
        <aside className={wl.panel}>
          <Link className={wl.brandRow} to={backHref} aria-label={brandName}>
            {brandLogo ? <img src={brandLogo} alt="" className={wl.logo} /> : <span className={wl.mark} aria-hidden="true">{initial}</span>}
            <span className={wl.brandName}>{brandName}</span>
          </Link>

          <div className={wl.hero}>
            <h1 className={wl.heroTitle}>Your business online, today.</h1>
            <p className={wl.heroText}>Create your account, then finish your order. Most orders set themselves up automatically.</p>
            <div className={wl.panelBox}>
              <div className={wl.panelLabel}>What happens next</div>
              <ul className={wl.perks}>
                {['Confirm your email with a 6-digit code', 'Add your details and set a password', 'Order a domain or hosting and pay online'].map((line) => (
                  <li key={line}>
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#3fcf8e" strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round">
                      <path d="M5 12.5 10 17 19 7" />
                    </svg>
                    <span>{line}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <Link className={wl.panelBack} to={backHref}>← Back to {brandName}</Link>
        </aside>
      ) : (
        <div className={s.topbar}>
          <a className={s.back} href={backHref}>← Back to moinfo.co.tz</a>
          <button type="button" className={s.themeToggle} onClick={toggleTheme}
            aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}>
            {isDark ? <SunIcon /> : <MoonIcon />}
          </button>
        </div>
      )}

      <div className={s.wrap}>
        <div className={s.inner}>
        {branding.branded ? (
          <div className={s.stepper}>
            <span className={dotClass(1)}>1</span> Account
            <span className={s.stepRule} />
            <span className={dotClass(2)}>2</span> Verify email
            <span className={s.stepRule} />
            <span className={dotClass(3)}>3</span> Live
          </div>
        ) : (
          <div className={s.brandRow}>
            {brandLogo ? <img src={brandLogo} alt="" className={s.logo} /> : <span className={s.avatar}>{initial}</span>}
            <span className={s.brandName}>{brandName}</span>
          </div>
        )}

        {step === 'done' ? (
          <div className={s.card}>
            <div className={s.doneWrap}>
              <div className={s.doneIcon}><CheckIcon /></div>
              <div className={s.title}>Welcome aboard!</div>
              <p className={s.subtitle}>Your account is ready — taking you to your client area…</p>
            </div>
          </div>
        ) : step === 'details' ? (
          <>
            <h1 className={s.title}>Create an account</h1>
            <p className={s.subtitle}>Register to order hosting &amp; domains, pay invoices and get support.</p>

            <form className={s.card} onSubmit={handleDetails}>
              <div className={s.grid2}>
                <div className={s.field}>
                  <label className={s.label}>Full name</label>
                  <input className={s.input} required {...form.getInputProps('name', { withError: false })} />
                  {err('name') && <span className={s.error}>{err('name')}</span>}
                </div>
                <div className={s.field}>
                  <label className={s.label}>Company <span className={s.labelOptional}>(optional)</span></label>
                  <input className={s.input} placeholder="Business or organisation" {...form.getInputProps('company', { withError: false })} />
                </div>
              </div>
              <div className={s.grid2}>
                <div className={s.field}>
                  <label className={s.label}>Email address</label>
                  <input className={s.input} required type="email" {...form.getInputProps('email', { withError: false })} />
                  {err('email') && <span className={s.error}>{err('email')}</span>}
                </div>
                <div className={s.field}>
                  <label className={s.label}>Phone <span className={s.labelOptional}>(optional)</span></label>
                  <input className={s.input} placeholder="0712 345 678" {...form.getInputProps('phone', { withError: false })} />
                </div>
              </div>
              <div className={s.field}>
                <label className={s.label}>Address <span className={s.labelOptional}>(optional)</span></label>
                <input className={s.input} placeholder="Street, city" {...form.getInputProps('address', { withError: false })} />
              </div>
              <div className={s.grid2}>
                <div className={s.field}>
                  <label className={s.label}>Password</label>
                  <input className={s.input} required type="password" {...form.getInputProps('password', { withError: false })} />
                  {err('password') && <span className={s.error}>{err('password')}</span>}
                </div>
                <div className={s.field}>
                  <label className={s.label}>Confirm password</label>
                  <input className={s.input} required type="password" {...form.getInputProps('password_confirmation', { withError: false })} />
                  {err('password_confirmation') && <span className={s.error}>{err('password_confirmation')}</span>}
                </div>
              </div>

              <button className={s.submit} type="submit" disabled={loading}>
                {loading ? 'Sending…' : 'Continue — verify email'}
              </button>
            </form>

            <p className={s.footNote}>
              Already registered? <Link to="/portal/login">Sign in</Link>
            </p>
          </>
        ) : (
          <>
            <h1 className={s.title}>Verify your email</h1>
            <p className={s.subtitle}>Enter the 6-digit code we sent to <b>{form.values.email}</b></p>

            <div className={s.card}>
              {!isNewClient && (
                <div className={s.alert}>
                  <InfoIcon />
                  <span>Welcome back{clientName ? <>, <b>{clientName}</b></> : ''}! We found your existing
                    client account — verify your email and set a password to activate portal access.</span>
                </div>
              )}

              <PinInput value={otpValue} onChange={setOtpValue} s={s} />

              {needsDetails && (
                <>
                  <div className={s.field}>
                    <label className={s.label}>Your name</label>
                    <input className={s.input} required {...form.getInputProps('name', { withError: false })} />
                  </div>
                  <div className={s.field}>
                    <label className={s.label}>Phone <span className={s.labelOptional}>(optional)</span></label>
                    <input className={s.input} {...form.getInputProps('phone', { withError: false })} />
                  </div>
                  <div className={s.grid2}>
                    <div className={s.field}>
                      <label className={s.label}>Set password</label>
                      <input className={s.input} required type="password" {...form.getInputProps('password', { withError: false })} />
                    </div>
                    <div className={s.field}>
                      <label className={s.label}>Confirm password</label>
                      <input className={s.input} required type="password" {...form.getInputProps('password_confirmation', { withError: false })} />
                    </div>
                  </div>
                </>
              )}

              <button className={s.submit} type="button" disabled={loading} onClick={handleVerify}>
                {loading ? 'Creating…' : 'Create account'}
              </button>

              <div className={s.verifyLinks}>
                <a className={s.link} onClick={() => { setStep('details'); setOtpValue(''); }}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}><BackIcon /> Edit details</span>
                </a>
                <a className={s.link} onClick={() => sendOtp()}>Resend code</a>
              </div>
            </div>
          </>
        )}
        </div>
      </div>
    </div>
  );
}

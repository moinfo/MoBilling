import { useState } from 'react';
import { useMantineColorScheme, useComputedColorScheme, ActionIcon } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../../context/AuthContext';
import { useBranding } from '../../branding';
import { useNavigate, Link, useLocation } from 'react-router-dom';
import { safeNext } from '../../utils/safeNext';
import { IconSun, IconMoon } from '@tabler/icons-react';
import classes from './PortalLogin.module.css';

/**
 * The four things a customer signs in to do. The mono keys on the left mirror
 * the design's ledger feel — they are labels, not decoration.
 */
const PERKS = [
  { k: 'DOM', t: 'Domains', d: 'Register, renew and manage your .tz domains, nameservers and EPP codes.' },
  { k: 'WEB', t: 'Hosting', d: 'One-click cPanel login, disk and bandwidth usage, upgrades.' },
  { k: 'PAY', t: 'Billing', d: 'Invoices, statements and receipts. Pay by mobile money or card.' },
  { k: 'SUP', t: 'Support', d: 'Open a ticket and track it, 24/7, with a team in your time zone.' },
];

export default function PortalLogin() {
  const { login } = useAuth();
  const navigate = useNavigate();
  // Set when the visitor came from an /order/* link — see OrderRoute.
  const next = safeNext(useLocation().search);
  const { toggleColorScheme } = useMantineColorScheme();
  const isDark = useComputedColorScheme('dark') === 'dark';
  const branding = useBranding();
  const brandName = branding.branded ? (branding.name ?? 'Client Area') : 'Moinfotech';
  const backHref = branding.branded && branding.website ? branding.website : 'https://moinfo.co.tz';

  const [showPw, setShowPw] = useState(false);
  const [remember, setRemember] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const form = useForm({
    initialValues: { identifier: '', password: '' },
    validate: {
      identifier: (v) => (v.length > 0 ? null : 'Email or phone is required'),
      password: (v) => (v.length > 0 ? null : 'Password is required'),
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    setSubmitting(true);
    try {
      const { user, userType } = await login(values);
      if (userType === 'client') {
        navigate(next ?? '/portal/dashboard');
      } else {
        navigate(user.role === 'super_admin' ? '/admin/tenants' : '/dashboard');
      }
    } catch (err: any) {
      // Imported WHMCS client without a portal account yet → claim it via OTP.
      if (err.response?.status === 449 && err.response?.data?.requires_otp) {
        notifications.show({
          title: 'Verification required',
          message: 'A verification code has been sent to your email — finish setting up your account.',
          color: 'blue',
        });
        navigate(
          `/portal/register?email=${encodeURIComponent(values.identifier)}&sent=1`
          + (next ? `&next=${encodeURIComponent(next)}` : '')
        );
        return;
      }
      notifications.show({
        title: 'Login failed',
        message: err.response?.data?.message || 'Invalid credentials',
        color: 'red',
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className={classes.page}>
      {/* ── Brand panel ─────────────────────────────────────────────── */}
      <div className={classes.brand}>
        <div className={classes.brandGrid} aria-hidden="true" />
        <div className={classes.brandOrb} aria-hidden="true" />

        <div className={classes.brandRow}>
          <img src="/moinfotech-logo.png" alt="" height={40} />
          <span className={classes.brandLockup}>
            <span className={classes.brandName}>
              Moinfo<span className={classes.brandNameAccent}>Tech</span>
            </span>
            <span className={classes.brandKicker}>TCRA REGISTRAR · TZ</span>
          </span>
        </div>

        <div className={classes.brandMiddle}>
          <h1 className={classes.brandHeadline}>Everything you run with us, in one place.</h1>
          <div className={classes.perks}>
            {PERKS.map((p) => (
              <div key={p.k} className={classes.perk}>
                <span className={classes.perkKey}>{p.k}</span>
                <span className={classes.perkBody}>
                  <span className={classes.perkTitle}>{p.t}</span>
                  <span className={classes.perkDesc}>{p.d}</span>
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className={classes.brandFoot}>
          <div className={classes.tiles}>
            <div className={classes.tile}>
              <div className={classes.tileLabel}>
                <span className={classes.tileDot} />
                PLATFORM STATUS
              </div>
              <div className={classes.tileValue}>All systems operational</div>
            </div>
            {/* The design shows a measured "99.98% / 30 DAYS". Nothing actually
                measures that, so we state the guarantee the site advertises. */}
            <div className={classes.tile}>
              <div className={classes.tileLabel}>UPTIME GUARANTEE</div>
              <div className={classes.tileValue}>99.9%</div>
            </div>
          </div>
          <div className={classes.copyright}>
            © {new Date().getFullYear()} MOINFOTECH COMPANY LIMITED
          </div>
        </div>
      </div>

      {/* ── Form column ─────────────────────────────────────────────── */}
      <div className={classes.formCol}>
        <div className={classes.topBar}>
          <a className={classes.back} href={backHref}>
            ← Back to {backHref.replace(/^https?:\/\//, '')}
          </a>
          <div className={classes.topRight}>
            <ActionIcon
              variant="default"
              size="lg"
              onClick={toggleColorScheme}
              aria-label="Toggle colour scheme"
            >
              {isDark ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
            <a
              className={classes.help}
              href="https://wa.me/255689011111"
              target="_blank"
              rel="noopener noreferrer"
            >
              Need help?
            </a>
          </div>
        </div>

        <div className={classes.formWrap}>
          <form className={classes.form} onSubmit={form.onSubmit(handleSubmit)}>
            <div className={classes.intro}>
              <span className={classes.eyebrow}>CLIENT AREA</span>
              <h2 className={classes.heading}>Sign in</h2>
              <p className={classes.sub}>Manage domains, hosting, invoices and tickets.</p>
            </div>

            <div className={classes.fields}>
              <div className={classes.field}>
                <label className={classes.label} htmlFor="identifier">
                  <span>EMAIL OR PHONE</span>
                  <span className={classes.labelHint}>REQUIRED</span>
                </label>
                <input
                  id="identifier"
                  className={classes.input}
                  placeholder="you@company.com or 0712345678"
                  autoComplete="username"
                  {...form.getInputProps('identifier')}
                />
              </div>

              <div className={classes.field}>
                <label className={classes.label} htmlFor="password">
                  <span>PASSWORD</span>
                  <Link className={classes.forgot} to="/forgot-password">FORGOT?</Link>
                </label>
                <div className={classes.pwWrap}>
                  <input
                    id="password"
                    className={`${classes.input} ${classes.pwInput}`}
                    type={showPw ? 'text' : 'password'}
                    placeholder="Your password"
                    autoComplete="current-password"
                    {...form.getInputProps('password')}
                  />
                  <button
                    type="button"
                    className={classes.pwToggle}
                    onClick={() => setShowPw((v) => !v)}
                    aria-label={showPw ? 'Hide password' : 'Show password'}
                  >
                    {showPw ? 'HIDE' : 'SHOW'}
                  </button>
                </div>
              </div>

              <div className={classes.row}>
                <button
                  type="button"
                  className={classes.remember}
                  onClick={() => setRemember((v) => !v)}
                  aria-pressed={remember}
                >
                  <span className={`${classes.box} ${remember ? classes.boxOn : ''}`}>
                    {remember ? '✓' : ''}
                  </span>
                  Keep me signed in
                </button>
                <span className={classes.security}>TLS 1.3 · 2FA READY</span>
              </div>

              <button className={classes.submit} type="submit" disabled={submitting}>
                {submitting ? 'Signing in…' : 'Sign in'}
              </button>
            </div>

            <div className={classes.quickLinks}>
              <a
                className={classes.quick}
                href="https://moinfo.co.tz:2083"
                target="_blank"
                rel="noopener noreferrer"
              >
                <span className={classes.quickLabel}>CPANEL</span>
                <span className={classes.quickText}>Manage files &amp; databases</span>
              </a>
              <a
                className={classes.quick}
                href="https://moinfo.co.tz:2096"
                target="_blank"
                rel="noopener noreferrer"
              >
                <span className={classes.quickLabel}>WEBMAIL</span>
                <span className={classes.quickText}>Read your email</span>
              </a>
            </div>

            <p className={classes.newHere}>
              New to {brandName}?{' '}
              <Link to={`/portal/register${next ? `?next=${encodeURIComponent(next)}` : ''}`}>
                Create an account
              </Link>
            </p>
          </form>
        </div>

        <div className={classes.legal}>
          <span>© {new Date().getFullYear()} MOINFOTECH</span>
          <span>
            <a href="https://moinfo.co.tz/privacy">PRIVACY</a>
            {' · '}
            <a href="https://moinfo.co.tz/terms">TERMS</a>
          </span>
        </div>
      </div>
    </div>
  );
}

import { useState } from 'react';
import { useMantineColorScheme, useComputedColorScheme, ActionIcon } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../../context/AuthContext';
import { useBranding } from '../../branding';
import { useNavigate, Link, useLocation } from 'react-router-dom';
import { safeNext } from '../../utils/safeNext';
import { useLanguage } from '../../i18n/LanguageContext';
import { IconSun, IconMoon } from '@tabler/icons-react';
import classes from './PortalLogin.module.css';
import wl from './WhiteLabelAuth.module.css';

/**
 * The four things a customer signs in to do. The mono keys on the left mirror
 * the design's ledger feel — they are labels, not decoration.
 */
const PERKS = [
  { k: 'DOM', titleKey: 'login.perkDomains', descKey: 'login.perkDomainsDesc' },
  { k: 'WEB', titleKey: 'login.perkHosting', descKey: 'login.perkHostingDesc' },
  { k: 'PAY', titleKey: 'login.perkBilling', descKey: 'login.perkBillingDesc' },
  { k: 'SUP', titleKey: 'login.perkSupport', descKey: 'login.perkSupportDesc' },
];

export default function PortalLogin() {
  const { login, completeTwoFactorLogin } = useAuth();
  const navigate = useNavigate();
  // Set when the visitor came from an /order/* link — see OrderRoute.
  const next = safeNext(useLocation().search);
  const { toggleColorScheme } = useMantineColorScheme();
  const isDark = useComputedColorScheme('dark') === 'dark';
  const branding = useBranding();
  const { t } = useLanguage();
  const brandName = branding.branded ? (branding.name ?? 'Client Area') : 'Moinfotech';
  // On a white-label domain, "back" goes to the reseller's own storefront
  // root ("/", WhiteLabelLanding) — never to Moinfotech's own site, which
  // the reseller's customers should never see.
  const backHref = branding.branded ? '/' : 'https://moinfo.co.tz';

  const [showPw, setShowPw] = useState(false);
  const [remember, setRemember] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  // 2FA (authenticator app) login-challenge state
  const [twoFaChallengeId, setTwoFaChallengeId] = useState<string | null>(null);
  const [twoFaCode, setTwoFaCode] = useState('');
  const [twoFaRecoveryCode, setTwoFaRecoveryCode] = useState('');
  const [twoFaUseRecovery, setTwoFaUseRecovery] = useState(false);
  const [twoFaSubmitting, setTwoFaSubmitting] = useState(false);

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
      const result = await login(values);
      if ('requires_2fa' in result) {
        setTwoFaChallengeId(result.challenge_id);
        return;
      }
      const { user, userType } = result;
      if (userType === 'client') {
        navigate(next ?? '/portal/dashboard');
      } else {
        navigate(user.role === 'super_admin' ? '/admin/tenants' : '/dashboard');
      }
    } catch (err: any) {
      // Same identifier+password also matches a staff account — but they're
      // on the PORTAL login page, so there's no real ambiguity: they want
      // their client account. Resolve it silently instead of asking.
      if (err.response?.status === 300 && err.response?.data?.requires_account_choice) {
        try {
          const result = await login({ ...values, account_type: 'client' });
          if ('requires_2fa' in result) {
            setTwoFaChallengeId(result.challenge_id);
            return;
          }
          navigate(next ?? '/portal/dashboard');
        } catch (err2: any) {
          notifications.show({
            title: t('login.failed'),
            message: err2.response?.data?.message || t('login.invalid'),
            color: 'red',
          });
        }
        return;
      }
      // Known client (e.g. imported from WHMCS) with no portal password set
      // yet — they already have a real account, they just need to verify
      // (email, SMS, or WhatsApp) and set a password, not "sign up".
      if (err.response?.status === 449 && err.response?.data?.requires_otp) {
        notifications.show({
          title: t('login.verifyTitle'),
          message: t('login.verifyMessage'),
          color: 'blue',
        });
        navigate(
          `/portal/forgot-password?identifier=${encodeURIComponent(values.identifier)}`
          + (next ? `&next=${encodeURIComponent(next)}` : '')
        );
        return;
      }
      notifications.show({
        title: t('login.failed'),
        message: err.response?.data?.message || t('login.invalid'),
        color: 'red',
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handleTwoFactorVerify = async () => {
    if (!twoFaChallengeId) return;
    setTwoFaSubmitting(true);
    try {
      const { user, userType } = await completeTwoFactorLogin(
        twoFaChallengeId,
        twoFaUseRecovery ? { recovery_code: twoFaRecoveryCode.trim() } : { code: twoFaCode }
      );
      if (userType === 'client') {
        navigate(next ?? '/portal/dashboard');
      } else {
        navigate(user.role === 'super_admin' ? '/admin/tenants' : '/dashboard');
      }
    } catch (err: any) {
      notifications.show({
        title: t('login.failed'),
        message: err.response?.data?.message || 'That code was not correct.',
        color: 'red',
      });
      setTwoFaCode('');
    } finally {
      setTwoFaSubmitting(false);
    }
  };

  // A white-label reseller's sign-in uses the Lucham Cloud design (navy brand
  // panel + white form column, see WhiteLabelAuth.module.css). The two-column
  // "Control Room" layout below is Moinfotech's own default portal only.
  if (branding.branded) {
    const initial = brandName.trim().charAt(0).toUpperCase() || '?';
    const year = new Date().getFullYear();
    const registerHref = `/portal/register${next ? `?next=${encodeURIComponent(next)}` : ''}`;
    return (
      <div className={wl.page}>
        <aside className={wl.panel}>
          <Link className={wl.brandRow} to={backHref} aria-label={brandName}>
            {branding.logo_url
              ? <img src={branding.logo_url} alt="" className={wl.logo} />
              : <span className={wl.mark} aria-hidden="true">{initial}</span>}
            <span className={wl.brandName}>{brandName}</span>
          </Link>

          <div className={wl.hero}>
            <h1 className={wl.heroTitle}>Welcome back.</h1>
            <p className={wl.heroText}>Manage your domains, hosting and business email from one account.</p>
            <ul className={wl.perks}>
              {['Renew or upgrade any plan yourself', 'Add mailboxes and subdomains in seconds', 'Reach local support from your dashboard'].map((line) => (
                <li key={line}>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#3fcf8e" strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round">
                    <path d="M5 12.5 10 17 19 7" />
                  </svg>
                  <span>{line}</span>
                </li>
              ))}
            </ul>
          </div>

          <Link className={wl.panelBack} to={backHref}>← Back to {brandName}</Link>
        </aside>

        <main className={wl.wrap}>
          <div className={wl.inner}>
            {twoFaChallengeId ? (
              <>
                <h2 className={wl.title}>Two-factor verification</h2>
                <p className={wl.subtitle}>
                  {twoFaUseRecovery ? 'Enter one of your recovery codes.' : 'Enter the 6-digit code from your authenticator app.'}
                </p>
                <div className={wl.form}>
                  <div className={wl.field}>
                    <label className={wl.label} htmlFor="wl-2fa">{twoFaUseRecovery ? 'Recovery code' : 'Authentication code'}</label>
                    <input
                      id="wl-2fa"
                      className={wl.input}
                      placeholder={twoFaUseRecovery ? 'XXXX-XXXX' : '123456'}
                      inputMode={twoFaUseRecovery ? 'text' : 'numeric'}
                      autoFocus
                      value={twoFaUseRecovery ? twoFaRecoveryCode : twoFaCode}
                      onChange={(e) => (twoFaUseRecovery ? setTwoFaRecoveryCode(e.target.value) : setTwoFaCode(e.target.value))}
                      onKeyDown={(e) => e.key === 'Enter' && handleTwoFactorVerify()}
                    />
                  </div>
                  <button className={wl.submit} type="button" disabled={twoFaSubmitting} onClick={handleTwoFactorVerify}>
                    {twoFaSubmitting ? t('login.submitting') : 'Verify'}
                  </button>
                </div>
                <p className={wl.footNote}>
                  <a className={wl.link} onClick={() => { setTwoFaUseRecovery(!twoFaUseRecovery); setTwoFaCode(''); setTwoFaRecoveryCode(''); }}>
                    {twoFaUseRecovery ? 'Use authenticator code instead' : 'Lost your device? Use a recovery code'}
                  </a>
                </p>
                <p className={wl.footNote}>
                  <a className={wl.link} onClick={() => { setTwoFaChallengeId(null); setTwoFaCode(''); setTwoFaRecoveryCode(''); setTwoFaUseRecovery(false); }}>
                    Back to sign in
                  </a>
                </p>
              </>
            ) : (
              <>
                <h2 className={wl.title}>Sign in</h2>
                <p className={wl.subtitle}>
                  New to {brandName}? <Link className={wl.link} to={registerHref}>Create an account</Link>
                </p>

                <form className={wl.form} onSubmit={form.onSubmit(handleSubmit)}>
                  <div className={wl.field}>
                    <label className={wl.label} htmlFor="wl-identifier">{t('login.identifier')}</label>
                    <input id="wl-identifier" className={wl.input} placeholder={t('login.identifierPlaceholder')} autoComplete="username"
                      {...form.getInputProps('identifier', { withError: false })} />
                    {form.errors.identifier && <span className={wl.error}>{form.errors.identifier}</span>}
                  </div>

                  <div className={wl.field}>
                    <div className={wl.labelRow}>
                      <label className={wl.label} htmlFor="wl-password">{t('login.password')}</label>
                      <Link className={wl.link} style={{ fontSize: 13 }} to="/portal/forgot-password">{t('login.forgot')}</Link>
                    </div>
                    <div className={wl.pwWrap}>
                      <input
                        id="wl-password"
                        className={`${wl.input} ${wl.pwInput}`}
                        type={showPw ? 'text' : 'password'}
                        placeholder={t('login.passwordPlaceholder')}
                        autoComplete="current-password"
                        {...form.getInputProps('password', { withError: false })}
                      />
                      <button type="button" className={wl.eye} onClick={() => setShowPw((v) => !v)}
                        aria-label={showPw ? 'Hide password' : 'Show password'}>
                        {showPw ? t('login.hide') : t('login.show')}
                      </button>
                    </div>
                    {form.errors.password && <span className={wl.error}>{form.errors.password}</span>}
                  </div>

                  <label className={wl.checkRow}>
                    <input type="checkbox" className={wl.checkbox} checked={remember} onChange={(e) => setRemember(e.currentTarget.checked)} />
                    {t('login.remember')}
                  </label>

                  <button className={wl.submit} type="submit" disabled={submitting}>
                    {submitting ? t('login.submitting') : t('login.submit')}
                  </button>
                </form>

                {branding.email && (
                  <p className={wl.footSmall}>
                    Trouble signing in? <a className={wl.link} href={`mailto:${branding.email}`}>Contact support</a>
                  </p>
                )}
              </>
            )}
          </div>
        </main>

        <footer className={wl.footer}>© {year} {brandName}</footer>
      </div>
    );
  }

  return (
    <div className={classes.page}>
      {/* ── Brand panel ─────────────────────────────────────────────── */}
      <div className={classes.brand}>
        <div className={classes.brandGrid} aria-hidden="true" />
        <div className={classes.brandOrb} aria-hidden="true" />

        <div className={classes.brandRow}>
          {(!branding.branded || branding.logo_url) && (
            <img src={branding.branded ? branding.logo_url! : '/moinfotech-logo.png'} alt="" height={40} />
          )}
          <span className={classes.brandLockup}>
            <span className={classes.brandName}>
              {branding.branded ? brandName : <>Moinfo<span className={classes.brandNameAccent}>Tech</span></>}
            </span>
            {!branding.branded && <span className={classes.brandKicker}>TCRA REGISTRAR · TZ</span>}
          </span>
        </div>

        <div className={classes.brandMiddle}>
          <h1 className={classes.brandHeadline}>{t('login.brandHeadline')}</h1>
          <div className={classes.perks}>
            {PERKS.map((p) => (
              <div key={p.k} className={classes.perk}>
                <span className={classes.perkKey}>{p.k}</span>
                <span className={classes.perkBody}>
                  <span className={classes.perkTitle}>{t(p.titleKey)}</span>
                  <span className={classes.perkDesc}>{t(p.descKey)}</span>
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
                {t('login.platformStatus')}
              </div>
              <div className={classes.tileValue}>{t('login.operational')}</div>
            </div>
            {/* The design shows a measured "99.98% / 30 DAYS". Nothing actually
                measures that, so we state the guarantee the site advertises. */}
            <div className={classes.tile}>
              <div className={classes.tileLabel}>{t('login.uptimeGuarantee')}</div>
              <div className={classes.tileValue}>99.9%</div>
            </div>
          </div>
          <div className={classes.copyright}>
            © {new Date().getFullYear()} {branding.branded ? brandName.toUpperCase() : 'MOINFOTECH COMPANY LIMITED'}
          </div>
        </div>
      </div>

      {/* ── Form column ─────────────────────────────────────────────── */}
      <div className={classes.formCol}>
        <div className={classes.topBar}>
          {branding.branded ? (
            <Link className={classes.back} to={backHref}>← {t('login.backTo')} {t('login.backToHome')}</Link>
          ) : (
            <a className={classes.back} href={backHref}>← {t('login.backTo')} {backHref.replace(/^https?:\/\//, '')}</a>
          )}
          <div className={classes.topRight}>
            <ActionIcon
              variant="default"
              size="lg"
              onClick={toggleColorScheme}
              aria-label="Toggle colour scheme"
            >
              {isDark ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
            {!branding.branded && (
              <a
                className={classes.help}
                href="https://wa.me/255689011111"
                target="_blank"
                rel="noopener noreferrer"
              >
                {t('login.needHelp')}
              </a>
            )}
          </div>
        </div>

        <div className={classes.formWrap}>
          {twoFaChallengeId ? (
            <div className={classes.form}>
              <div className={classes.intro}>
                <span className={classes.eyebrow}>{t('login.eyebrow')}</span>
                <h2 className={classes.heading}>Two-Factor Verification</h2>
                <p className={classes.sub}>
                  {twoFaUseRecovery ? 'Enter one of your recovery codes.' : 'Enter the 6-digit code from your authenticator app.'}
                </p>
              </div>

              <div className={classes.fields}>
                <div className={classes.field}>
                  <label className={classes.label} htmlFor="twofa-code">
                    <span>{twoFaUseRecovery ? 'Recovery code' : 'Authentication code'}</span>
                  </label>
                  <input
                    id="twofa-code"
                    className={classes.input}
                    placeholder={twoFaUseRecovery ? 'XXXX-XXXX' : '123456'}
                    inputMode={twoFaUseRecovery ? 'text' : 'numeric'}
                    autoFocus
                    value={twoFaUseRecovery ? twoFaRecoveryCode : twoFaCode}
                    onChange={(e) => (twoFaUseRecovery ? setTwoFaRecoveryCode(e.target.value) : setTwoFaCode(e.target.value))}
                    onKeyDown={(e) => e.key === 'Enter' && handleTwoFactorVerify()}
                  />
                </div>

                <button className={classes.submit} type="button" disabled={twoFaSubmitting}
                  onClick={handleTwoFactorVerify}>
                  {twoFaSubmitting ? t('login.submitting') : 'Verify'}
                </button>
              </div>

              <p className={classes.newHere}>
                <Link to="#" onClick={(e) => {
                  e.preventDefault();
                  setTwoFaUseRecovery(!twoFaUseRecovery);
                  setTwoFaCode('');
                  setTwoFaRecoveryCode('');
                }}>
                  {twoFaUseRecovery ? 'Use authenticator code instead' : 'Lost your device? Use a recovery code'}
                </Link>
              </p>
              <p className={classes.newHere}>
                <Link to="#" onClick={(e) => {
                  e.preventDefault();
                  setTwoFaChallengeId(null);
                  setTwoFaCode('');
                  setTwoFaRecoveryCode('');
                  setTwoFaUseRecovery(false);
                }}>
                  Back to Sign in
                </Link>
              </p>
            </div>
          ) : (
          <form className={classes.form} onSubmit={form.onSubmit(handleSubmit)}>
            <div className={classes.intro}>
              <span className={classes.eyebrow}>{t('login.eyebrow')}</span>
              <h2 className={classes.heading}>{t('login.heading')}</h2>
              <p className={classes.sub}>{t('login.sub')}</p>
            </div>

            <div className={classes.fields}>
              <div className={classes.field}>
                <label className={classes.label} htmlFor="identifier">
                  <span>{t('login.identifier')}</span>
                  <span className={classes.labelHint}>{t('login.required')}</span>
                </label>
                <input
                  id="identifier"
                  className={classes.input}
                  placeholder={t('login.identifierPlaceholder')}
                  autoComplete="username"
                  {...form.getInputProps('identifier')}
                />
              </div>

              <div className={classes.field}>
                <label className={classes.label} htmlFor="password">
                  <span>{t('login.password')}</span>
                  <Link className={classes.forgot} to="/portal/forgot-password">{t('login.forgot')}</Link>
                </label>
                <div className={classes.pwWrap}>
                  <input
                    id="password"
                    className={`${classes.input} ${classes.pwInput}`}
                    type={showPw ? 'text' : 'password'}
                    placeholder={t('login.passwordPlaceholder')}
                    autoComplete="current-password"
                    {...form.getInputProps('password')}
                  />
                  <button
                    type="button"
                    className={classes.pwToggle}
                    onClick={() => setShowPw((v) => !v)}
                    aria-label={showPw ? 'Hide password' : 'Show password'}
                  >
                    {showPw ? t('login.hide') : t('login.show')}
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
                  {t('login.remember')}
                </button>
                <span className={classes.security}>{t('login.security')}</span>
              </div>

              <button className={classes.submit} type="submit" disabled={submitting}>
                {submitting ? t('login.submitting') : t('login.submit')}
              </button>
            </div>

            <p className={classes.newHere}>
              {t('login.newHere')} {brandName}?{' '}
              <Link to={`/portal/register${next ? `?next=${encodeURIComponent(next)}` : ''}`}>
                {t('login.createAccount')}
              </Link>
            </p>
          </form>
          )}
        </div>

        <div className={classes.legal}>
          <span>© {new Date().getFullYear()} {branding.branded ? brandName.toUpperCase() : 'MOINFOTECH'}</span>
          {!branding.branded && (
            <span>
              <a href="https://moinfo.co.tz/privacy">{t('login.privacy')}</a>
              {' · '}
              <a href="https://moinfo.co.tz/terms">{t('login.terms')}</a>
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

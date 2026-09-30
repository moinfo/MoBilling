import { useEffect, useState } from 'react';
import { useMantineColorScheme, useComputedColorScheme, ActionIcon } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { safeNext } from '../../utils/safeNext';
import { useBranding } from '../../branding';
import { useLanguage } from '../../i18n/LanguageContext';
import { IconSun, IconMoon, IconCheck, IconInfoCircle, IconUserPlus, IconMail, IconBrandWhatsapp } from '@tabler/icons-react';
import { forgotPassword, verifyResetOtp, resetPassword } from '../../api/auth';
import classes from './PortalLogin.module.css';
import own from './PortalForgotPassword.module.css';
import reg from './PortalRegister.module.css';

/**
 * Portal-branded account recovery — same OTP flow as the staff /forgot-password
 * page, but living at its own URL under /portal so client traffic never shares
 * a route with the internal admin tool, and the Control Room visual language
 * (this page reuses PortalLogin's shell) carries all the way through.
 */
type Step = 'request' | 'verify' | 'reset' | 'done';

export default function PortalForgotPassword() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  // Arriving from a failed login for a known client (no portal password set
  // yet, e.g. WHMCS-imported) — prefill what they already typed, and carry
  // through the ?next= they were originally headed to (an /order/* link etc.).
  const prefillIdentifier = searchParams.get('identifier') ?? '';
  const next = safeNext(window.location.search);
  const { toggleColorScheme } = useMantineColorScheme();
  const isDark = useComputedColorScheme('dark') === 'dark';
  const branding = useBranding();
  const { t } = useLanguage();
  const brandName = branding.branded ? (branding.name ?? 'Client Area') : 'Moinfotech';
  // On a white-label domain, "back" goes to the reseller's own storefront
  // root ("/", WhiteLabelLanding) — never to Moinfotech's own site, which
  // the reseller's customers should never see.
  const backHref = branding.branded ? '/' : 'https://moinfo.co.tz';

  // Same localStorage key as the storefront/login/register pages, so a
  // reseller's dark/light choice carries over across the whole flow.
  const THEME_KEY = 'wl_theme';
  const [wlTheme, setWlTheme] = useState<'light' | 'dark' | null>(() => {
    try { const s = localStorage.getItem(THEME_KEY); return s === 'light' || s === 'dark' ? s : null; } catch { return null; }
  });
  const [systemDark, setSystemDark] = useState(false);
  useEffect(() => {
    if (!branding.branded) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    setSystemDark(mq.matches);
    const onChange = (e: MediaQueryListEvent) => setSystemDark(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, [branding.branded]);
  const wlIsDark = wlTheme ? wlTheme === 'dark' : systemDark;
  const toggleWlTheme = () => {
    const cur = wlTheme ?? (systemDark ? 'dark' : 'light');
    const nextTheme = cur === 'dark' ? 'light' : 'dark';
    setWlTheme(nextTheme);
    try { localStorage.setItem(THEME_KEY, nextTheme); } catch { /* ignore */ }
  };

  const [step, setStep] = useState<Step>('request');
  const [loading, setLoading] = useState(false);
  // If we arrived with a prefilled phone (not an email), default to WhatsApp.
  const [channel, setChannel] = useState<'email' | 'whatsapp'>(
    prefillIdentifier && !prefillIdentifier.includes('@') ? 'whatsapp' : 'email'
  );
  const [identifier, setIdentifier] = useState('');
  const [contactHint, setContactHint] = useState('');
  const [otp, setOtp] = useState('');
  const [isRegistration, setIsRegistration] = useState(false);
  const [clientName, setClientName] = useState('');

  const requestForm = useForm({
    initialValues: { identifier: prefillIdentifier },
    validate: { identifier: (v) => (v.length > 0 ? null : 'Email or phone is required') },
  });

  const resetForm = useForm({
    initialValues: { password: '', password_confirmation: '' },
    validate: {
      password: (v) => (v.length >= 8 ? null : 'Min 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  const handleRequest = async (values: typeof requestForm.values) => {
    setLoading(true);
    try {
      const res = await forgotPassword(values.identifier, channel);
      setIdentifier(values.identifier);
      setContactHint(res.data.email_hint || '');
      setIsRegistration(!!res.data.requires_registration);
      setStep('verify');
      notifications.show({ title: t('forgot.codeSent'), message: res.data.message, color: 'green' });
    } catch (err: any) {
      const msg = err.response?.data?.message || err.response?.data?.errors?.identifier?.[0] || t('forgot.somethingWrong');
      notifications.show({ title: t('forgot.error'), message: msg, color: 'red' });
    } finally {
      setLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (otp.length !== 6) {
      notifications.show({ title: t('forgot.error'), message: t('forgot.enterCode'), color: 'red' });
      return;
    }
    setLoading(true);
    try {
      const res = await verifyResetOtp({ identifier, otp });
      setIsRegistration(!!res.data.requires_registration);
      if (res.data.client_name) setClientName(res.data.client_name);
      setStep('reset');
      notifications.show({ title: t('forgot.verified'), message: res.data.message, color: 'green' });
    } catch (err: any) {
      const msg = err.response?.data?.message || err.response?.data?.errors?.otp?.[0] || t('forgot.verifyFailed');
      notifications.show({ title: t('forgot.error'), message: msg, color: 'red' });
    } finally {
      setLoading(false);
    }
  };

  const handleReset = async (values: typeof resetForm.values) => {
    setLoading(true);
    try {
      const res = await resetPassword({
        identifier, otp,
        password: values.password,
        password_confirmation: values.password_confirmation,
      });

      if (isRegistration && res.data.token) {
        localStorage.setItem('token', res.data.token);
        localStorage.setItem('user_type', res.data.user_type || 'client');
        notifications.show({ title: 'Welcome!', message: 'Portal account created successfully.', color: 'green' });
        navigate(next ?? '/portal/dashboard');
        return;
      }

      setStep('done');
    } catch (err: any) {
      const msg = err.response?.data?.message || err.response?.data?.errors?.otp?.[0]
        || err.response?.data?.errors?.name?.[0] || t('forgot.resetFailed');
      notifications.show({ title: t('forgot.error'), message: msg, color: 'red' });
    } finally {
      setLoading(false);
    }
  };

  // A white-label reseller's recovery flow matches the storefront's own
  // design language (WhiteLabelLanding / PortalRegister / PortalLogin) —
  // the "Control Room" layout below is Moinfotech's own default portal only.
  if (branding.branded) {
    const initial = brandName.trim().charAt(0).toUpperCase() || '?';
    return (
      <div className={reg.page} data-theme={wlTheme ?? undefined}>
        <div className={reg.topbar}>
          <Link className={reg.back} to={backHref}>← {t('login.backTo')} {t('login.backToHome')}</Link>
          <button type="button" className={reg.themeToggle} onClick={toggleWlTheme}
            aria-label={wlIsDark ? 'Switch to light mode' : 'Switch to dark mode'}>
            {wlIsDark ? <IconSun size={16} /> : <IconMoon size={16} />}
          </button>
        </div>

        <div className={reg.wrap}>
          <div className={reg.brandRow}>
            {branding.logo_url ? <img src={branding.logo_url} alt="" className={reg.logo} /> : <span className={reg.avatar}>{initial}</span>}
            <span className={reg.brandName}>{brandName}</span>
          </div>

          {step === 'request' && (
            <>
              <h1 className={reg.title}>{prefillIdentifier ? 'Welcome back' : t('forgot.reqHeading')}</h1>
              <p className={reg.subtitle}>
                {prefillIdentifier
                  ? 'We found your account — verify it below to set up portal access. No need to sign up again.'
                  : t('forgot.reqSub')}
              </p>
              <form className={reg.card} onSubmit={requestForm.onSubmit(handleRequest)}>
                <div className={reg.channelToggle}>
                  <button type="button" className={`${reg.channelBtn} ${channel === 'email' ? reg.channelBtnActive : ''}`} onClick={() => setChannel('email')}>
                    <IconMail size={16} /> {t('forgot.viaEmail')}
                  </button>
                  <button type="button" className={`${reg.channelBtn} ${channel === 'whatsapp' ? reg.channelBtnActive : ''}`} onClick={() => setChannel('whatsapp')}>
                    <IconBrandWhatsapp size={16} /> {t('forgot.viaWhatsapp')}
                  </button>
                </div>
                <div className={reg.field}>
                  <label className={reg.label}>{channel === 'email' ? t('forgot.emailLabel') : t('forgot.phoneLabel')}</label>
                  <input className={reg.input}
                    placeholder={channel === 'email' ? t('forgot.emailPlaceholder') : t('forgot.phonePlaceholder')}
                    autoComplete={channel === 'email' ? 'email' : 'tel'}
                    inputMode={channel === 'email' ? 'email' : 'tel'}
                    {...requestForm.getInputProps('identifier', { withError: false })} />
                </div>
                <button className={reg.submit} type="submit" disabled={loading}>
                  {loading ? t('forgot.reqSubmitting') : t('forgot.reqSubmit')}
                </button>
              </form>
              <p className={reg.footNote}>
                {t('forgot.rememberPassword')}{' '}
                <Link to={`/portal/login${next ? `?next=${encodeURIComponent(next)}` : ''}`}>{t('forgot.backToSignin')}</Link>
              </p>
            </>
          )}

          {step === 'verify' && (
            <>
              <h1 className={reg.title}>{t('forgot.verifyHeading')}</h1>
              <p className={reg.subtitle}>{t('forgot.verifySub')}</p>
              <div className={reg.card}>
                <div className={reg.alert}>
                  <IconInfoCircle size={16} style={{ flexShrink: 0, marginTop: 1 }} />
                  <span>{t('forgot.codeSentTo')} {contactHint || identifier}</span>
                </div>
                <div className={reg.field}>
                  <label className={reg.label}>{t('forgot.verifyLabel')}</label>
                  <input
                    className={reg.otpInput}
                    inputMode="numeric"
                    maxLength={6}
                    autoFocus
                    value={otp}
                    onChange={(e) => setOtp(e.currentTarget.value.replace(/\D/g, '').slice(0, 6))}
                  />
                </div>
                <button className={reg.submit} type="button" disabled={loading} onClick={handleVerifyOtp}>
                  {loading ? t('forgot.verifySubmitting') : t('forgot.verifySubmit')}
                </button>
                <p className={`${reg.footNote} ${reg.center}`}>
                  <a className={reg.link} onClick={() => { setStep('request'); setOtp(''); }}>{t('forgot.useDifferent')}</a>
                </p>
              </div>
            </>
          )}

          {step === 'reset' && (
            <>
              <h1 className={reg.title}>{isRegistration ? t('forgot.registerHeading') : t('forgot.resetHeading')}</h1>
              <p className={reg.subtitle}>{isRegistration ? t('forgot.registerSub') : t('forgot.resetSub')}</p>
              <form className={reg.card} onSubmit={resetForm.onSubmit(handleReset)}>
                <div className={reg.alert}>
                  {isRegistration ? <IconUserPlus size={16} style={{ flexShrink: 0, marginTop: 1 }} /> : <IconCheck size={16} style={{ flexShrink: 0, marginTop: 1 }} />}
                  <span>
                    {isRegistration
                      ? `Setting up portal access for ${clientName || identifier}`
                      : `${t('forgot.codeSentTo')} ${contactHint || identifier}`}
                  </span>
                </div>
                <div className={reg.field}>
                  <label className={reg.label}>{t('forgot.newPassword')}</label>
                  <input className={reg.input} type="password" {...resetForm.getInputProps('password', { withError: false })} />
                </div>
                <div className={reg.field}>
                  <label className={reg.label}>{t('forgot.confirmPassword')}</label>
                  <input className={reg.input} type="password" {...resetForm.getInputProps('password_confirmation', { withError: false })} />
                </div>
                <button className={reg.submit} type="submit" disabled={loading}>
                  {loading ? t('forgot.submitting') : (isRegistration ? t('forgot.registerSubmit') : t('forgot.resetSubmit'))}
                </button>
              </form>
            </>
          )}

          {step === 'done' && (
            <div className={reg.card}>
              <div className={reg.doneWrap}>
                <div className={reg.doneIcon}><IconCheck size={26} /></div>
                <div className={reg.title}>{t('forgot.doneHeading')}</div>
                <p className={reg.subtitle}>{t('forgot.doneSub')}</p>
                <button className={reg.submit}
                  onClick={() => navigate(`/portal/login${next ? `?next=${encodeURIComponent(next)}` : ''}`)}>
                  {t('forgot.doneSubmit')}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className={classes.page}>
      {/* ── Brand panel (same as PortalLogin) ─────────────────────────── */}
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
          <h1 className={classes.brandHeadline}>Forgot your password? No worries.</h1>
        </div>

        <div className={classes.brandFoot}>
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
          <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle colour scheme">
            {isDark ? <IconSun size={18} /> : <IconMoon size={18} />}
          </ActionIcon>
        </div>

        <div className={classes.formWrap}>
          <div className={classes.form}>
            {/* Step 1: request */}
            {step === 'request' && (
              <>
                <div className={classes.intro}>
                  <span className={classes.eyebrow}>{t('forgot.eyebrow')}</span>
                  <h2 className={classes.heading}>{prefillIdentifier ? 'Welcome back' : t('forgot.reqHeading')}</h2>
                  <p className={classes.sub}>
                    {prefillIdentifier
                      ? 'We found your account — verify it below to set up portal access. No need to sign up again.'
                      : t('forgot.reqSub')}
                  </p>
                </div>
                <form onSubmit={requestForm.onSubmit(handleRequest)}>
                  <div className={classes.fields}>
                    <div className={own.channelToggle}>
                      <button type="button"
                        className={`${own.channelBtn} ${channel === 'email' ? own.channelBtnActive : ''}`}
                        onClick={() => setChannel('email')}>
                        <IconMail size={16} /> {t('forgot.viaEmail')}
                      </button>
                      <button type="button"
                        className={`${own.channelBtn} ${channel === 'whatsapp' ? own.channelBtnActive : ''}`}
                        onClick={() => setChannel('whatsapp')}>
                        <IconBrandWhatsapp size={16} /> {t('forgot.viaWhatsapp')}
                      </button>
                    </div>
                    <div className={classes.field}>
                      <label className={classes.label} htmlFor="identifier">
                        <span>{channel === 'email' ? t('forgot.emailLabel') : t('forgot.phoneLabel')}</span>
                        <span className={classes.labelHint}>{t('login.required')}</span>
                      </label>
                      <input
                        id="identifier"
                        className={classes.input}
                        placeholder={channel === 'email' ? t('forgot.emailPlaceholder') : t('forgot.phonePlaceholder')}
                        autoComplete={channel === 'email' ? 'email' : 'tel'}
                        inputMode={channel === 'email' ? 'email' : 'tel'}
                        {...requestForm.getInputProps('identifier')}
                      />
                    </div>
                    <button className={classes.submit} type="submit" disabled={loading}>
                      {loading ? t('forgot.reqSubmitting') : t('forgot.reqSubmit')}
                    </button>
                  </div>
                </form>
                <p className={classes.newHere}>
                  {t('forgot.rememberPassword')}{' '}
                  <Link to={`/portal/login${next ? `?next=${encodeURIComponent(next)}` : ''}`}>{t('forgot.backToSignin')}</Link>
                </p>
              </>
            )}

            {/* Step 2: verify */}
            {step === 'verify' && (
              <>
                <div className={classes.intro}>
                  <span className={classes.eyebrow}>{t('forgot.eyebrow')}</span>
                  <h2 className={classes.heading}>{t('forgot.verifyHeading')}</h2>
                  <p className={classes.sub}>{t('forgot.verifySub')}</p>
                </div>
                <div className={classes.fields}>
                  <div className={own.alert}>
                    <IconInfoCircle size={16} style={{ flexShrink: 0 }} />
                    <span>{t('forgot.codeSentTo')} {contactHint || identifier}</span>
                  </div>
                  <div className={classes.field}>
                    <label className={classes.label} htmlFor="otp">
                      <span>{t('forgot.verifyLabel')}</span>
                    </label>
                    <input
                      id="otp"
                      className={own.otpInput}
                      inputMode="numeric"
                      maxLength={6}
                      autoFocus
                      value={otp}
                      onChange={(e) => setOtp(e.currentTarget.value.replace(/\D/g, '').slice(0, 6))}
                    />
                  </div>
                  <button className={classes.submit} type="button" disabled={loading} onClick={handleVerifyOtp}>
                    {loading ? t('forgot.verifySubmitting') : t('forgot.verifySubmit')}
                  </button>
                  <p className={`${classes.newHere} ${own.center}`}>
                    <button type="button" className={own.linkBtn} onClick={() => { setStep('request'); setOtp(''); }}>
                      {t('forgot.useDifferent')}
                    </button>
                  </p>
                </div>
              </>
            )}

            {/* Step 3: reset or register */}
            {step === 'reset' && (
              <>
                <div className={classes.intro}>
                  <span className={classes.eyebrow}>{t('forgot.eyebrow')}</span>
                  <h2 className={classes.heading}>{isRegistration ? t('forgot.registerHeading') : t('forgot.resetHeading')}</h2>
                  <p className={classes.sub}>{isRegistration ? t('forgot.registerSub') : t('forgot.resetSub')}</p>
                </div>
                <form onSubmit={resetForm.onSubmit(handleReset)}>
                  <div className={classes.fields}>
                    <div className={own.alert}>
                      {isRegistration ? <IconUserPlus size={16} style={{ flexShrink: 0 }} /> : <IconCheck size={16} style={{ flexShrink: 0 }} />}
                      <span>
                        {isRegistration
                          ? `Setting up portal access for ${clientName || identifier}`
                          : `${t('forgot.codeSentTo')} ${contactHint || identifier}`}
                      </span>
                    </div>
                    <div className={classes.field}>
                      <label className={classes.label} htmlFor="password">
                        <span>{t('forgot.newPassword')}</span>
                      </label>
                      <input
                        id="password"
                        type="password"
                        className={classes.input}
                        {...resetForm.getInputProps('password')}
                      />
                    </div>
                    <div className={classes.field}>
                      <label className={classes.label} htmlFor="password_confirmation">
                        <span>{t('forgot.confirmPassword')}</span>
                      </label>
                      <input
                        id="password_confirmation"
                        type="password"
                        className={classes.input}
                        {...resetForm.getInputProps('password_confirmation')}
                      />
                    </div>
                    <button className={classes.submit} type="submit" disabled={loading}>
                      {loading ? t('forgot.submitting') : (isRegistration ? t('forgot.registerSubmit') : t('forgot.resetSubmit'))}
                    </button>
                  </div>
                </form>
              </>
            )}

            {/* Step 4: done */}
            {step === 'done' && (
              <div className={own.center}>
                <div className={own.doneIcon}><IconCheck size={28} /></div>
                <h2 className={classes.heading}>{t('forgot.doneHeading')}</h2>
                <p className={classes.sub}>{t('forgot.doneSub')}</p>
                <button className={classes.submit} style={{ marginTop: 20 }}
                  onClick={() => navigate(`/portal/login${next ? `?next=${encodeURIComponent(next)}` : ''}`)}>
                  {t('forgot.doneSubmit')}
                </button>
              </div>
            )}
          </div>
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

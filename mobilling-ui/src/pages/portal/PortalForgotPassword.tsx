import { useState } from 'react';
import { useMantineColorScheme, useComputedColorScheme, ActionIcon } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { safeNext } from '../../utils/safeNext';
import { useBranding } from '../../branding';
import { useLanguage } from '../../i18n/LanguageContext';
import { IconSun, IconMoon, IconCheck, IconInfoCircle, IconUserPlus } from '@tabler/icons-react';
import { forgotPassword, verifyResetOtp, resetPassword } from '../../api/auth';
import classes from './PortalLogin.module.css';
import own from './PortalForgotPassword.module.css';

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
  const backHref = branding.branded && branding.website ? branding.website : 'https://moinfo.co.tz';

  const [step, setStep] = useState<Step>('request');
  const [loading, setLoading] = useState(false);
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
      const res = await forgotPassword(values.identifier);
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

  return (
    <div className={classes.page}>
      {/* ── Brand panel (same as PortalLogin) ─────────────────────────── */}
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
          <h1 className={classes.brandHeadline}>Forgot your password? No worries.</h1>
        </div>

        <div className={classes.brandFoot}>
          <div className={classes.copyright}>
            © {new Date().getFullYear()} MOINFOTECH COMPANY LIMITED
          </div>
        </div>
      </div>

      {/* ── Form column ─────────────────────────────────────────────── */}
      <div className={classes.formCol}>
        <div className={classes.topBar}>
          <a className={classes.back} href={backHref}>
            ← {t('login.backTo')} {backHref.replace(/^https?:\/\//, '')}
          </a>
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
                    <div className={classes.field}>
                      <label className={classes.label} htmlFor="identifier">
                        <span>{t('login.identifier')}</span>
                        <span className={classes.labelHint}>{t('login.required')}</span>
                      </label>
                      <input
                        id="identifier"
                        className={classes.input}
                        placeholder={t('forgot.reqPlaceholder')}
                        autoComplete="username"
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
          <span>© {new Date().getFullYear()} MOINFOTECH</span>
          <span>
            <a href="https://moinfo.co.tz/privacy">{t('login.privacy')}</a>
            {' · '}
            <a href="https://moinfo.co.tz/terms">{t('login.terms')}</a>
          </span>
        </div>
      </div>
    </div>
  );
}

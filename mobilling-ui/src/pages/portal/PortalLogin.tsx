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
  const { login } = useAuth();
  const navigate = useNavigate();
  // Set when the visitor came from an /order/* link — see OrderRoute.
  const next = safeNext(useLocation().search);
  const { toggleColorScheme } = useMantineColorScheme();
  const isDark = useComputedColorScheme('dark') === 'dark';
  const branding = useBranding();
  const { t } = useLanguage();
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
          title: t('login.verifyTitle'),
          message: t('login.verifyMessage'),
          color: 'blue',
        });
        navigate(
          `/portal/register?email=${encodeURIComponent(values.identifier)}&sent=1`
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
              {t('login.needHelp')}
            </a>
          </div>
        </div>

        <div className={classes.formWrap}>
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

            <div className={classes.quickLinks}>
              <a
                className={classes.quick}
                href="https://moinfo.co.tz:2083"
                target="_blank"
                rel="noopener noreferrer"
              >
                <span className={classes.quickLabel}>{t('login.cpanel')}</span>
                <span className={classes.quickText}>{t('login.cpanelDesc')}</span>
              </a>
              <a
                className={classes.quick}
                href="https://moinfo.co.tz:2096"
                target="_blank"
                rel="noopener noreferrer"
              >
                <span className={classes.quickLabel}>{t('login.webmail')}</span>
                <span className={classes.quickText}>{t('login.webmailDesc')}</span>
              </a>
            </div>

            <p className={classes.newHere}>
              {t('login.newHere')} {brandName}?{' '}
              <Link to={`/portal/register${next ? `?next=${encodeURIComponent(next)}` : ''}`}>
                {t('login.createAccount')}
              </Link>
            </p>
          </form>
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

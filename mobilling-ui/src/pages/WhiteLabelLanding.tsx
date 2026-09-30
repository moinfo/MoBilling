import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  IconServer, IconMailFast, IconCloud, IconSearch,
  IconCircleCheck, IconCircleX, IconBolt, IconHeadset, IconShieldCheck, IconRefresh,
} from '@tabler/icons-react';
import { useBranding } from '../branding';
import { checkPublicDomain, getPublicCatalog, DomainCheckResult } from '../api/publicStorefront';
import styles from './WhiteLabelLanding.module.css';

/**
 * The root page on a reseller's own custom domain (Tenant.custom_domain).
 * Styled like a real hosting-company homepage (moinfo.co.tz) rather than a
 * bare card — but deliberately content-free: no marketing copy that would
 * need writing per reseller. The domain search and plan pricing are real,
 * pulled live from the reseller's own tenant via the same public,
 * Host-resolved endpoints moinfo.co.tz itself uses.
 * See Landing.tsx: the actual MoBilling marketing site never renders here.
 */
const FEATURES = [
  { icon: IconBolt, title: 'Fast setup', desc: 'Most orders provision automatically — no waiting on a technician.' },
  { icon: IconHeadset, title: 'Local support', desc: 'A support team in your own time zone, reachable from your account.' },
  { icon: IconShieldCheck, title: 'Reliable infrastructure', desc: 'Redundant hardware and monitored uptime behind every service.' },
  { icon: IconRefresh, title: 'Easy renewals', desc: 'Manage billing, renewals and upgrades yourself, any time.' },
];

function money(n: number) {
  return `TZS ${Math.round(n).toLocaleString()}`;
}

export default function WhiteLabelLanding() {
  const branding = useBranding();
  const name = branding.name ?? 'Client Area';
  const initial = name.trim().charAt(0).toUpperCase() || '?';

  const [domainInput, setDomainInput] = useState('');
  const [searching, setSearching] = useState(false);
  const [result, setResult] = useState<DomainCheckResult | null>(null);

  const catalogQuery = useQuery({ queryKey: ['public-catalog'], queryFn: getPublicCatalog });
  const catalog = catalogQuery.data?.data;

  const runSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    const domain = domainInput.trim().toLowerCase();
    if (!domain || !domain.includes('.')) return;
    setSearching(true);
    setResult(null);
    try {
      const res = await checkPublicDomain(domain);
      setResult(res.data);
    } catch {
      setResult({ name: domain, offered: false, available: null, message: 'Could not check that domain right now — please try again.' });
    } finally {
      setSearching(false);
    }
  };

  const orderHref = (label: string) => `/portal/register?next=${encodeURIComponent(`/portal/dashboard?want=${label}`)}`;

  return (
    <div className={styles.page}>
      {/* ── Top bar ─────────────────────────────────────────────── */}
      <header className={styles.topbar}>
        <div className={styles.topbarInner}>
          <div className={styles.brandRow}>
            {branding.logo_url ? (
              <img src={branding.logo_url} alt="" className={styles.logoSm} />
            ) : (
              <div className={styles.avatarSm}>{initial}</div>
            )}
            <span className={styles.brandNameSm}>{name}</span>
          </div>
          <Link to="/portal/login" className={styles.navSignIn}>Client Area · Sign in</Link>
        </div>
      </header>

      {/* ── Hero + domain search ────────────────────────────────── */}
      <section className={styles.hero}>
        <h1 className={styles.heroTitle}>Everything you run with {name}, in one place.</h1>
        <p className={styles.heroSub}>Domains, hosting, business email and cloud servers — start with the domain.</p>

        <form className={styles.searchBar} onSubmit={runSearch}>
          <IconSearch size={18} className={styles.searchIcon} />
          <input
            className={styles.searchInput}
            placeholder="yourbusiness.co.tz"
            value={domainInput}
            onChange={(e) => setDomainInput(e.currentTarget.value)}
            autoCapitalize="off"
            autoCorrect="off"
          />
          <button className={styles.searchBtn} type="submit" disabled={searching}>
            {searching ? 'Checking…' : 'Search'}
          </button>
        </form>

        {result && (
          <div className={`${styles.searchResult} ${result.available ? styles.searchResultOk : styles.searchResultBad}`}>
            {result.offered && result.available && (
              <>
                <IconCircleCheck size={20} />
                <span><b>{result.name}</b> is available — {money(result.pricing!.register_price)}/year</span>
                <Link to={orderHref(result.name)} className={styles.resultCta}>Register now</Link>
              </>
            )}
            {result.offered && result.available === false && (
              <><IconCircleX size={20} /><span><b>{result.name}</b> is already registered.</span></>
            )}
            {!result.offered && (
              <><IconCircleX size={20} /><span>{result.message || "We don't currently offer that domain."}</span></>
            )}
          </div>
        )}
      </section>

      {/* ── Plans ────────────────────────────────────────────────── */}
      {catalog && catalog.hosting.length > 0 && (
        <section className={styles.plans}>
          <h2 className={styles.sectionTitle}><IconServer size={20} /> Hosting plans</h2>
          <div className={styles.planGrid}>
            {catalog.hosting.map((p) => (
              <div key={p.name} className={styles.planCard}>
                <div className={styles.planName}>{p.name}</div>
                <div className={styles.planPrice}>{money(p.price)}<span>/{p.billing_cycle}</span></div>
                <Link to={orderHref(p.name)} className={styles.planCta}>Get started</Link>
              </div>
            ))}
          </div>
        </section>
      )}

      {catalog && catalog.email.length > 0 && (
        <section className={styles.plans}>
          <h2 className={styles.sectionTitle}><IconMailFast size={20} /> Business email</h2>
          <div className={styles.planGrid}>
            {catalog.email.map((p) => (
              <div key={p.name} className={styles.planCard}>
                <div className={styles.planName}>{p.name}</div>
                <div className={styles.planPrice}>{money(p.price)}<span>/{p.billing_cycle}</span></div>
                <Link to={orderHref(p.name)} className={styles.planCta}>Get started</Link>
              </div>
            ))}
          </div>
        </section>
      )}

      {catalog && catalog.linode.length > 0 && (
        <section className={styles.plans}>
          <h2 className={styles.sectionTitle}><IconCloud size={20} /> Cloud servers</h2>
          <div className={styles.planGrid}>
            {catalog.linode.map((p) => (
              <div key={p.name} className={styles.planCard}>
                <div className={styles.planName}>{p.name}</div>
                <div className={styles.planPrice}>{money(p.price)}<span>/{p.billing_cycle}</span></div>
                <Link to={orderHref(p.name)} className={styles.planCta}>Get started</Link>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* ── Features ─────────────────────────────────────────────── */}
      <section className={styles.features}>
        <div className={styles.featureGrid}>
          {FEATURES.map((f) => (
            <div key={f.title} className={styles.featureCard}>
              <f.icon size={22} />
              <div className={styles.featureTitle}>{f.title}</div>
              <div className={styles.featureDesc}>{f.desc}</div>
            </div>
          ))}
        </div>
      </section>

      {/* ── Final CTA ────────────────────────────────────────────── */}
      <section className={styles.cta}>
        <h2>Ready to get started?</h2>
        <div className={styles.ctaActions}>
          <Link to="/portal/register" className={styles.primaryBtn}>Create account</Link>
          <Link to="/portal/login" className={styles.secondaryBtn}>Sign in</Link>
        </div>
      </section>

      <footer className={styles.footer}>© {new Date().getFullYear()} {name}</footer>
    </div>
  );
}

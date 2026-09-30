import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useBranding } from '../branding';
import { checkPublicDomain, getPublicCatalog, DomainCheckResult } from '../api/publicStorefront';
import styles from './WhiteLabelLanding.module.css';

/**
 * The root page on a reseller's own custom domain (Tenant.custom_domain).
 * Card-based storefront in the style of moinfo.co.tz — deliberately
 * content-free: no marketing copy that would need writing per reseller. The
 * domain search and plan pricing are real, pulled live from the reseller's
 * own tenant via the same public, Host-resolved endpoints moinfo.co.tz
 * itself uses. See Landing.tsx: the actual MoBilling marketing site never
 * renders here.
 */
const FEATURES = [
  { title: 'Automatic setup', desc: 'Most orders provision themselves — no waiting on a technician.' },
  { title: 'Local support', desc: 'A support team in your own time zone, reachable from your account.' },
  { title: 'Redundant hardware', desc: 'Monitored uptime behind every hosting account.' },
  { title: 'Self-service billing', desc: 'Manage renewals and upgrades yourself, any time.' },
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
      setResult({ name: domain, offered: false, available: null, message: "Couldn't check that domain — try again." });
    } finally {
      setSearching(false);
    }
  };

  const orderHref = (label: string) => `/portal/register?next=${encodeURIComponent(`/portal/dashboard?want=${label}`)}`;

  /** The middle-priced plan is the one most people should pick — worth a visual callout. */
  const popularName = (plans: { name: string; price: number }[]) =>
    plans.length >= 3 ? plans[Math.floor(plans.length / 2)].name : null;

  const renderPlans = (title: string, plans: { name: string; price: number; billing_cycle: string }[]) => {
    if (!plans.length) return null;
    const popular = popularName(plans);
    return (
      <section className={styles.plans} key={title}>
        <h2 className={styles.sectionTitle}>{title}</h2>
        <div className={styles.planGrid}>
          {plans.map((p) => (
            <Link key={p.name} to={orderHref(p.name)}
              className={`${styles.planCard} ${p.name === popular ? styles.planCardPopular : ''}`}>
              {p.name === popular && <span className={styles.planBadge}>Most chosen</span>}
              <div className={styles.planName}>{p.name}</div>
              <div className={styles.planPrice}>{money(p.price)}<span>/{p.billing_cycle}</span></div>
              <span className={styles.planCta}>Get started</span>
            </Link>
          ))}
        </div>
      </section>
    );
  };

  return (
    <div className={styles.page}>
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
          <Link to="/portal/login" className={styles.navSignIn}>Sign in</Link>
        </div>
      </header>

      <section className={styles.hero}>
        <h1 className={styles.heroTitle}>Your domain, hosting and business email — set up in minutes.</h1>
        <p className={styles.heroSub}>Search below. If it's free, the price is exact — no quotes, no waiting.</p>

        <form className={styles.searchBar} onSubmit={runSearch}>
          <input
            className={styles.searchInput}
            placeholder="yourbusiness.co.tz"
            value={domainInput}
            onChange={(e) => setDomainInput(e.currentTarget.value)}
            autoCapitalize="off"
            autoCorrect="off"
            spellCheck={false}
          />
          <button className={styles.searchBtn} type="submit" disabled={searching}>
            {searching ? 'Checking…' : 'Check'}
          </button>
        </form>

        {result && (
          <div className={`${styles.searchResult} ${result.available ? styles.searchResultOk : styles.searchResultBad}`}>
            {result.offered && result.available && (
              <>
                <span className={styles.resultDot} />
                <span><b>{result.name}</b> is available — {money(result.pricing!.register_price)}/year</span>
                <Link to={orderHref(result.name)} className={styles.resultCta}>Register</Link>
              </>
            )}
            {result.offered && result.available === false && (
              <><span className={styles.resultDot} /><span><b>{result.name}</b> is already registered.</span></>
            )}
            {!result.offered && (
              <><span className={styles.resultDot} /><span>{result.message || "We don't register that domain here."}</span></>
            )}
          </div>
        )}
      </section>

      {catalog && renderPlans('Hosting', catalog.hosting)}
      {catalog && renderPlans('Business email', catalog.email)}
      {catalog && renderPlans('Cloud servers', catalog.linode)}

      <section className={styles.features}>
        <div className={styles.featureGrid}>
          {FEATURES.map((f) => (
            <div key={f.title} className={styles.featureItem}>
              <div className={styles.featureTitle}>{f.title}</div>
              <div className={styles.featureDesc}>{f.desc}</div>
            </div>
          ))}
        </div>
      </section>

      <section className={styles.cta}>
        <h2>Get your own address online.</h2>
        <div className={styles.ctaActions}>
          <Link to="/portal/register" className={styles.primaryBtn}>Create account</Link>
          <Link to="/portal/login" className={styles.secondaryBtn}>Sign in</Link>
        </div>
      </section>

      <footer className={styles.footer}>© {new Date().getFullYear()} {name}</footer>
    </div>
  );
}

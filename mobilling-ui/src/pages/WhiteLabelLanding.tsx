import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useBranding } from '../branding';
import { checkPublicDomain, getPublicCatalog, DomainCheckResult } from '../api/publicStorefront';
import styles from './WhiteLabelLanding.module.css';

/**
 * The root page on a reseller's own custom domain (Tenant.custom_domain).
 * Design concept: a domain/registry lookup console, not a generic SaaS
 * marketing page — the search is the hero interaction, and plans read as a
 * spec ledger rather than pricing cards. No copy needs writing per reseller:
 * the domain search and plan pricing are real, pulled live from the
 * reseller's own tenant via the same public, Host-resolved endpoints
 * moinfo.co.tz itself uses. See Landing.tsx: the actual MoBilling marketing
 * site never renders here.
 */
const TRUST_LINES = [
  'Most orders provision automatically — no waiting on a technician.',
  'Support from a team in your own time zone.',
  'Redundant hardware behind every hosting account.',
  'Manage renewals and billing yourself, any time.',
];

function money(n: number) {
  return `TZS ${Math.round(n).toLocaleString()}`;
}

function PlanLedger({ title, plans, orderHref }: {
  title: string;
  plans: { name: string; price: number; billing_cycle: string }[];
  orderHref: (label: string) => string;
}) {
  if (plans.length === 0) return null;
  return (
    <section className={styles.ledger}>
      <h2 className={styles.ledgerTitle}>{title}</h2>
      <div className={styles.ledgerRows}>
        {plans.map((p) => (
          <Link key={p.name} to={orderHref(p.name)} className={styles.ledgerRow}>
            <span className={styles.rowName}>{p.name}</span>
            <span className={styles.rowPrice}>
              {money(p.price)}<span className={styles.rowCycle}>/{p.billing_cycle}</span>
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
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

  return (
    <div className={styles.page}>
      <header className={styles.topbar}>
        {branding.logo_url ? (
          <img src={branding.logo_url} alt="" className={styles.logoSm} />
        ) : (
          <div className={styles.avatarSm}>{initial}</div>
        )}
        <span className={styles.brandNameSm}>{name}</span>
        <Link to="/portal/login" className={styles.navSignIn}>Sign in</Link>
      </header>

      <section className={styles.hero}>
        <h1 className={styles.heroTitle}>Your domain, hosting and business email — set up in minutes.</h1>
        <p className={styles.heroSub}>Search below. If it's free, the price is exact — no quotes, no waiting.</p>

        <form className={styles.lookup} onSubmit={runSearch}>
          <label className={styles.lookupLabel} htmlFor="domain-lookup">Check a domain</label>
          <div className={styles.lookupRow}>
            <input
              id="domain-lookup"
              className={styles.lookupInput}
              placeholder="yourbusiness.co.tz"
              value={domainInput}
              onChange={(e) => setDomainInput(e.currentTarget.value)}
              autoCapitalize="off"
              autoCorrect="off"
              spellCheck={false}
            />
            <button className={styles.lookupBtn} type="submit" disabled={searching}>
              {searching ? 'Checking' : 'Check'}
            </button>
          </div>
        </form>

        {result && (
          <div className={styles.record}>
            {result.offered && result.available && (
              <>
                <span className={`${styles.dot} ${styles.dotOk}`} />
                <span className={styles.recordName}>{result.name}</span>
                <span className={styles.recordStatusOk}>available</span>
                <span className={styles.recordPrice}>{money(result.pricing!.register_price)}/yr</span>
                <Link to={orderHref(result.name)} className={styles.recordCta}>Register</Link>
              </>
            )}
            {result.offered && result.available === false && (
              <>
                <span className={`${styles.dot} ${styles.dotBad}`} />
                <span className={styles.recordName}>{result.name}</span>
                <span className={styles.recordStatusBad}>already registered</span>
              </>
            )}
            {!result.offered && (
              <>
                <span className={`${styles.dot} ${styles.dotBad}`} />
                <span className={styles.recordMsg}>{result.message || "We don't register that domain here."}</span>
              </>
            )}
          </div>
        )}
      </section>

      {catalog && (
        <>
          <PlanLedger title="Hosting" plans={catalog.hosting} orderHref={orderHref} />
          <PlanLedger title="Business email" plans={catalog.email} orderHref={orderHref} />
          <PlanLedger title="Cloud servers" plans={catalog.linode} orderHref={orderHref} />
        </>
      )}

      <section className={styles.trust}>
        {TRUST_LINES.map((line) => (
          <p key={line} className={styles.trustLine}>{line}</p>
        ))}
      </section>

      <section className={styles.cta}>
        <h2 className={styles.ctaTitle}>Get your own address online.</h2>
        <div className={styles.ctaActions}>
          <Link to="/portal/register" className={styles.primaryBtn}>Create account</Link>
          <Link to="/portal/login" className={styles.secondaryBtn}>Sign in</Link>
        </div>
      </section>

      <footer className={styles.footer}>© {new Date().getFullYear()} {name}</footer>
    </div>
  );
}

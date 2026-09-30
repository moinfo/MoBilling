import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useBranding } from '../branding';
import {
  checkPublicDomain, getPublicCatalog, DomainCheckResult, CatalogPlan,
} from '../api/publicStorefront';
import styles from './WhiteLabelLanding.module.css';

/**
 * The root page on a reseller's own custom domain (Tenant.custom_domain).
 * Built from the design the owner iterated on in Claude's design canvas
 * (https://claude.ai/artifact/8iKx1n7kvodTqSLt4k5Bb4) — a dark hero with a
 * live domain search, a tabbed hosting/business-email plan section with a
 * full spec comparison table, a 3-step "how it works", and a dark footer.
 * Every number on the page is real: pulled live from the reseller's own
 * tenant via the public, Host-resolved endpoints moinfo.co.tz itself uses
 * (domain search, plan catalog, TLD pricing) — nothing hardcoded per
 * reseller. See Landing.tsx: the actual MoBilling marketing site never
 * renders here.
 */
function money(n: number) {
  return n.toLocaleString();
}

/** "Disk Space: 4 GB · Bandwidth: 4 GB · ..." -> [{ label: 'disk space', value: '4 GB' }, ...] */
function parseSpecs(description: string | null): { label: string; value: string }[] {
  if (!description) return [];
  return description.split(' · ').map((chunk) => {
    const [label, ...rest] = chunk.split(': ');
    return { label: label.toLowerCase(), value: rest.join(': ') };
  }).filter((s) => s.label && s.value);
}

function specValue(specs: { label: string; value: string }[], label: string): string {
  return specs.find((s) => s.label === label)?.value ?? '—';
}

const SearchIcon = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#5b6472" strokeWidth={2} strokeLinecap="round">
    <circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" />
  </svg>
);
const CheckIcon = ({ color }: { color: string }) => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 12.5 10 17 19 7" />
  </svg>
);
const BoltIcon = ({ color }: { color: string }) => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <path d="M13 2 4 14h7l-1 8 9-12h-7z" />
  </svg>
);
const HeadsetIcon = ({ color }: { color: string }) => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <path d="M4 14v-2a8 8 0 0 1 16 0v2" /><rect x="3" y="14" width="4" height="6" rx="1.5" /><rect x="17" y="14" width="4" height="6" rx="1.5" />
  </svg>
);
const ShieldIcon = ({ color }: { color: string }) => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 3 4 6v6c0 4.5 3.4 8 8 9 4.6-1 8-4.5 8-9V6z" /><path d="m9 12 2 2 4-4" />
  </svg>
);
const ReceiptIcon = ({ color }: { color: string }) => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="5" width="18" height="14" rx="2" /><path d="M3 10h18M7 15h4" />
  </svg>
);
const ServerIcon = ({ color }: { color: string }) => (
  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="4" width="18" height="7" rx="2" /><rect x="3" y="13" width="18" height="7" rx="2" /><path d="M7 7.5h.01M7 16.5h.01" />
  </svg>
);
const MailIcon = ({ color }: { color: string }) => (
  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 7 9 6 9-6" />
  </svg>
);
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

const FEATURES = [
  { Icon: BoltIcon, title: 'Automatic setup', desc: 'Most orders provision themselves — no waiting on a technician.' },
  { Icon: HeadsetIcon, title: 'Local support', desc: 'A support team in your own time zone, reachable from your account.' },
  { Icon: ShieldIcon, title: 'Redundant hardware', desc: 'Monitored uptime behind every hosting account.' },
  { Icon: ReceiptIcon, title: 'Self-service billing', desc: 'Manage renewals and upgrades yourself, any time.' },
];

const HOW_IT_WORKS = [
  { n: '01', title: 'Search your name', desc: "Type the address you want. If it's free, you see the exact yearly price." },
  { n: '02', title: 'Add hosting or email', desc: 'Pick a plan that fits — upgrade any time from your account.' },
  { n: '03', title: 'Pay and go live', desc: 'Most orders set themselves up automatically — no waiting on a technician.' },
];

export default function WhiteLabelLanding() {
  const branding = useBranding();
  const name = branding.name ?? 'Client Area';
  const initial = name.trim().charAt(0).toUpperCase() || '?';
  const accent = 'var(--accent)';

  const THEME_KEY = 'wl_theme';
  const [theme, setTheme] = useState<'light' | 'dark' | null>(() => {
    try {
      const saved = localStorage.getItem(THEME_KEY);
      return saved === 'light' || saved === 'dark' ? saved : null;
    } catch { return null; }
  });
  const toggleTheme = () => {
    const current = theme ?? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    const next = current === 'dark' ? 'light' : 'dark';
    setTheme(next);
    try { localStorage.setItem(THEME_KEY, next); } catch { /* ignore */ }
  };
  // Effective theme for the toggle icon only — null (no explicit choice) still
  // follows the system preference via CSS alone, this just picks the right icon.
  const [systemPrefersDark, setSystemPrefersDark] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    setSystemPrefersDark(mq.matches);
    const onChange = (e: MediaQueryListEvent) => setSystemPrefersDark(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);
  const isDark = theme ? theme === 'dark' : systemPrefersDark;

  const [tab, setTab] = useState<'hosting' | 'email'>('hosting');
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

  // Real local TLD for the hero pill/example — .co.tz-style row preferred, else any .tz, else cheapest offered.
  const tlds = catalog?.tlds ?? [];
  const localTld = tlds.find((t) => t.tld === 'co.tz') || tlds.find((t) => t.tld === 'tz')
    || tlds.find((t) => t.tld.endsWith('.tz')) || tlds[0];

  const middlePlan = (plans: CatalogPlan[]) => (plans.length >= 3 ? plans[Math.floor(plans.length / 2)] : null);
  const hostingPlans = catalog?.hosting ?? [];
  const emailPlans = catalog?.email ?? [];
  const popularHosting = middlePlan(hostingPlans);
  const popularEmail = middlePlan(emailPlans);
  const headlinePlans = hostingPlans.slice(0, 4);

  // Illustrative example order in the hero — real plans/prices, not invented.
  const exampleHosting = popularHosting ?? hostingPlans[0];
  const exampleEmail = popularEmail ?? emailPlans[0];
  const exampleTotal = (localTld?.price ?? 0) + (exampleHosting?.price ?? 0) + (exampleEmail?.price ?? 0);
  const exampleDomainName = `yourbusiness.${localTld?.tld ?? 'co.tz'}`;
  const exampleHostingSpecs = exampleHosting ? parseSpecs(exampleHosting.description) : [];
  const exampleHostingSub = exampleHostingSpecs.length
    ? `${specValue(exampleHostingSpecs, 'disk space')} · ${specValue(exampleHostingSpecs, 'email accounts')} email accounts`
    : (exampleHosting ? `Billed ${exampleHosting.billing_cycle}` : '');

  return (
    <div className={styles.page} data-theme={theme ?? undefined}>
      <div className={styles.hero}>
        <div className={styles.container}>
          <header className={styles.navRow}>
            <a href="#top" className={styles.brand} aria-label={`${name} home`}>
              {branding.logo_url ? (
                <img src={branding.logo_url} alt="" className={styles.logoSm} />
              ) : (
                <span className={styles.avatarSm}>{initial}</span>
              )}
              <span className={styles.brandName}>{name}</span>
            </a>
            <nav className={styles.nav}>
              <a className={styles.navlink} href="#domains">Domains</a>
              <a className={styles.navlink} href="#plans">Hosting</a>
              <a className={styles.navlink} href="#plans">Business email</a>
              <a className={styles.navlink} href="#how">How it works</a>
            </nav>
            <div className={styles.navActions}>
              <button type="button" className={styles.themeToggle} onClick={toggleTheme}
                aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}>
                {isDark ? <SunIcon /> : <MoonIcon />}
              </button>
              <Link to="/portal/login" className={styles.btnGhost}>Sign in</Link>
              <Link to="/portal/register" className={styles.btnLight}>Create account</Link>
            </div>
          </header>

          <div id="domains" className={styles.heroGrid}>
            <div>
              {localTld && (
                <div className={styles.pill}>
                  <span className={styles.pillTag}>.{localTld.tld}</span>
                  {localTld.tld.endsWith('tz') ? 'Local domains' : 'Domains'} from TZS {money(localTld.price)}/year
                </div>
              )}
              <h1 className={styles.heroTitle}>Your domain, hosting and business email — set up in minutes.</h1>
              <p className={styles.heroSub}>Search below. If it's free, the price is exact — no quotes, no waiting.</p>

              <form className={styles.searchBar} onSubmit={runSearch}>
                <SearchIcon />
                <input
                  className={styles.searchInput}
                  placeholder="yourbusiness.co.tz"
                  value={domainInput}
                  onChange={(e) => setDomainInput(e.currentTarget.value)}
                  autoCapitalize="off"
                  autoCorrect="off"
                  spellCheck={false}
                />
                <button className={styles.checkBtn} type="submit" disabled={searching}>
                  {searching ? 'Checking…' : 'Check'}
                </button>
              </form>

              {result && (
                <div className={`${styles.searchResult} ${result.available ? styles.searchResultOk : styles.searchResultBad}`}>
                  {result.offered && result.available && (
                    <>
                      <span className={styles.resultDot} />
                      <span><b>{result.name}</b> is available — TZS {money(result.pricing!.register_price)}/year</span>
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

              {tlds.length > 0 && (
                <div className={styles.tldRow}>
                  {tlds.map((t) => (
                    <span key={t.tld} className={styles.tldChip}>
                      .{t.tld} <span className={styles.tldPrice}>{money(t.price)}</span>
                    </span>
                  ))}
                </div>
              )}
            </div>

            {(exampleHosting || exampleEmail) && (
              <div className={styles.orderCard}>
                <div className={styles.orderHead}>
                  <span className={styles.orderTitle}>Your order</span>
                  <span className={styles.orderBadge}>Example</span>
                </div>
                <div className={`${styles.orderRow} ${styles.orderRowOk}`}>
                  <span className={styles.orderCheck}><CheckIcon color="#fff" /></span>
                  <div className={styles.orderRowBody}>
                    <div className={styles.orderRowName}>{exampleDomainName}</div>
                    <div className={styles.orderRowSub} style={{ color: '#157a4a' }}>Available</div>
                  </div>
                  <span className={styles.orderRowPrice}>{money(localTld?.price ?? 0)}</span>
                </div>
                {exampleHosting && (
                  <div className={styles.orderRow}>
                    <span className={styles.orderIconTile}><ServerIcon color={accent} /></span>
                    <div className={styles.orderRowBody}>
                      <div className={styles.orderRowName}>{exampleHosting.name}</div>
                      <div className={styles.orderRowSub}>{exampleHostingSub}</div>
                    </div>
                    <span className={styles.orderRowPrice}>{money(exampleHosting.price)}</span>
                  </div>
                )}
                {exampleEmail && (
                  <div className={styles.orderRow}>
                    <span className={styles.orderIconTile}><MailIcon color={accent} /></span>
                    <div className={styles.orderRowBody}>
                      <div className={styles.orderRowName}>{exampleEmail.name}</div>
                      <div className={styles.orderRowSub}>you@{exampleDomainName.replace('yourbusiness.', '')}</div>
                    </div>
                    <span className={styles.orderRowPrice}>{money(exampleEmail.price)}</span>
                  </div>
                )}
                <div className={styles.orderTotal}>
                  <span>Total per year</span>
                  <span>TZS {money(exampleTotal)}</span>
                </div>
                <Link to={orderHref(exampleDomainName)} className={styles.orderCta}>Register &amp; go live</Link>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className={styles.features}>
        <div className={styles.featureGrid}>
          {FEATURES.map((f) => (
            <div key={f.title} className={styles.featureItem}>
              <span className={styles.featureIconTile}><f.Icon color={accent} /></span>
              <div>
                <div className={styles.featureTitle}>{f.title}</div>
                <div className={styles.featureDesc}>{f.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div id="plans" className={styles.plansSection}>
        <div className={styles.container}>
          <div className={styles.plansHead}>
            <div>
              <div className={styles.eyebrow}>Plans &amp; pricing</div>
              <h2 className={styles.plansTitle}>One yearly price.<br />Everything included.</h2>
            </div>
            <div className={styles.tabs} role="tablist" aria-label="Plan type">
              <button type="button" role="tab" aria-selected={tab === 'hosting'}
                className={`${styles.tab} ${tab === 'hosting' ? styles.tabActive : ''}`}
                onClick={() => setTab('hosting')}>
                Web hosting
              </button>
              <button type="button" role="tab" aria-selected={tab === 'email'}
                className={`${styles.tab} ${tab === 'email' ? styles.tabActive : ''}`}
                onClick={() => setTab('email')}>
                Business email
              </button>
            </div>
          </div>

          {tab === 'hosting' && headlinePlans.length > 0 && (
            <>
              <div className={styles.planGrid4}>
                {headlinePlans.map((p) => {
                  const specs = parseSpecs(p.description);
                  const popular = p.name === popularHosting?.name;
                  return (
                    <div key={p.name} className={`${styles.planCard} ${popular ? styles.planCardDark : ''}`}>
                      {popular && <span className={styles.planBadge}>Most chosen</span>}
                      <div className={styles.planName}>{p.name}</div>
                      <div className={styles.planPrice}>
                        <span className={styles.planPriceCcy}>TZS</span> {money(p.price)}
                      </div>
                      <div className={styles.planCycle}>per {p.billing_cycle}</div>
                      <Link to={orderHref(p.name)} className={`${styles.planCta} ${popular ? styles.planCtaLight : ''}`}>Get started</Link>
                      {specs.length > 0 && (
                        <ul className={`${styles.planSpecs} ${popular ? styles.planSpecsDark : ''}`}>
                          {specs.map((s) => (
                            <li key={s.label}>
                              <CheckIcon color={popular ? '#3fcf8e' : accent} />
                              <span><b>{s.value}</b> {s.label}</span>
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  );
                })}
              </div>

              {hostingPlans.some((p) => p.description) && (
                <div className={styles.compareCard}>
                  <div className={styles.compareHead}>
                    <span>Compare all hosting plans</span>
                    <span className={styles.compareNote}>Prices in TZS, billed yearly</span>
                  </div>
                  <div className={styles.compareScroll}>
                    <table className={styles.compareTable}>
                      <thead>
                        <tr>
                          <th>Plan</th><th>Price / year</th><th>Disk</th><th>Bandwidth</th>
                          <th>Databases</th><th>Email</th><th>Subdomains</th>
                        </tr>
                      </thead>
                      <tbody>
                        {hostingPlans.map((p) => {
                          const specs = parseSpecs(p.description);
                          return (
                            <tr key={p.name}>
                              <td className={styles.compareName}>{p.name}</td>
                              <td className={styles.comparePrice}>{money(p.price)}</td>
                              <td>{specValue(specs, 'disk space')}</td>
                              <td>{specValue(specs, 'bandwidth')}</td>
                              <td>{specValue(specs, 'databases')}</td>
                              <td>{specValue(specs, 'email accounts')}</td>
                              <td>{specValue(specs, 'subdomains')}</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </>
          )}

          {tab === 'email' && emailPlans.length > 0 && (
            <div className={styles.planGrid5}>
              {emailPlans.map((p) => {
                const specs = parseSpecs(p.description);
                const popular = p.name === popularEmail?.name;
                return (
                  <div key={p.name} className={`${styles.planCard} ${popular ? styles.planCardDark : ''}`}>
                    {popular && <span className={styles.planBadgeInline}>Most chosen</span>}
                    <div className={styles.planName}>{p.name}</div>
                    <div className={styles.planPrice}>
                      <span className={styles.planPriceCcy}>TZS</span> {money(p.price)}
                    </div>
                    <div className={styles.planCycle}>per {p.billing_cycle}</div>
                    <Link to={orderHref(p.name)} className={`${styles.planCta} ${popular ? styles.planCtaLight : ''}`}>Get started</Link>
                    {specs.length > 0 && (
                      <ul className={`${styles.planSpecs} ${popular ? styles.planSpecsDark : ''}`}>
                        {specs.map((s) => (
                          <li key={s.label}>
                            <CheckIcon color={popular ? '#3fcf8e' : accent} />
                            <span><b>{s.value}</b> {s.label}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      <div id="how" className={styles.howSection}>
        <div className={styles.container}>
          <h2 className={styles.howTitle}>Online in three steps.</h2>
          <div className={styles.howGrid}>
            {HOW_IT_WORKS.map((s) => (
              <div key={s.n} className={styles.howCard}>
                <div className={styles.howNum}>{s.n}</div>
                <div className={styles.howCardTitle}>{s.title}</div>
                <div className={styles.howCardDesc}>{s.desc}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className={styles.container} style={{ marginBottom: 96 }}>
        <div className={styles.ctaPanel}>
          <div>
            <h2 className={styles.ctaTitle}>Get your own address online.</h2>
            <p className={styles.ctaSub}>Create an account in a minute and manage everything yourself.</p>
          </div>
          <div className={styles.ctaActions}>
            <Link to="/portal/register" className={styles.btnLight}>Create account</Link>
            <Link to="/portal/login" className={styles.btnGhost}>Sign in</Link>
          </div>
        </div>
      </div>

      <footer className={styles.footer}>
        <div className={styles.container}>
          <div className={styles.footerGrid}>
            <div>
              <div className={styles.footerBrand}>
                {branding.logo_url ? (
                  <img src={branding.logo_url} alt="" className={styles.logoSm} />
                ) : (
                  <span className={styles.avatarSm}>{initial}</span>
                )}
                <span className={styles.brandName}>{name}</span>
              </div>
              <p className={styles.footerBlurb}>Domain, hosting and business email for Tanzanian businesses.</p>
            </div>
            <div className={styles.footerCol}>
              <span className={styles.footerColTitle}>Products</span>
              <a className={styles.flink} href="#domains">Domains</a>
              <a className={styles.flink} href="#plans">Web hosting</a>
              <a className={styles.flink} href="#plans">Business email</a>
            </div>
            <div className={styles.footerCol}>
              <span className={styles.footerColTitle}>Account</span>
              <Link className={styles.flink} to="/portal/login">Sign in</Link>
              <Link className={styles.flink} to="/portal/register">Create account</Link>
            </div>
            <div className={styles.footerCol}>
              <span className={styles.footerColTitle}>Help</span>
              <a className={styles.flink} href="#how">How it works</a>
            </div>
          </div>
          <div className={styles.footerCopy}>© {new Date().getFullYear()} {name}</div>
        </div>
      </footer>
    </div>
  );
}

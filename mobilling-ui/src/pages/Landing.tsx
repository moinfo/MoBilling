import { useState } from 'react';
import { Drawer, Loader, Center, Burger } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useMantineColorScheme, useComputedColorScheme } from '@mantine/core';
import { Link, Navigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  IconFileInvoice, IconFileText, IconBuildingBank, IconCash, IconLayoutDashboard,
  IconHeadset, IconSpeakerphone, IconWalk, IconMailFast,
  IconServer, IconWorldWww, IconRefresh, IconLock, IconLogin2, IconShoppingCart,
  IconPalette, IconBuildingCommunity,
  IconMail, IconPhone, IconBrandWhatsapp, IconMapPin,
  IconSun, IconMoon, IconPlus, IconMinus,
} from '@tabler/icons-react';
import { getPublicPlans, getPublicLicensePlans, SubscriptionPlan } from '../api/subscription';
import { isBrandedHost } from '../branding';
import { useReveal } from '../hooks/useReveal';
import '../theme/marketing.css';
import styles from './Landing.module.css';

// ── Brand constants ──────────────────────────────────────────────────────────
// Hard-coded rather than token-driven: these are the four brand hues and they
// mean the same thing in light and dark. Surface colours come from `.mkt`.

const BLUE = '#1a68b0';
const GREEN = '#2fae60';
const YELLOW = '#f5c518';
const ORANGE = '#f0632c';

const WHATSAPP = 'https://wa.me/255689011111';
const PHONE = '+255 689 011 111';
const EMAIL = 'info@moinfo.co.tz';

/** Yellow tiles need dark glyphs; every other accent carries white. */
const onAccent = (accent: string) => (accent === YELLOW ? '#3a2c00' : '#fff');

// ── Content ──────────────────────────────────────────────────────────────────

const NAV_LINKS = [
  { label: 'Features', href: '#features' },
  { label: 'Hosting & Domains', href: '#hosting' },
  { label: 'Reseller', href: '#reseller' },
  { label: 'Pricing', href: '#pricing' },
  { label: 'FAQ', href: '#faq' },
  { label: 'Contact', href: '#contact' },
];

const HERO_TRUST = [
  { dot: '#ffd24a', label: '.tz registry connected' },
  { dot: '#4fd189', label: 'cPanel automation' },
  { dot: '#56a9e8', label: 'M-Pesa & Pesapal ready' },
  { dot: '#f5a11d', label: 'Local support team' },
];

const STATS = [
  { value: '500+', color: BLUE, label: 'Businesses onboarded' },
  { value: '50K+', color: GREEN, label: 'Invoices generated' },
  { value: '300+', color: '#e0a512', label: 'Domains & hosting automated' },
  { value: '99.9%', color: ORANGE, label: 'Uptime' },
];

const HOW_IT_WORKS = [
  {
    num: '01', accent: BLUE, tint: 'var(--mk-tint-b)', on: 'var(--mk-on-b)',
    title: 'Create your account',
    body: 'Sign up in seconds. Set your business profile and logo, then invite your team.',
  },
  {
    num: '02', accent: GREEN, tint: 'var(--mk-tint-g)', on: 'var(--mk-on-g)',
    title: 'Add services & pricing',
    body: 'Import clients, define hosting plans and domain pricing — connect your WHM server if you host.',
  },
  {
    num: '03', accent: '#f5a11d', tint: 'var(--mk-tint-y)', on: 'var(--mk-on-y)',
    title: 'Sell on autopilot',
    body: 'Clients order and pay in your portal; provisioning, renewals, reminders and dunning run themselves.',
  },
];

const FEATURES = [
  { icon: IconFileInvoice, accent: BLUE, title: 'Invoicing & recurring billing', body: 'Automatic numbering, tax, recurring cycles, late fees and dunning — on autopilot.' },
  { icon: IconFileText, accent: GREEN, title: 'Quotations & proformas', body: 'Polished quotes and proformas that convert to final invoices in one click.' },
  { icon: IconBuildingBank, accent: YELLOW, title: 'Statutory bills', body: 'Never miss NHIF, NSSF, PAYE or VAT deadlines — tracked with due-date reminders.' },
  { icon: IconCash, accent: ORANGE, title: 'Payments & wallet', body: 'M-Pesa, Pesapal, bank, cash and cheque — plus a client credit wallet with auto-pay.' },
  { icon: IconLayoutDashboard, accent: BLUE, title: 'Client portal', body: 'Clients log in to order services, pay invoices, open tickets and manage everything themselves.' },
  { icon: IconHeadset, accent: GREEN, title: 'Support helpdesk', body: 'A full ticketing system — departments, priorities, email notifications — for you and your clients.' },
  { icon: IconSpeakerphone, accent: YELLOW, title: 'WhatsApp marketing', body: 'Track leads from WhatsApp and social ads through a full pipeline. Log calls, schedule follow-ups.' },
  { icon: IconWalk, accent: ORANGE, title: 'Field marketing', body: 'Manage door-to-door campaigns. Log visits, track conversion per officer, measure ROI per session.' },
  { icon: IconMailFast, accent: 'linear-gradient(135deg, #1a68b0, #2fae60)', title: 'SMS & email notifications', body: 'Payment reminders, invoice and renewal notices sent to clients automatically.' },
];

const HOSTING = [
  { icon: IconServer, title: 'cPanel hosting automation', body: 'Connect your WHM server: accounts are created the moment an invoice is paid, suspended on non-payment, upgraded with prorated billing.' },
  { icon: IconWorldWww, title: '.tz domain registrar', body: 'Register, renew and transfer .tz domains directly at the TCRA/tzNIC registry over EPP. Live availability search, your own pricing per TLD.' },
  { icon: IconRefresh, title: 'Auto-renewals from wallet', body: "Clients opt in to auto-renew — renewals invoice themselves and draw from the client's credit balance." },
  { icon: IconLock, title: 'SSL & DNS management', body: 'Nightly SSL monitoring on every domain, self-service nameserver changes and EPP transfer codes — all from the portal.' },
  { icon: IconLogin2, title: 'One-click cPanel login', body: 'Clients jump into cPanel, webmail, file manager or phpMyAdmin from their portal — no passwords to share.' },
  { icon: IconShoppingCart, title: 'Order → pay → provision', body: 'A WHMCS-style cart: clients choose a plan, pick a domain, pay online — and the service goes live automatically.' },
];

/** Icon hues cycle through the three light-on-dark brand tints. */
const DARK_ICON_COLORS = ['#4fd189', '#ffd24a', '#56a9e8'];

const RESELLER = [
  { icon: IconPalette, title: 'Your brand, your prices', body: 'Run the whole platform under your business name and logo. Set your own hosting plans and per-TLD pricing — keep the margin.' },
  { icon: IconServer, title: 'We run the machinery', body: 'Registry connections, cPanel automation, billing engine, portal and SSL monitoring — maintained for you.' },
  { icon: IconBuildingCommunity, title: 'Isolated tenant workspace', body: 'Your clients, invoices and services live in their own isolated workspace. Your customers only ever see your brand.' },
];

const TESTIMONIALS = [
  { bar: BLUE, tint: 'var(--mk-tint-b)', on: 'var(--mk-on-b)', initials: 'AH', name: 'Amina Hassan', role: 'Amina Traders, Dar es Salaam', quote: 'MoBilling replaced our manual Excel tracking. Now I generate invoices and track M-Pesa payments in seconds. Statutory deadlines? I never miss them anymore.' },
  { bar: GREEN, tint: 'var(--mk-tint-g)', on: 'var(--mk-on-g)', initials: 'DO', name: 'David Ochieng', role: 'Ochieng IT Solutions, Nairobi', quote: 'We moved our whole hosting business off WHMCS. Domains register themselves when clients pay, cPanel accounts provision automatically, and we stopped paying license fees.' },
  { bar: '#f5a11d', tint: 'var(--mk-tint-y)', on: 'var(--mk-on-y)', initials: 'FK', name: 'Fatuma Kombo', role: 'Kombo Supplies, Mombasa', quote: 'Our field sales team now logs every door-to-door visit from their phones. Management sees real-time conversion stats. Best investment we made this year.' },
];

const FAQS = [
  { q: 'Is MoBilling a WHMCS alternative?', a: 'Yes. MoBilling does what WHMCS does — client portal, shopping cart, cPanel/WHM auto-provisioning, domain registration and renewals, tickets, recurring billing and dunning — with no separate licence fee, and built for East African payments like M-Pesa and Pesapal.' },
  { q: 'Can I sell hosting and domains?', a: 'Yes. Connect your WHM server and MoBilling creates, suspends and upgrades cPanel accounts automatically. .tz domains are registered directly at the TCRA/tzNIC registry over EPP, with your own pricing per TLD.' },
  { q: 'What is the white-label reseller program?', a: 'You run MoBilling under your own brand: your logo, your domain pricing, your hosting plans, your client portal. We operate the registry connections, automation and infrastructure behind the scenes — your customers only ever see your business.' },
  { q: 'Is there a free trial?', a: "Yes. You can start completely free, with no card required. When you're ready, choose the plan that fits your business." },
  { q: 'Which payment methods are supported?', a: 'M-Pesa, Pesapal, bank transfers, cash, cheques and mobile money — plus a client credit wallet for prepaid balances and auto-renewals.' },
  { q: 'Is MoBilling compliant with TRA/KRA?', a: 'Yes. MoBilling supports VAT, PAYE, NHIF, NSSF and other statutory requirements for Tanzania and Kenya.' },
  { q: 'Can I use it on my phone?', a: 'Yes. MoBilling is fully responsive and works on any device — phone, tablet or desktop.' },
  { q: 'Can I import my existing client data?', a: 'Yes — including from WHMCS. We migrate clients, services, invoices, payments and domains; your clients even keep their old portal passwords.' },
  { q: 'Do you offer support in Swahili?', a: 'Kabisa! Our support team speaks both Swahili and English. Reach us on WhatsApp, phone or email any time.' },
  { q: 'What happens if I stop paying?', a: 'Your data stays yours. The account moves to read-only so you can still export clients, invoices and payments — nothing is deleted when a subscription lapses.' },
];

const CONTACTS = [
  { icon: IconMail, accent: BLUE, label: 'EMAIL', value: EMAIL, href: `mailto:${EMAIL}` },
  { icon: IconPhone, accent: YELLOW, label: 'PHONE', value: PHONE, href: 'tel:+255689011111' },
  { icon: IconBrandWhatsapp, accent: GREEN, label: 'WHATSAPP', value: PHONE, href: WHATSAPP },
  { icon: IconMapPin, accent: ORANGE, label: 'OFFICE', value: 'Njuweni Hotel, 1st Floor, Room 134\nKibaha, Tanzania' },
];

// ── Hero dashboard preview ───────────────────────────────────────────────────
// Static by design: this is a picture of the product, not a live widget. Every
// figure is illustrative, so it must never be mistaken for the user's own data.

const PREVIEW_METRICS = [
  { label: 'REVENUE MTD', value: 'TZS 4.2M', tint: 'var(--mk-tint-b)', on: 'var(--mk-on-b)' },
  { label: 'HOSTING', value: '109', tint: 'var(--mk-tint-g)', on: 'var(--mk-on-g)' },
  { label: 'DOMAINS', value: '317', tint: 'var(--mk-tint-y)', on: 'var(--mk-on-y)' },
];

const PREVIEW_INVOICES = [
  { name: 'Amina Traders', amount: '450,000', status: 'PAID', tint: 'var(--mk-tint-g)', on: 'var(--mk-on-g)' },
  { name: 'Kibaha Hardware', amount: '182,500', status: 'PENDING', tint: 'var(--mk-tint-y)', on: 'var(--mk-on-y)' },
  { name: 'TopNet Ltd', amount: '320,000', status: 'PAID', tint: 'var(--mk-tint-g)', on: 'var(--mk-on-g)' },
  { name: 'Salama Shops', amount: '95,000', status: 'OVERDUE', tint: 'var(--mk-tint-o)', on: 'var(--mk-on-o)' },
];

function DashboardPreview() {
  return (
    <div className={styles.preview} aria-hidden="true">
      <div className={styles.previewHead}>
        <span>MOBILLING / DASHBOARD</span>
        <span className={styles.live}>
          <span className={styles.liveDot} />
          LIVE
        </span>
      </div>

      <div className={styles.metrics}>
        {PREVIEW_METRICS.map((m) => (
          <div key={m.label} className={styles.metric} style={{ background: m.tint }}>
            <div className={styles.metricLabel} style={{ color: m.on }}>{m.label}</div>
            <div className={styles.metricValue}>{m.value}</div>
          </div>
        ))}
      </div>

      <div className={styles.previewBody}>
        <div className={styles.previewLabel}>RECENT INVOICES</div>
        {PREVIEW_INVOICES.map((row) => (
          <div key={row.name} className={styles.invoiceRow}>
            <span className={styles.avatarTile} style={{ background: row.tint, color: row.on }}>
              {row.name[0]}
            </span>
            <span className={styles.invoiceName}>{row.name}</span>
            <span className={styles.invoiceAmount}>{row.amount}</span>
            <span className={styles.chip} style={{ background: row.tint, color: row.on }}>
              {row.status}
            </span>
          </div>
        ))}
      </div>

      <div className={styles.previewFoot}>
        <div className={styles.miniCard}>
          <div className={styles.miniLabel}>DOMAIN REGISTERED</div>
          <div className={styles.miniValue}>amina-traders.co.tz · auto</div>
        </div>
        <div className={styles.miniCard}>
          <div className={styles.miniLabel}>PAYMENT RECEIVED</div>
          <div className={styles.miniValue}>TZS 450,000 via M-Pesa</div>
        </div>
      </div>
    </div>
  );
}

// ── Pricing ──────────────────────────────────────────────────────────────────

const PLAN_ACCENTS = [
  { tint: 'var(--mk-tint-b)', on: 'var(--mk-on-b)' },
  { tint: 'var(--mk-tint-g)', on: 'var(--mk-on-g)' },
  { tint: 'var(--mk-tint-y)', on: 'var(--mk-on-y)' },
  { tint: 'var(--mk-tint-o)', on: 'var(--mk-on-o)' },
];

/** Self-hosted licence tiers get a coloured top rule, keyed by product line. */
const LICENSE_ACCENTS: Record<string, string> = {
  lite: YELLOW,
  reseller: BLUE,
  general: GREEN,
};

/**
 * Which hosted plan wears the dark "POPULAR" card.
 *
 * The design hard-codes the third of four tiers, but plans come from
 * /api/plans and their count varies per deployment, so the choice has to be
 * derived. This picks the second-most-expensive tier: it is the upsell target
 * in a four-tier ladder and degrades sensibly to the top tier when there are
 * fewer, without assuming any particular plan name.
 *
 * Returns the plan's index in `plans`, or -1 to highlight none.
 */
function pickPopularPlan(plans: SubscriptionPlan[]): number {
  if (plans.length < 3) return -1; // nothing to upsell towards
  const byPrice = [...plans].sort((a, b) => Number(a.price) - Number(b.price));
  return plans.indexOf(byPrice[byPrice.length - 2]);
}

const money = (value: string | number) => `TZS ${Number(value).toLocaleString()}`;

function PricingSection() {
  const [tab, setTab] = useState<'hosted' | 'self'>('hosted');

  const hosted = useQuery({ queryKey: ['public-plans'], queryFn: getPublicPlans });
  const self = useQuery({ queryKey: ['public-license-plans'], queryFn: getPublicLicensePlans });

  const plans = hosted.data?.data?.data ?? [];
  const licences = self.data?.data?.data ?? [];
  const popular = pickPopularPlan(plans);
  const loading = tab === 'hosted' ? hosted.isLoading : self.isLoading;

  return (
    <section id="pricing" className={styles.section}>
      <div className={styles.shell}>
        <div className={styles.centered} data-reveal="">
          <div className={styles.eyebrow} style={{ color: 'var(--mk-on-b)' }}>PRICING</div>
          <h2 className={styles.h2}>Simple, transparent pricing</h2>
          <p className={styles.lead} style={{ maxWidth: '52ch' }}>
            Start with a free trial. Choose a plan when you&apos;re ready — hosted by us, or licensed
            for your own server.
          </p>
          <div className={styles.switch} role="tablist" aria-label="Pricing model">
            <button
              type="button"
              role="tab"
              aria-selected={tab === 'hosted'}
              className={`${styles.switchBtn} ${tab === 'hosted' ? styles.switchBtnActive : ''}`}
              onClick={() => setTab('hosted')}
            >
              Hosted plans
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={tab === 'self'}
              className={`${styles.switchBtn} ${tab === 'self' ? styles.switchBtnActive : ''}`}
              onClick={() => setTab('self')}
            >
              Self-hosted licence
            </button>
          </div>
        </div>

        {loading ? (
          <Center py={60}><Loader /></Center>
        ) : tab === 'hosted' ? (
          plans.length === 0 ? null : (
            <div
              className={styles.priceGrid}
              style={{ ['--cols' as string]: String(Math.min(plans.length, 4)) }}
            >
              {plans.map((plan, i) => {
                const isPopular = i === popular;
                const accent = PLAN_ACCENTS[i % PLAN_ACCENTS.length];
                const tick = isPopular ? '#4fd189' : accent.on;
                return (
                  <div
                    key={plan.id}
                    data-reveal=""
                    className={`${styles.priceCard} ${isPopular ? styles.priceCardPopular : ''}`}
                  >
                    <div className={styles.priceHead}>
                      <span className={styles.priceName}>{plan.name}</span>
                      {isPopular && <span className={styles.popularChip}>POPULAR</span>}
                    </div>
                    <div className={styles.priceDesc}>{plan.description}</div>
                    <div className={styles.priceValue}>{money(plan.price)}</div>
                    <div className={styles.priceCadence}>PER {plan.billing_cycle_days} DAYS</div>

                    {plan.features && plan.features.length > 0 && (
                      <div className={styles.priceFeatures}>
                        {plan.features.map((f, fi) => (
                          <div key={fi} className={styles.priceFeature}>
                            <span className={styles.tick} style={{ color: tick }}>✓</span>
                            {f}
                          </div>
                        ))}
                      </div>
                    )}

                    <Link
                      to="/register"
                      className={`${styles.btn} ${styles.priceCta}`}
                      style={
                        isPopular
                          ? { background: 'var(--mk-cta)', color: '#fff' }
                          : { background: accent.tint, color: accent.on }
                      }
                    >
                      {isPopular ? 'Get started →' : 'Get started'}
                    </Link>
                  </div>
                );
              })}
            </div>
          )
        ) : licences.length === 0 ? (
          <p className={styles.priceNote}>
            Self-hosted licences are available on request —{' '}
            <a href={WHATSAPP} target="_blank" rel="noreferrer">talk to sales</a>.
          </p>
        ) : (
          <>
            <div
              className={styles.priceGrid}
              style={{ ['--cols' as string]: String(Math.min(licences.length, 3)) }}
            >
              {licences.map((plan) => {
                const accent = LICENSE_ACCENTS[plan.product] ?? BLUE;
                const purchasable =
                  plan.monthly_price || plan.quarterly_price || plan.semi_annual_price ||
                  plan.annual_price || plan.perpetual_price;
                const headline = plan.monthly_price ?? plan.annual_price;
                const cadence = plan.monthly_price ? 'PER MONTH' : 'PER YEAR';
                return (
                  <div
                    key={plan.id}
                    data-reveal=""
                    className={styles.priceCard}
                    style={{ borderTop: `4px solid ${accent}` }}
                  >
                    <div className={styles.priceHead}>
                      <span className={styles.priceName}>{plan.name}</span>
                    </div>
                    <div className={styles.priceDesc}>{plan.description}</div>

                    {headline ? (
                      <>
                        <div className={styles.priceValue}>{money(headline)}</div>
                        <div className={styles.priceCadence}>{cadence}</div>
                        {plan.monthly_price && plan.annual_price && (
                          <div className={styles.priceAlt}>
                            or {money(plan.annual_price)} per year
                          </div>
                        )}
                      </>
                    ) : (
                      <>
                        <div className={styles.priceValue}>Talk to us</div>
                        <div className={styles.priceCadence}>CUSTOM PRICING</div>
                      </>
                    )}

                    {purchasable ? (
                      <div style={{ marginTop: 'auto' }}>
                        <Link
                          to={`/buy-license?product=${plan.product}`}
                          className={`${styles.btn} ${styles.priceCta}`}
                          style={{ background: accent, color: onAccent(accent), width: '100%' }}
                        >
                          Buy licence
                        </Link>
                        <a
                          className={styles.priceSecondary}
                          href={`${WHATSAPP}?text=${encodeURIComponent(`I want a self-hosted ${plan.name} licence`)}`}
                          target="_blank"
                          rel="noreferrer"
                        >
                          Or talk to sales first
                        </a>
                      </div>
                    ) : (
                      <a
                        className={`${styles.btn} ${styles.priceCta}`}
                        style={{ background: 'var(--mk-tint-b)', color: 'var(--mk-on-b)' }}
                        href={`${WHATSAPP}?text=${encodeURIComponent(`I want a self-hosted ${plan.name} licence`)}`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        Talk to sales
                      </a>
                    )}
                  </div>
                );
              })}
            </div>
            <p className={styles.priceNote}>
              Self-hosted licences are governed by the{' '}
              <Link to="/license-agreement">MoBilling Licence Agreement</Link>.
            </p>
          </>
        )}
      </div>
    </section>
  );
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default function Landing() {
  // White-label domains never show the MoBilling marketing site.
  // Checked before any hook so hook order stays stable (rules of hooks).
  if (isBrandedHost()) return <Navigate to="/portal/login" replace />;
  return <LandingContent />;
}

function LandingContent() {
  const { toggleColorScheme } = useMantineColorScheme();
  const scheme = useComputedColorScheme('light');
  const [menuOpened, { toggle: toggleMenu, close: closeMenu }] = useDisclosure(false);
  const [openFaq, setOpenFaq] = useState(0);
  const revealRef = useReveal();

  return (
    <div className="mkt" ref={revealRef}>
      {/* ── Utility strip ── */}
      <div className={styles.rule} />
      <div className={styles.utility}>
        <div className={styles.utilityInner}>
          <div className={styles.utilityLeft}>
            <a href={`mailto:${EMAIL}`}>{EMAIL}</a>
            <a href="tel:+255689011111">{PHONE}</a>
          </div>
          <a className={styles.utilityWa} href={WHATSAPP} target="_blank" rel="noreferrer">
            CHAT ON WHATSAPP →
          </a>
        </div>
      </div>

      {/* ── Nav ── */}
      <header className={styles.nav}>
        <div className={styles.navInner}>
          <a className={styles.brand} href="#top">
            <img src="/moinfotech-logo.png" alt="" />
            <span className={styles.wordmark}>MoBilling</span>
          </a>

          <nav className={styles.navLinks}>
            {NAV_LINKS.map((l) => (
              <a key={l.href} href={l.href}>{l.label}</a>
            ))}
          </nav>

          <div className={styles.navActions}>
            <button
              type="button"
              className={styles.iconBtn}
              onClick={toggleColorScheme}
              aria-label={scheme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'}
            >
              {scheme === 'dark' ? <IconSun size={20} /> : <IconMoon size={20} />}
            </button>
            <Link className={styles.signIn} to="/login">Sign in</Link>
            <a className={`${styles.btn} ${styles.btnPrimary}`} href="#pricing">Get started</a>
            <Burger
              className={styles.burger}
              opened={menuOpened}
              onClick={toggleMenu}
              size="sm"
              aria-label="Open navigation"
            />
          </div>
        </div>
      </header>

      <Drawer opened={menuOpened} onClose={closeMenu} position="right" size="70%" title="Menu">
        <nav style={{ display: 'flex', flexDirection: 'column', gap: 18, fontSize: 17 }}>
          {NAV_LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              onClick={closeMenu}
              style={{ color: 'inherit', textDecoration: 'none' }}
            >
              {l.label}
            </a>
          ))}
          <Link to="/login" style={{ color: 'inherit', textDecoration: 'none', fontWeight: 600 }}>
            Sign in
          </Link>
        </nav>
      </Drawer>

      {/* ── Hero ── */}
      <section className={styles.hero} id="top">
        <div className={styles.heroGlowA} />
        <div className={styles.heroGlowB} />
        <div className={styles.heroGrid}>
          <div className={styles.heroCopy}>
            <div className={styles.pill}>
              <span className={styles.pillDot} />
              WHMCS-STYLE PLATFORM · BUILT FOR EAST AFRICA
            </div>
            <h1 className={styles.h1}>
              Billing, hosting<br />&amp; .tz domains<br />
              <span className={styles.h1Accent}>on autopilot.</span>
            </h1>
            <p className={styles.heroBody}>
              Invoices, statutory bills, a client portal, cPanel provisioning and a direct .tz
              registrar — everything WHMCS does, plus East African billing, in one platform.
              White-label it and sell under your own brand.
            </p>
            <div className={styles.heroButtons}>
              <a className={`${styles.btn} ${styles.btnCta}`} href="#pricing">Start free today →</a>
              <a
                className={`${styles.btn} ${styles.btnGhost}`}
                href={WHATSAPP}
                target="_blank"
                rel="noreferrer"
              >
                WhatsApp us
              </a>
            </div>
            <div className={styles.heroTrust}>
              {HERO_TRUST.map((t) => (
                <div key={t.label}>
                  <span className={styles.trustDot} style={{ background: t.dot }} />
                  {t.label}
                </div>
              ))}
            </div>
          </div>

          <DashboardPreview />
        </div>
      </section>

      {/* ── Stats ── */}
      <div className={styles.stats}>
        <div className={styles.statsGrid}>
          {STATS.map((s) => (
            <div key={s.label} className={styles.statCard} data-reveal="">
              <div className={styles.statValue} style={{ color: s.color }}>{s.value}</div>
              <div className={styles.statLabel}>{s.label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* ── How it works ── */}
      <section className={styles.section}>
        <div className={styles.shell}>
          <div className={styles.centered} data-reveal="">
            <div className={styles.eyebrow} style={{ color: GREEN }}>HOW IT WORKS</div>
            <h2 className={styles.h2}>Up and running in minutes</h2>
            <p className={styles.lead}>
              No complicated setup, no training, no consultant. Sign up, add your services, start
              billing the same afternoon.
            </p>
          </div>

          <div className={styles.grid3}>
            {HOW_IT_WORKS.map((s) => (
              <div
                key={s.num}
                className={styles.stepCard}
                style={{ borderTopColor: s.accent }}
                data-reveal=""
              >
                <div className={styles.iconTile} style={{ background: s.tint }}>
                  <span className={styles.stepNum} style={{ color: s.on }}>{s.num}</span>
                </div>
                <h3 className={styles.h3}>{s.title}</h3>
                <p className={styles.body}>{s.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Features ── */}
      <section id="features" className={styles.band}>
        <div style={{ maxWidth: 1280, margin: '0 auto' }}>
          <div className={styles.centered} data-reveal="">
            <div className={styles.eyebrow} style={{ color: 'var(--mk-on-b)' }}>FEATURES</div>
            <h2 className={styles.h2}>Everything you need to run your business</h2>
            <p className={styles.lead}>
              From generating invoices to running WhatsApp campaigns — MoBilling handles it all.
            </p>
          </div>

          <div className={styles.grid3}>
            {FEATURES.map((f) => (
              <div
                key={f.title}
                className={styles.featureCard}
                style={{ ['--accent' as never]: f.accent }}
                data-reveal=""
              >
                <div className={styles.iconTile} style={{ background: f.accent }}>
                  <f.icon size={24} color={onAccent(f.accent)} />
                </div>
                <h3 className={styles.h3}>{f.title}</h3>
                <p className={styles.body}>{f.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Hosting & domains ── */}
      <section id="hosting" className={styles.dark}>
        <div className={styles.darkGlow} />
        <div className={styles.darkInner}>
          <div className={styles.centered} data-reveal="">
            <div className={styles.eyebrow} style={{ color: '#4fd189' }}>HOSTING &amp; DOMAINS</div>
            <h2 className={styles.h2}>Everything WHMCS does — built in</h2>
            <p className={styles.lead}>
              Sell cPanel hosting and .tz domains with end-to-end automation: order, pay, provision,
              renew, suspend. No licence fees, no plugins, no cron babysitting.
            </p>
          </div>

          <div className={styles.grid3}>
            {HOSTING.map((h, i) => (
              <div key={h.title} className={styles.darkCard} data-reveal="">
                <div className={styles.darkCardHead}>
                  <span className={styles.darkTile}>
                    <h.icon size={21} color={DARK_ICON_COLORS[i % DARK_ICON_COLORS.length]} />
                  </span>
                  <span className={styles.darkIndex}>{String(i + 1).padStart(2, '0')}</span>
                </div>
                <h3 className={styles.h3}>{h.title}</h3>
                <p className={styles.body}>{h.body}</p>
              </div>
            ))}
          </div>

          <div className={styles.migrate} data-reveal="">
            <div>
              <h3 className={styles.h3}>Migrating from WHMCS?</h3>
              <p className={styles.body}>
                We import your clients, services, invoices, payments and domains — your clients even
                keep their existing portal passwords. Zero-downtime cutover.
              </p>
            </div>
            <a
              className={`${styles.btn} ${styles.btnCta}`}
              href={`${WHATSAPP}?text=${encodeURIComponent('I want to migrate from WHMCS to MoBilling')}`}
              target="_blank"
              rel="noreferrer"
            >
              Ask about migration →
            </a>
          </div>
        </div>
      </section>

      {/* ── Testimonials ── */}
      <section className={styles.section}>
        <div className={styles.shell}>
          <div className={styles.centered} data-reveal="">
            <div className={styles.eyebrow} style={{ color: '#e0a512' }}>TESTIMONIALS</div>
            <h2 className={styles.h2}>Loved by businesses across East Africa</h2>
          </div>

          <div className={styles.grid3}>
            {TESTIMONIALS.map((t) => (
              <figure key={t.name} className={styles.quoteCard} data-reveal="" style={{ margin: 0 }}>
                <div className={styles.quoteBar} style={{ background: t.bar }} />
                <blockquote className={styles.quote}>“{t.quote}”</blockquote>
                <figcaption className={styles.attribution}>
                  <span className={styles.initials} style={{ background: t.tint, color: t.on }}>
                    {t.initials}
                  </span>
                  <span>
                    <span className={styles.attrName} style={{ display: 'block' }}>{t.name}</span>
                    <span className={styles.attrRole}>{t.role}</span>
                  </span>
                </figcaption>
              </figure>
            ))}
          </div>
        </div>
      </section>

      {/* ── Reseller ── */}
      <section id="reseller" className={styles.shell} style={{ paddingBottom: 8 }}>
        <div className={styles.reseller} data-reveal="">
          <div className={styles.resellerGlow} />
          <div className={styles.resellerInner}>
            <div className={styles.resellerPill}>WHITE-LABEL RESELLER</div>
            <h2 className={styles.h2}>Your brand. Our engine.</h2>
            <p className={styles.lead} style={{ marginBottom: 36 }}>
              Start your own hosting and domains business without building any infrastructure.
              Resell under your own name — we run the registry, servers and billing behind the
              scenes.
            </p>

            <div className={styles.grid3}>
              {RESELLER.map((r) => (
                <div key={r.title} className={styles.resellerCard}>
                  <div className={styles.iconTile} style={{ background: 'rgba(255,255,255,0.18)' }}>
                    <r.icon size={22} color="#fff" />
                  </div>
                  <h3 className={styles.h3}>{r.title}</h3>
                  <p className={styles.body}>{r.body}</p>
                </div>
              ))}
            </div>

            <div className={styles.centerButtons}>
              <Link className={`${styles.btn} ${styles.btnWhite}`} to="/register">
                Become a reseller →
              </Link>
              <a
                className={`${styles.btn} ${styles.btnOutline}`}
                href={WHATSAPP}
                target="_blank"
                rel="noreferrer"
              >
                Talk to sales
              </a>
            </div>
          </div>
        </div>
      </section>

      <PricingSection />

      {/* ── FAQ ── */}
      <section id="faq" className={styles.section}>
        <div className={`${styles.shell} ${styles.faqGrid}`}>
          <div className={styles.faqAside} data-reveal="">
            <div className={styles.eyebrow} style={{ color: GREEN }}>FAQ</div>
            <h2 className={styles.h2}>Frequently asked questions</h2>
            <p className={styles.body}>
              Still have questions? Reach us on WhatsApp any time — {PHONE}.
            </p>
          </div>

          <div className={styles.faqList}>
            {FAQS.map((item, i) => {
              const open = openFaq === i;
              return (
                <div key={item.q} className={styles.faqItem}>
                  <button
                    type="button"
                    className={styles.faqTrigger}
                    aria-expanded={open}
                    onClick={() => setOpenFaq(open ? -1 : i)}
                  >
                    <span className={styles.faqQuestion}>{item.q}</span>
                    <span className={styles.faqGlyph}>
                      {open ? <IconMinus size={20} /> : <IconPlus size={20} />}
                    </span>
                  </button>
                  {open && <p className={styles.faqAnswer}>{item.a}</p>}
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* ── Closing CTA ── */}
      <section className={styles.shell} style={{ paddingBottom: 96 }}>
        <div className={styles.ctaFrame} data-reveal="">
          <div className={styles.ctaInner}>
            <div className={styles.eyebrow} style={{ color: '#ffd24a' }}>FREE TO START</div>
            <h2 className={styles.h2}>Ready to simplify your billing?</h2>
            <p className={styles.lead}>
              Join hundreds of East African businesses already using MoBilling to stay compliant and
              grow faster.
            </p>
            <div className={styles.centerButtons}>
              <Link className={`${styles.btn} ${styles.btnCta}`} to="/register">
                Create free account →
              </Link>
              <a
                className={`${styles.btn} ${styles.btnGhost}`}
                href={WHATSAPP}
                target="_blank"
                rel="noreferrer"
              >
                Chat with us
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* ── Contact ── */}
      <section id="contact" className={styles.band}>
        <div className={`${styles.contactGrid}`} style={{ maxWidth: 1280, margin: '0 auto' }}>
          <div data-reveal="">
            <div className={styles.eyebrow} style={{ color: ORANGE }}>CONTACT</div>
            <h2 className={styles.h2}>Get in touch</h2>
            <p className={styles.body} style={{ fontSize: 16.5 }}>
              Have questions or need help? Our local team is ready to assist you in Swahili or
              English.
            </p>
          </div>

          <div className={styles.contactCards}>
            {CONTACTS.map((c) => {
              const Tag = c.href ? 'a' : 'div';
              return (
                <Tag
                  key={c.label}
                  className={styles.contactCard}
                  data-reveal=""
                  {...(c.href
                    ? { href: c.href, target: c.href.startsWith('http') ? '_blank' : undefined, rel: 'noreferrer' }
                    : {})}
                >
                  <span className={styles.contactTile} style={{ background: c.accent }}>
                    <c.icon size={21} color={onAccent(c.accent)} />
                  </span>
                  <div className={styles.contactLabel}>{c.label}</div>
                  <div className={styles.contactValue} style={{ whiteSpace: 'pre-line' }}>
                    {c.value}
                  </div>
                </Tag>
              );
            })}
          </div>
        </div>
      </section>

      {/* ── Footer ── */}
      <footer className={styles.footer}>
        <div className={styles.footerGrid}>
          <div>
            <span className={styles.brand} style={{ color: '#fff' }}>
              <img src="/moinfotech-logo.png" alt="" />
              <span className={styles.wordmark}>MoBilling</span>
            </span>
            <p className={styles.footerBlurb}>
              Billing, hosting automation and .tz domain registration — the WHMCS-style platform
              built for East African businesses. White-label ready.
            </p>
          </div>

          <div>
            <div className={styles.footerLabel}>NAVIGATION</div>
            <div className={styles.footerLinks}>
              <a href="#features">Features</a>
              <a href="#hosting">Hosting &amp; Domains</a>
              <a href="#reseller">Reseller</a>
              <a href="#pricing">Pricing &amp; self-hosted</a>
              <a href="#faq">FAQ</a>
              <Link to="/license-agreement">Licence agreement</Link>
            </div>
          </div>

          <div>
            <div className={styles.footerLabel}>CONTACT US</div>
            <div className={styles.footerLinks}>
              <a href={`mailto:${EMAIL}`}>{EMAIL}</a>
              <a href="tel:+255689011111">{PHONE}</a>
              <a href={WHATSAPP} target="_blank" rel="noreferrer">WhatsApp</a>
              <span>Kibaha, Tanzania</span>
            </div>
          </div>
        </div>

        <div className={styles.footerBar}>
          <span>© {new Date().getFullYear()} MOBILLING. ALL RIGHTS RESERVED.</span>
          <span>
            POWERED BY <a href="https://moinfo.co.tz" target="_blank" rel="noreferrer">MOINFOTECH</a>
          </span>
        </div>
      </footer>

      <a
        className={styles.floatWa}
        href={WHATSAPP}
        target="_blank"
        rel="noreferrer"
        aria-label="Chat with us on WhatsApp"
      >
        <IconBrandWhatsapp size={26} />
      </a>
    </div>
  );
}

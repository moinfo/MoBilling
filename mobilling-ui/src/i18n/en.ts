import type { Translations } from './types';

/**
 * Portal strings, English.
 *
 * Covers the screens a customer meets first — login, the sidebar and the
 * dashboard's attention band. The rest of the portal is still hardcoded
 * English; add keys here as each screen is converted.
 */
export const en: Translations = {
  // ── Login ────────────────────────────────────────────────────────────
  'login.eyebrow': 'CLIENT AREA',
  'login.heading': 'Sign in',
  'login.sub': 'Manage domains, hosting, invoices and tickets.',
  'login.identifier': 'EMAIL OR PHONE',
  'login.required': 'REQUIRED',
  'login.identifierPlaceholder': 'you@company.com or 0712345678',
  'login.password': 'PASSWORD',
  'login.forgot': 'FORGOT?',
  'login.passwordPlaceholder': 'Your password',
  'login.show': 'SHOW',
  'login.hide': 'HIDE',
  'login.remember': 'Keep me signed in',
  'login.security': 'TLS 1.3 · 2FA READY',
  'login.submit': 'Sign in',
  'login.submitting': 'Signing in…',
  'login.needHelp': 'Need help?',
  'login.backTo': 'Back to',
  'login.newHere': 'New to',
  'login.createAccount': 'Create an account',
  'login.failed': 'Login failed',
  'login.invalid': 'Invalid credentials',
  'login.verifyTitle': 'Verification required',
  'login.verifyMessage':
    'A verification code has been sent to your email — finish setting up your account.',

  // Brand panel
  'login.brandHeadline': 'Everything you run with us, in one place.',
  'login.perkDomains': 'Domains',
  'login.perkDomainsDesc':
    'Register, renew and manage your .tz domains, nameservers and EPP codes.',
  'login.perkHosting': 'Hosting',
  'login.perkHostingDesc': 'One-click cPanel login, disk and bandwidth usage, upgrades.',
  'login.perkBilling': 'Billing',
  'login.perkBillingDesc':
    'Invoices, statements and receipts. Pay by mobile money or card.',
  'login.perkSupport': 'Support',
  'login.perkSupportDesc':
    'Open a ticket and track it, 24/7, with a team in your time zone.',
  'login.platformStatus': 'PLATFORM STATUS',
  'login.operational': 'All systems operational',
  'login.uptimeGuarantee': 'UPTIME GUARANTEE',
  'login.cpanel': 'CPANEL',
  'login.cpanelDesc': 'Manage files & databases',
  'login.webmail': 'WEBMAIL',
  'login.webmailDesc': 'Read your email',
  'login.privacy': 'PRIVACY',
  'login.terms': 'TERMS',

  // ── Sidebar ──────────────────────────────────────────────────────────
  'nav.overview': 'Overview',
  'nav.services': 'Services',
  'nav.billing': 'Billing',
  'nav.support': 'Support',
  'nav.account': 'Account',
  'nav.dashboard': 'Dashboard',
  'nav.news': 'News',
  'nav.myHosting': 'My Hosting',
  'nav.myDomains': 'My Domains',
  'nav.productsServices': 'Products & Services',
  'nav.subscriptions': 'Subscriptions',
  'nav.orderServices': 'Order Services',
  'nav.invoices': 'Invoices',
  'nav.payments': 'Payments',
  'nav.quotations': 'Quotations',
  'nav.creditNotes': 'Credit Notes',
  'nav.statement': 'Statement',
  'nav.tickets': 'Support Tickets',
  'nav.knowledgebase': 'Knowledgebase',
  'nav.profile': 'Profile',
  'nav.portalUsers': 'Portal Users',
  'nav.signOut': 'Sign out',
  'nav.operational': 'ALL SYSTEMS OPERATIONAL',

  // ── Dashboard attention band ─────────────────────────────────────────
  'attention.title': 'NEEDS YOUR ATTENTION',
  'attention.invoicesOverdueOne': 'invoice is overdue',
  'attention.invoicesOverdueMany': 'invoices are overdue',
  'attention.unpaidOne': 'unpaid invoice',
  'attention.unpaidMany': 'unpaid invoices',
  'attention.settleNote': 'Settle these to keep your services active',
  'attention.unpaidTotal': 'unpaid in total · settle to keep services active',
  'attention.viewInvoices': 'View invoices',
  'attention.domainExpiresOne': 'domain expires soon',
  'attention.domainExpiresMany': 'domains expire soon',
  'attention.domainNote': 'Within the next 45 days · renew to avoid losing the name',
  'attention.renew': 'Renew',

  // ── Disk usage ───────────────────────────────────────────────────────
  'disk.notSynced': 'Usage not synced',
  'disk.used': 'used',
  'disk.unlimited': 'unlimited',
};

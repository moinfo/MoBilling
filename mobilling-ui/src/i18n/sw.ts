import type { Translations } from './types';

/** Portal strings, Swahili. Mirrors the key set in en.ts. */
export const sw: Translations = {
  // ── Login ────────────────────────────────────────────────────────────
  'login.eyebrow': 'ENEO LA MTEJA',
  'login.heading': 'Ingia',
  'login.sub': 'Simamia vikoa, hosting, ankara na tiketi.',
  'login.identifier': 'BARUA PEPE AU SIMU',
  'login.required': 'INAHITAJIKA',
  'login.identifierPlaceholder': 'wewe@kampuni.com au 0712345678',
  'login.password': 'NENOSIRI',
  'login.forgot': 'UMESAHAU?',
  'login.passwordPlaceholder': 'Nenosiri lako',
  'login.show': 'ONYESHA',
  'login.hide': 'FICHA',
  'login.remember': 'Nikumbuke',
  'login.security': 'TLS 1.3 · TAYARI KWA 2FA',
  'login.submit': 'Ingia',
  'login.submitting': 'Inaingia…',
  'login.needHelp': 'Unahitaji msaada?',
  'login.backTo': 'Rudi',
  'login.newHere': 'Mgeni kwa',
  'login.createAccount': 'Fungua akaunti',
  'login.failed': 'Kuingia kumeshindikana',
  'login.invalid': 'Taarifa si sahihi',
  'login.verifyTitle': 'Uthibitisho unahitajika',
  'login.verifyMessage':
    'Msimbo wa uthibitisho umetumwa kwenye barua pepe yako — kamilisha kuweka akaunti yako.',

  // Brand panel
  'login.brandHeadline': 'Kila kitu unachoendesha nasi, mahali pamoja.',
  'login.perkDomains': 'Vikoa',
  'login.perkDomainsDesc':
    'Sajili, hifadhi na simamia vikoa vyako vya .tz, nameservers na misimbo ya EPP.',
  'login.perkHosting': 'Hosting',
  'login.perkHostingDesc':
    'Ingia cPanel kwa mbofyo mmoja, ona matumizi ya hifadhi na bandwidth, pandisha kiwango.',
  'login.perkBilling': 'Malipo',
  'login.perkBillingDesc':
    'Ankara, taarifa na risiti. Lipa kwa pesa za simu au kadi.',
  'login.perkSupport': 'Msaada',
  'login.perkSupportDesc':
    'Fungua tiketi na uifuatilie, 24/7, na timu iliyo katika saa moja na wewe.',
  'login.platformStatus': 'HALI YA MFUMO',
  'login.operational': 'Mifumo yote inafanya kazi',
  'login.uptimeGuarantee': 'DHAMANA YA UPATIKANAJI',
  'login.cpanel': 'CPANEL',
  'login.cpanelDesc': 'Simamia faili na hifadhidata',
  'login.webmail': 'WEBMAIL',
  'login.webmailDesc': 'Soma barua pepe zako',
  'login.privacy': 'FARAGHA',
  'login.terms': 'MASHARTI',

  // ── Sidebar ──────────────────────────────────────────────────────────
  'nav.overview': 'Muhtasari',
  'nav.services': 'Huduma',
  'nav.billing': 'Malipo',
  'nav.support': 'Msaada',
  'nav.account': 'Akaunti',
  'nav.dashboard': 'Dashibodi',
  'nav.news': 'Habari',
  'nav.myHosting': 'Hosting Yangu',
  'nav.myDomains': 'Vikoa Vyangu',
  'nav.productsServices': 'Bidhaa na Huduma',
  'nav.subscriptions': 'Michango',
  'nav.orderServices': 'Agiza Huduma',
  'nav.invoices': 'Ankara',
  'nav.payments': 'Malipo',
  'nav.quotations': 'Nukuu',
  'nav.creditNotes': 'Hati za Mikopo',
  'nav.statement': 'Taarifa ya Akaunti',
  'nav.tickets': 'Tiketi za Msaada',
  'nav.knowledgebase': 'Maktaba ya Maarifa',
  'nav.profile': 'Wasifu',
  'nav.portalUsers': 'Watumiaji',
  'nav.signOut': 'Toka',
  'nav.operational': 'MIFUMO YOTE INAFANYA KAZI',

  // ── Dashboard attention band ─────────────────────────────────────────
  'attention.title': 'INAHITAJI UANGALIZI WAKO',
  'attention.invoicesOverdueOne': 'ankara imechelewa',
  'attention.invoicesOverdueMany': 'ankara zimechelewa',
  'attention.unpaidOne': 'ankara ambayo haijalipwa',
  'attention.unpaidMany': 'ankara ambazo hazijalipwa',
  'attention.settleNote': 'Lipa hizi ili huduma zako ziendelee kufanya kazi',
  'attention.unpaidTotal': 'hazijalipwa kwa jumla · lipa ili huduma ziendelee',
  'attention.viewInvoices': 'Angalia ankara',
  'attention.domainExpiresOne': 'kikoa kinaisha muda karibuni',
  'attention.domainExpiresMany': 'vikoa vinaisha muda karibuni',
  'attention.domainNote': 'Ndani ya siku 45 · hifadhi ili usipoteze jina',
  'attention.renew': 'Hifadhi upya',

  // ── Disk usage ───────────────────────────────────────────────────────
  'disk.notSynced': 'Matumizi hayajasasishwa',
  'disk.used': 'yametumika',
  'disk.unlimited': 'bila kikomo',
};

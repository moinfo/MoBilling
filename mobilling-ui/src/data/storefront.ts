/**
 * Storefront layout for the public order pages.
 *
 * The moinfo.co.tz marketing site links here as
 *   /order/<category>?plan=<slug>[&coupon=CODE]
 * so this file is the other half of that contract. Its counterpart lives in
 * the marketing repo at src/data/mobilling.ts (PLAN_SLUG_TO_PRODUCT) — keep
 * the two in step when products are renamed.
 *
 * Why a hardcoded map instead of the API's own grouping: product_services has
 * no slug column, and its `category` column holds provisioning buckets
 * ("cpanel", "whmcs"), not customer-facing groups. So we group by product name
 * here and resolve a slug to the CatalogProduct whose `name` matches.
 */

export interface StorefrontPlan {
  /** URL slug used by the marketing site. */
  slug: string;
  /** Exact `name` of the product in MoBilling, as migrated from WHMCS. */
  product: string;
}

export interface StorefrontCategory {
  slug: string;
  label: string;
  description: string;
  plans: StorefrontPlan[];
}

export const STOREFRONT: StorefrontCategory[] = [
  {
    slug: 'web-hosting',
    label: 'Web Hosting',
    description: 'cPanel hosting with free SSL, daily backups and 24/7 support.',
    plans: [
      { slug: 'university', product: 'Web Hosting University' },
      { slug: 'personal', product: 'Web Hosting Personal' },
      { slug: 'professional', product: 'Web Hosting Professional' },
      { slug: 'premier', product: 'Web Hosting Premier' },
      { slug: 'plus', product: 'Web Hosting Plus' },
    ],
  },
  {
    slug: 'email-hosting',
    label: 'Business Email',
    description: 'Professional email on your own domain, with webmail and IMAP.',
    plans: [
      { slug: 'starter', product: 'Business Email Starter' },
      { slug: 'medium', product: 'Business Email Medium' },
      { slug: 'premier', product: 'Business Email Premier' },
      { slug: 'plus', product: 'Business Email Plus' },
    ],
  },
  {
    slug: 'vps',
    label: 'Linux VPS',
    description: 'Dedicated resources with full root access.',
    plans: [
      { slug: 'linux-mit-500', product: 'Linux MIT 500' },
      { slug: 'linux-mit-600', product: 'Linux MIT 600' },
      { slug: 'linux-mit-700', product: 'Linux MIT 700' },
    ],
  },
  {
    slug: 'dedicated-server',
    label: 'Dedicated Servers',
    description: 'A whole physical server, tuned for demanding workloads.',
    plans: [
      { slug: 'linux-server-mit-450', product: 'Linux Server - MIT 450' },
      { slug: 'linux-server-mit-550', product: 'Linux Server - MIT 550' },
      { slug: 'linux-server-mit-650', product: 'Linux Server - MIT 650' },
    ],
  },
  {
    slug: 'reseller-hosting',
    label: 'Reseller Hosting',
    description: 'Start your own hosting business with WHM and white-label support.',
    plans: [
      { slug: 'linux-reseller-starter', product: 'Linux Reseller Starter' },
      { slug: 'linux-reseller-medium', product: 'Linux Reseller Medium' },
      { slug: 'linux-reseller-premium', product: 'Linux Reseller Premium' },
      { slug: 'linux-reseller-business', product: 'Linux Reseller Business' },
    ],
  },
  {
    slug: 'website-design',
    label: 'Website Design',
    description: 'Designed, built and delivered by our team.',
    plans: [
      { slug: 'reseller-design', product: 'Reseller Design' },
      { slug: 'static-website-design', product: 'Static Website Design' },
      { slug: 'ecommerce-website-design', product: 'Ecommerce Website Design' },
    ],
  },
];

export const findCategory = (slug?: string) =>
  STOREFRONT.find((c) => c.slug === slug);

/** Product name a `?plan=` slug refers to, if the category offers it. */
export function productNameForPlan(
  category: StorefrontCategory,
  planSlug?: string | null,
): string | undefined {
  if (!planSlug) return undefined;
  return category.plans.find((p) => p.slug === planSlug)?.product;
}

export const formatTsh = (amount: number) =>
  `TSh ${Number(amount).toLocaleString('en-US', { maximumFractionDigits: 2 })}`;

export const cycleLabel = (cycle: string | null) =>
  ({
    monthly: '/mo',
    quarterly: '/quarter',
    half_yearly: '/6 months',
    yearly: '/yr',
    once: '',
  }[cycle ?? 'once'] ?? '');

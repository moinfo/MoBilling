import api from './axios';

/**
 * Public, unauthenticated storefront endpoints — same purpose as moinfo.co.tz's
 * own domain search box, resolved by the visiting Host so a white-label
 * reseller's landing page searches/prices against their own tenant.
 */
export interface DomainCheckResult {
  name: string;
  offered: boolean;
  available: boolean | null;
  message?: string;
  pricing?: {
    tld: string;
    register_price: number;
    transfer_price: number;
    years_min: number;
    years_max: number;
  };
}

export const checkPublicDomain = (name: string) =>
  api.get<DomainCheckResult>('/public/domains/check', { params: { name } });

export interface CatalogPlan {
  name: string;
  price: number;
  billing_cycle: string;
  description: string | null;
}

export interface CatalogTld {
  tld: string;
  price: number;
}

export interface PublicCatalog {
  hosting: CatalogPlan[];
  email: CatalogPlan[];
  linode: CatalogPlan[];
  tlds: CatalogTld[];
}

export const getPublicCatalog = () => api.get<PublicCatalog>('/public/catalog');

import { useEffect, useState } from 'react';
import api from './api/axios';

/**
 * White-label branding. When the app is visited on a tenant's custom domain
 * (tenants.custom_domain), the portal renders under that tenant's name/logo.
 * On the default hosts it stays MoBilling/Moinfotech.
 */
export interface Branding {
  branded: boolean;
  name?: string;
  logo_url?: string | null;
  website?: string | null;
  email?: string | null;
  phone?: string | null;
}

const DEFAULT_HOSTS = ['mobilling.co.tz', 'www.mobilling.co.tz', 'localhost', '127.0.0.1'];
const CACHE_KEY = 'wl_branding_v1';

export const isBrandedHost = () => !DEFAULT_HOSTS.includes(window.location.hostname);

let inFlight: Promise<Branding> | null = null;

export function loadBranding(): Promise<Branding> {
  if (!isBrandedHost()) return Promise.resolve({ branded: false });

  // session cache avoids logo flicker on every navigation
  try {
    const cached = sessionStorage.getItem(CACHE_KEY);
    if (cached) return Promise.resolve(JSON.parse(cached));
  } catch { /* ignore */ }

  if (!inFlight) {
    inFlight = api.get<Branding>('/public/branding')
      .then((res) => {
        const b = res.data?.branded ? res.data : { branded: false };
        try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(b)); } catch { /* ignore */ }
        return b;
      })
      .catch(() => ({ branded: false as const }));
  }
  return inFlight;
}

export function useBranding(): Branding {
  const [branding, setBranding] = useState<Branding>({ branded: false });

  useEffect(() => {
    let alive = true;
    loadBranding().then((b) => {
      if (!alive) return;
      setBranding(b);
      if (b.branded && b.name) document.title = `${b.name} — Client Area`;
    });
    return () => { alive = false; };
  }, []);

  return branding;
}

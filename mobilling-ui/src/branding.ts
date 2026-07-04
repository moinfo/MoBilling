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
}

const DEFAULT_HOSTS = ['mobilling.co.tz', 'www.mobilling.co.tz', 'localhost', '127.0.0.1'];
const CACHE_KEY = 'wl_branding_v1';
const CACHE_TTL_MS = 30 * 60 * 1000; // 30 min — a rename/logo change shows within half an hour

export const isBrandedHost = () => !DEFAULT_HOSTS.includes(window.location.hostname);

/** Read a still-fresh cached brand for THIS host (used to avoid a flash of default). */
function cachedBranding(): Branding | null {
  try {
    const raw = sessionStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const { host, at, data } = JSON.parse(raw);
    if (host !== window.location.hostname || Date.now() - at > CACHE_TTL_MS) return null;
    return data as Branding;
  } catch { return null; }
}

let inFlight: Promise<Branding> | null = null;

export function loadBranding(): Promise<Branding> {
  if (!isBrandedHost()) return Promise.resolve({ branded: false });

  const cached = cachedBranding();
  if (cached) return Promise.resolve(cached);

  if (!inFlight) {
    inFlight = api.get<Branding>('/public/branding')
      .then((res) => {
        const b = res.data?.branded ? res.data : { branded: false };
        try {
          sessionStorage.setItem(CACHE_KEY, JSON.stringify({ host: window.location.hostname, at: Date.now(), data: b }));
        } catch { /* ignore */ }
        return b;
      })
      .catch(() => ({ branded: false as const }))
      .finally(() => { inFlight = null; });
  }
  return inFlight;
}

export function useBranding(): Branding {
  // Seed synchronously from a fresh cache so a branded portal never flashes
  // the default MoBilling brand on navigation.
  const [branding, setBranding] = useState<Branding>(() => cachedBranding() ?? { branded: false });

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

# White-Label Custom Domains

Tenants can serve the client portal on their own domain (e.g.
`clients.acmehost.co.tz`), branded with their company name and logo. Their
customers never see MoBilling/Moinfotech.

## How it works

1. **Tenant** sets the domain in *Settings → Company → Custom Portal Domain*
   (stored in `tenants.custom_domain`, unique, validated hostname).
2. **Tenant** points the domain's DNS **A record** at the MoBilling server.
3. **We** activate it (nginx vhost + Let's Encrypt):

   ```bash
   sudo /var/www/html/MoBilling/scripts/enable-custom-domain.sh clients.acmehost.co.tz
   ```

That's it — no rebuild or deploy needed. At runtime:

- The SPA uses a **relative** API base (`/api`), so every request carries the
  custom hostname.
- On boot the SPA calls `GET /api/public/branding` (public); the backend
  matches the `Host` header against `tenants.custom_domain` and returns the
  tenant's name/logo/website (presentation fields only).
- Branded surfaces: `/portal/login`, `/portal/register`, the portal shell
  header, and the browser title. The MoBilling marketing landing page
  redirects to `/portal/login` on branded hosts.
- **Signups on a branded domain belong to that tenant**: `PortalAuthController`
  resolves the tenant by `Host` before falling back to
  `PORTAL_DEFAULT_TENANT_ID`, and scopes existing-client email matching to
  that tenant.

## Files

- `app/Http/Controllers/PublicBrandingController.php` — host → branding
- `mobilling-ui/src/branding.ts` — `useBranding()` hook (session-cached)
- `scripts/enable-custom-domain.sh` — nginx vhost + certbot
- `config/portal.php` — default signup tenant (fallback for mobilling.co.tz)

## Current limitations / future work

- Email links (invoice notifications, OTPs) still point at mobilling.co.tz —
  per-tenant portal URLs in notifications are a future enhancement.
- Staff area on a branded domain works but is unbranded by design; staff
  should keep using mobilling.co.tz.
- SSL issuance is one manual script run per domain (needs DNS already
  pointed here). Certbot auto-renews after that.

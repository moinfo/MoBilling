# Self-Hosted Licensing — Manual Test Guide

Step-by-step checklist for testing the whole self-hosted product line built
this session: pricing catalog → license issuance → installer → daily
re-validation → lockout screen → update notifications → license agreement.

This is an internal QA document, not customer-facing — it stays out of the
distributable package (`scripts/package-release.sh` only archives
`unganisha-api` and `mobilling-ui`, not root-level files like this one).

## Before you start

**Two environments are involved, and you can't avoid that:**

- **This production instance (mobilling.co.tz)** — safe for everything
  admin-side: License Plans, Licenses, Releases, the License Agreement
  page, and even the domain-lock behavior (via `curl` against the public
  validate endpoint, Phase 4 below). None of this touches real tenants.
- **A separate, genuinely fresh server** — required for Phase 6 onward.
  `/install` permanently locks itself out the moment a tenant exists in the
  database, and this instance already has real tenants — confirmed live,
  `POST /api/install/database` returns 403 "This MoBilling install is
  already set up." There is no way to test the installer against
  mobilling.co.tz itself. Cheapest option: a $5–6/mo VPS (or a spare
  machine, or a local VM) with a domain or subdomain pointed at it — you
  need PHP 8.2+, MySQL, and Nginx. Build the package to put on it with:

  ```bash
  cd /var/www/html/MoBilling
  ./scripts/package-release.sh 1.0.0-test
  ```

  This produces `../mobilling-releases/mobilling-1.0.0-test.zip`. Follow
  `scripts/package-templates/INSTALL.md` (included in the zip too) to get
  it running on the test server before Phase 6.

You'll need super-admin access to `/admin` on mobilling.co.tz throughout.

---

## Phase 1 — Pricing catalog (License Plans)

*Production admin UI — safe.*

1. Go to `https://mobilling.co.tz/admin/license-plans`.
2. Confirm three rows exist: **MoBilling Lite**, **MoBilling Reseller**,
   **MoBilling Complete** — with the monthly/quarterly/semi-annual/annual
   prices you configured earlier.
3. Edit one plan's price (e.g. bump the annual price by 1,000), click
   **Save**, confirm the table updates.
4. Confirm the public mirror picked it up:
   ```bash
   curl -s https://mobilling.co.tz/api/license-plans | python3 -m json.tool
   ```
5. Reload `https://mobilling.co.tz/` and scroll to the **"Prefer to run it
   on your own server?"** section — confirm the new price shows there too
   (hard-refresh if you still see the old figure, browser cache).
6. Revert the price back if you only changed it for this test.

## Phase 2 — Issue & manage licenses

*Production admin UI — safe. Issue two throwaway licenses: one for the
curl-only domain-lock tests in Phase 4, one reserved for the real
installer test in Phase 6, so their state doesn't cross-contaminate.*

1. Go to `/admin/licenses`, click **Issue License**.
2. Fill in: Customer Name `TEST — curl domain-lock`, an email, Package
   `MoBilling Lite`, Start Date = today, Billing Period = `Monthly`.
   Confirm the expiry preview shows exactly one month from today as you
   change the billing period. Amount Paid should pre-fill from the
   catalog price (still editable). Click **Issue License**.
3. Confirm the new row: Domain column empty (not yet bound), Status
   `Active`, Expires = today + 1 month.
4. Click the copy icon next to the License Key — save it somewhere; call
   it **KEY-CURL**.
5. Repeat steps 1–4 for a second license, Customer Name
   `TEST — installer`, any package/period. Call its key **KEY-INSTALL**.
6. On **KEY-CURL**: click the teal refresh icon (tooltip "Renew (extend
   expiry)"). Confirm **Extend From** defaults to the license's *current*
   expiry date, not today. Pick a new billing period, confirm the new
   expiry preview is correct, click **Renew**. Confirm the table's
   Expires date updated and Amount Paid recorded the renewal payment.
7. On **KEY-CURL**: click the pencil (Edit) icon. Confirm only
   Customer Name / Customer Email / Status / Notes are editable — no
   billing fields. Change the Notes field, Save, confirm it stuck.

## Phase 3 — License Agreement page

*Production, public — safe.*

1. Visit `https://mobilling.co.tz/license-agreement` directly (no login
   needed).
2. Confirm it shows a version + effective date line and the full
   agreement text below it.
3. From the landing page, scroll to the self-hosted section and confirm
   the small "governed by the MoBilling License Agreement" line at the
   bottom links to the same page.

## Phase 4 — Domain lock & rejection paths

*Production, via `curl` against the public validate endpoint — no second
server needed, since the endpoint takes `domain` as a plain POST field
rather than reading the request's actual Host header. Uses **KEY-CURL**
from Phase 2.*

1. First call binds the domain:
   ```bash
   curl -s -X POST https://mobilling.co.tz/api/license/validate \
     -H "Content-Type: application/json" \
     -d '{"license_key":"KEY-CURL","domain":"test1.example.com","app_version":"1.0.0"}' \
     -w "\nHTTP %{http_code}\n"
   ```
   Expect `valid:true`. Refresh `/admin/licenses` — the row's Domain
   column now shows `test1.example.com`, Last Check-in updated.
2. Repeat the exact same call — should still succeed (same domain is
   idempotent).
3. Call again with a *different* domain:
   ```bash
   curl -s -X POST https://mobilling.co.tz/api/license/validate \
     -H "Content-Type: application/json" \
     -d '{"license_key":"KEY-CURL","domain":"different.example.com","app_version":"1.0.0"}' \
     -w "\nHTTP %{http_code}\n"
   ```
   Expect **HTTP 403**, `"This license is already active on a different
   domain."`
4. In `/admin/licenses`, click the unbind icon (tooltip "Unbind domain
   (move to a new install)") on this license. Confirm the Domain column
   clears.
5. Re-run the step-3 call with `different.example.com` — it should now
   succeed and rebind to that domain.
6. Set the license to Suspended (Edit → Status → Suspended → Save). Run
   any validate call against it — expect **HTTP 403**, `"This license has
   been suspended. Contact support."`
7. Set it back to Active when done. (Testing the expiry-based 403 requires
   backdating `expires_at`, which isn't reachable through the admin UI by
   design — Renew only ever computes forward. Low priority to test by hand
   since it shares the same rejection branch you already just confirmed
   for suspension.)

## Phase 5 — Stand up the fresh test server

*One-time setup, on your separate VPS/VM, not this server.*

1. Point a domain or subdomain's A record at the test server.
2. `unzip mobilling-1.0.0-test.zip` there and follow its `INSTALL.md`
   (nginx vhost from `nginx.conf.example`, permissions, SSL via certbot).
3. Confirm `https://<test-domain>/api/install/status` returns
   `{"installed":false}` before continuing.

## Phase 6 — Run the Installer end-to-end

*On the fresh test server, in a browser. Uses **KEY-INSTALL** from Phase 2.*

1. Visit `https://<test-domain>/install`.
2. **Requirements step**: confirm every row shows a green check (PHP
   version, each extension, each writable path, `.env` writable). Fix
   anything red and click **Re-check** until `all_ok`.
3. **Database step**: enter the MySQL credentials for an empty database
   you created on the test server. Click **Connect & Create Tables**.
   Confirm it advances (this step runs migrations).
4. **License step**: paste **KEY-INSTALL**, click **Activate**. Confirm
   it advances — this is the same `checkLicense()` dry-run that binds
   nothing yet.
5. **Admin step**: fill in Company Name/Email/Currency, your name/email/
   password. Confirm the **"I have read and agree to the MoBilling
   License Agreement"** checkbox — try submitting without checking it
   first and confirm you get "You must accept the License Agreement to
   continue." Check it, click **Finish Setup**.
6. Confirm the **Installation Complete** screen, then **Go to Login** and
   log in with the admin account you just created.
7. Back on mobilling.co.tz, refresh `/admin/licenses` — **KEY-INSTALL**'s
   Domain column should now show the test domain, Status Active.
8. Confirm `/install` is now permanently locked: visit
   `https://<test-domain>/install` again — expect the "Already Installed"
   screen, and `GET /api/install/status` → `{"installed":true}`.
9. On the test server, check `.env` — confirm `APP_URL` was actually set
   to `https://<test-domain>` (not left at `http://localhost`). This
   matters for Phase 8: `license:check` validates using this value, so if
   it's wrong every scheduled check will look like a domain mismatch and
   deactivate the tenant immediately, with no grace period.

## Phase 7 — License Status tab (on the fresh install)

1. Logged in on the test install, go to **Settings → License** (only
   visible because this tenant is self-hosted).
2. Confirm: masked License Key (`MB-****-****-****-XXXX` style), Status
   `active`, Expires date matching what you set in Phase 2/6, Last
   Checked = install time.
3. Confirm the **Software Updates** card shows "Installed Version:
   1.0.0-test" (or whatever you passed to `package-release.sh`) and
   "Latest Version" once you've done Phase 9 — before that, if no release
   is published yet, this card should simply not render.

## Phase 8 — Daily re-validation & the grace period

*Run these on the test server's shell (not production).*

1. Trigger a check manually:
   ```bash
   php artisan license:check
   ```
   Expect: `Checked 1 self-hosted tenant(s): 1 valid, 0 deactivated, 0
   reactivated, 0 unreachable.` Confirm `license_last_valid_at` on the
   test install advanced (check Settings → License → Last Checked).
2. **Explicit-rejection path**: on mobilling.co.tz, suspend
   **KEY-INSTALL** (`/admin/licenses` → Edit → Status → Suspended). On the
   test server, run `php artisan license:check` again. Expect
   `1 deactivated`, and confirm you're now locked out: reload the test
   install in the browser — expect a redirect to `/license-inactive`
   showing the masked key/status and a WhatsApp support button. Confirm
   `/license-status` is still reachable despite the lockout (that's the
   page rendering it).
3. Reactivate: set **KEY-INSTALL** back to Active on production. Run
   `php artisan license:check` on the test server again. Expect
   `1 reactivated`, and confirm the test install is usable again.
4. **Grace-period path** (optional, harder to force): temporarily block
   the test server's outbound access to mobilling.co.tz (e.g.
   `iptables -A OUTPUT -d <mobilling.co.tz IP> -j DROP`, or point
   `/etc/hosts` at a bad IP), run `license:check` — expect
   `1 unreachable` and the tenant to stay active (grace period, default
   10 days). Remove the block afterward and confirm a normal check
   restores `valid`.

## Phase 9 — Check for Updates

1. On mobilling.co.tz, go to `/admin/releases`, click **Publish Release**.
   Version `1.1.0`, today's date, a short changelog, a Download URL (can
   be a placeholder for this test), leave **Active** on. Publish.
2. Confirm the public endpoint:
   ```bash
   curl -s https://mobilling.co.tz/api/releases/latest | python3 -m json.tool
   ```
3. On the test install, go to **Settings → License**. Confirm the
   **Software Updates** card now shows "Update available" (yellow badge),
   Installed Version `1.0.0-test` vs Latest Version `1.1.0`, the
   changelog text, and a **Download Update** button linking to the URL
   you entered.
4. Set the release back to inactive (or delete it) when done, unless you
   want it to keep showing for real future self-hosted customers.

## Phase 10 — Regression check on real tenants

*Production — confirms none of this affected existing paying tenants.*

1. Log in as a normal SaaS tenant (not self-hosted). Confirm normal
   access, no `/license-inactive` redirect, no License tab under
   Settings, and the **Subscription** nav item is still visible (it's
   hidden only for `is_self_hosted` tenants).
2. `php artisan license:check` on **this** production instance should
   report `Checked 0 self-hosted tenant(s)` — confirms it never touches
   real SaaS tenants here.

## Cleanup

1. On `/admin/licenses`, delete or suspend **KEY-CURL** and
   **KEY-INSTALL** once testing is done (real customer keys should be the
   only active ones on the catalog going forward).
2. Tear down the test VPS/VM, or leave it running if you want to keep it
   as a permanent staging environment for future test cycles — in which
   case, re-running `/install` there is not possible once you've
   completed Phase 6; you'd need a fresh database/server to re-test the
   installer itself again.

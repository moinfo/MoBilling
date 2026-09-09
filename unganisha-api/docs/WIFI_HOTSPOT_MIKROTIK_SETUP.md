# WiFi Hotspot — MikroTik Router Setup Runbook

> Step-by-step guide for connecting a physical MikroTik router to MoBilling's WiFi
> Hotspot Voucher Billing feature (`app/Services/Mikrotik/RouterOsService.php`,
> `MikrotikRouter` model). Written from a real end-to-end setup (MikroTik hAP ac lite,
> RB952Ui-5ac2nD, RouterOS v7) — every command here was actually run against a live
> router. Expect this to take **an hour or more** the first time; most of that is
> working through the checks in §8.

---

## 1. What you're building

```
Customer phone/laptop
      │  (WiFi, open/no password)
      ▼
MikroTik hotspot (captive portal)
      │  unauthenticated → only login.html + walled-garden domains reachable
      │  authenticated (voucher entered) → full internet
      ▼
Internet
```

```
MoBilling server ──(RouterOS API, port 8728)──► Router
                                                   │ used to create/remove
                                                   │ hotspot voucher users
                                                   │ (ProvisionWifiVoucherJob)
```

MoBilling never touches the router's WiFi/internet path — it only talks to the
RouterOS **API** (to create hotspot users when a voucher is paid for) and, optionally,
customizes the router's own **login.html** (branding + a "buy a voucher" link).

---

## 2. Prerequisites

- RouterOS v7.18+ (the Hotspot package was split out of the base install around
  this version — install it from **System → Packages** if `/ip hotspot` is missing).
- A LAN interface dedicated to the hotspot (don't reuse the router's management
  interface) — in this setup, `wlan1`.
- SSH enabled on the router (default) — needed for `scp` later (§7).
- A public IP or DDNS on the router **or** a way to reach it despite carrier NAT (§5).

---

## 3. Enable the Hotspot (device-mode restriction)

RouterOS v7 disables risky features by default (`mode=home`). Symptom: hotspot
users show `I` (Invalid) in `/ip hotspot print detail` with reason
`inactivated, not allowed by device-mode`.

```
/system device-mode update hotspot=yes
```

This requires a **physical confirmation within ~5 minutes** — power-cycle the
router (unplug/replug) or press its reset button briefly (not held). Re-check:

```
/system device-mode print
```

`hotspot` should now read `yes`.

---

## 4. Hotspot + DHCP interface setup

1. **Remove the hotspot interface from the bridge** if it was auto-added as a bridge
   slave — a DHCP server cannot run on a bridge-slave interface (error: *"DHCP server
   cannot run on slave interface!"*):
   ```
   /interface bridge port remove [find interface=wlan1]
   ```
2. Run the Hotspot setup wizard on that interface (WebFig: **IP → Hotspot → Hotspot
   Setup**, select `wlan1`), accepting defaults for the local address pool / DNS name
   unless you have a reason not to. This creates the DHCP server, the `default`
   hotspot server + profile, and the local IP (e.g. `10.5.50.1/24`).
3. **Open (unauthenticated) WiFi** — all access control happens at the hotspot login
   page, not at the WiFi layer:
   ```
   /interface wireless security-profiles add name=open mode=none
   /interface wireless set wlan1 security-profile=open
   ```

---

## 5. Reaching the router from the MoBilling server

The server needs to reach the router's RouterOS API (port 8728) from the internet.
Two obstacles came up in practice:

### 5a. Firewall — default drop rule

RouterOS's factory-default firewall has `chain=input action=drop
in-interface-list=!LAN` blocking all WAN-sourced traffic to router services. Add a
narrow accept rule **before** it:

```
/ip firewall filter print                     ; find the drop rule's position/comment
/ip firewall filter add chain=input action=accept src-address=<MOBILLING_SERVER_IP> \
    protocol=tcp dst-port=8728 place-before=[find comment="<drop rule's comment>"]
```

Prefer `place-before=[find comment=...]` over a numeric index — numeric positions
shift as other rules are added/removed.

### 5b. Carrier-level inbound blocking → WireGuard tunnel

Many mobile/4G-5G data plans (very common in Tanzania) block **inbound** connections
even when the router has a real public IP (no CGNAT) — confirmed by comparing the
router's own detected public IP (`/ip cloud print`) against an independent "what's my
IP" check from a device on the same network; matching IPs rule out CGNAT but not
carrier filtering. If port 8728 times out despite a correct firewall rule, this is
almost certainly why.

**Fix: a WireGuard tunnel, initiated outbound by the router** (carriers essentially
never block outbound):

On the **server**:
```
wg genkey | tee server_private.key | wg pubkey > server_public.key
# /etc/wireguard/wg0.conf
[Interface]
Address = 10.200.0.1/24
ListenPort = 51820
PrivateKey = <server_private.key>
SaveConfig = true

ufw allow 51820/udp
systemctl enable --now wg-quick@wg0
```

On the **router**:
```
/interface wireguard add name=wg0 listen-port=51820
/interface wireguard peers add interface=wg0 \
    public-key="<server_public_key>" \
    endpoint-address=<SERVER_PUBLIC_IP> endpoint-port=51820 \
    allowed-address=10.200.0.1/32 persistent-keepalive=25s
/ip address add address=10.200.0.2/24 interface=wg0
```

Back on the **server**, register the router's public key as a peer:
```
wg set wg0 peer <router_public_key> allowed-ips 10.200.0.2/32
```

Verify: `wg show` should show a recent handshake. Then add a **second** firewall
accept rule on the router scoped to the tunnel (different source address/interface
than the WAN-IP rule in §5a):
```
/ip firewall filter add chain=input action=accept src-address=10.200.0.1 \
    protocol=tcp dst-port=8728 place-before=[find comment="<drop rule's comment>"]
```

In MoBilling, the router's `host` field is then the **tunnel** address (`10.200.0.2`),
not the router's WAN/DDNS address.

> DDNS note: if the router's DDNS hostname (`/ip cloud print` → `dns-name`) doesn't
> resolve (`NXDOMAIN`), use the raw `public-address` from the same command instead —
> or just use the tunnel address once WireGuard is up, which sidesteps DNS entirely.

---

## 6. RouterOS API user

Create a dedicated API user (don't reuse `admin`):
```
/user group add name=mobilling-api policy=api,read,write,test
/user add name=mobilling-api password=<STRONG_PASSWORD> group=mobilling-api
```

In MoBilling: **WiFi Routers → Add Router** — `host` (tunnel or WAN IP per §5),
`api_port=8728`, `username`/`password` = the API user above, `use_tls=off` (plain
API; turn on + use port 8729 only if you've set up API-SSL). Click **Test
Connection** to confirm before creating any plans.

---

## 7. Branding the login page (optional)

The default `hotspot/login.html` is generic MikroTik branding. To customize it with
your own logo + a link to the MoBilling checkout page (see §9 for why that link is
needed):

1. **Don't paste large HTML into WebFig's file editor** — it has been observed to
   silently drop characters on paste for long lines (e.g. `font-weight:700;` →
   `font-weight:700`), corrupting the RouterOS template syntax
   (`$(if ...)`/`$(endif)`) and breaking the page. Use `scp` instead — it transfers
   bytes exactly.
2. Upload your logo (any PNG) and the edited `login.html` directly to their correct
   paths — RouterOS has no real folders, a file's "path" is just its name:
   ```bash
   scp mobilling-logo.png <user>@<router-ip>:hotspot/img/mobilling-logo.png
   scp login.html <user>@<router-ip>:hotspot/login.html
   ```
   If a file lands outside `hotspot/` (e.g. via WebFig's upload button, which drops
   files at the root), fix it without re-uploading: click the file in **WebFig →
   Files**, edit its **Name:** field to `hotspot/img/whatever.png`, Enter.
3. Keep every `$(...)` RouterOS template variable and the CHAP login `<script>` block
   in `login.html` untouched — only add markup, don't remove the existing form.

---

## 8. Walled garden — letting customers reach checkout before they've paid

**This is easy to miss and breaks the whole purchase flow if skipped.** Before a
customer logs in, the hotspot blocks *all* traffic except the login page itself —
including a "buy a voucher" link pointing at MoBilling, since that's still an
external site. Explicitly allow the domains a purchase needs:

```
/ip hotspot walled-garden add dst-host=mobilling.co.tz action=allow comment="MoBilling checkout"
/ip hotspot walled-garden add dst-host=*.mobilling.co.tz action=allow comment="MoBilling checkout wildcard"
/ip hotspot walled-garden add dst-host=pay.pesapal.com action=allow comment="Pesapal checkout"
/ip hotspot walled-garden add dst-host=*.pesapal.com action=allow comment="Pesapal wildcard"
```

(`pay.pesapal.com` is production — see `config/pesapal.php`; use
`cybqa.pesapal.com` instead if `PESAPAL_SANDBOX=true`.)

Provisioning itself (creating the hotspot user after payment) goes over the
RouterOS **API**, not through the customer's blocked connection, so it needs no
walled-garden entry.

---

## 9. Preventing one voucher being shared across many devices

RouterOS's hotspot **user profile** has a `shared-users` field — `1` limits a given
voucher username/password to one active device at a time. Check what your plans
actually use (`WifiPlan.hotspot_profile`; `null` falls back to the server's `default`
profile):

```
/ip hotspot user profile print
```

`default` ships with `shared-users=1` already — verify this is still true for
whatever profile your plans reference. If not:
```
/ip hotspot user profile set [find name="<profile>"] shared-users=1
```

This isn't airtight (multiple people can still take turns on one code), but it stops
mass simultaneous sharing.

---

## 10. Auto-login after payment

MoBilling can skip the "type your voucher code in" step entirely by sending the
customer's own browser straight to the router's local login endpoint right after
payment (`pages/public/WifiCheckout.tsx`'s `VoucherStatus`, using
`MikrotikRouter.local_login_host`). For this to work:

- Set **Local Hotspot IP** on the router in MoBilling (WiFi Routers → Edit) to the
  LAN-side address customers actually see on the hotspot (e.g. `10.5.50.1` — the
  hotspot interface's own IP from §4, **not** the tunnel/API `host` from §5).
- The router's hotspot login method must accept plain (non-CHAP) credentials via
  `GET /login?username=...&password=...` — true by default unless explicitly
  restricted in `/ip hotspot profile`.

If `local_login_host` is unset, or the redirect fails (customer already left the
WiFi), the success page falls back to showing the code for manual entry — nothing
breaks either way.

---

## Troubleshooting quick reference

| Symptom | Cause | Fix |
|---|---|---|
| `/ip hotspot print detail` shows `I` (Invalid), "not allowed by device-mode" | RouterOS v7 device-mode restriction | §3 |
| "DHCP server cannot run on slave interface!" | Hotspot interface still a bridge slave | §4.1 |
| Hotspot login page never appears, browser just times out | WiFi still password-protected, or hotspot not bound to the right interface | §4.3, re-run hotspot setup wizard |
| DDNS hostname → `NXDOMAIN` | DDNS not propagated/misconfigured | Use raw `public-address` from `/ip cloud print`, or the WireGuard tunnel address |
| MoBilling "Test Connection" → timeout, firewall rule looks correct | Carrier blocking inbound despite a real public IP | §5b — WireGuard tunnel |
| Login page shows raw `$(if ...)` template code instead of rendering | Corrupted paste via WebFig's file editor | §7 — use `scp`, never paste large HTML into WebFig |
| Customer can't reach the "buy a voucher" link before paying | Walled garden not configured | §8 |
| Voucher code being shared across many devices simultaneously | `shared-users` not set to `1` on the profile actually in use | §9 |

---

## Reference: this deployment (Moinfotech WiFi)

| Field | Value |
|---|---|
| Router model | MikroTik hAP ac lite, RB952Ui-5ac2nD |
| Hotspot interface | `wlan1` |
| `MikrotikRouter.host` (API) | WireGuard tunnel address `10.200.0.2` |
| `MikrotikRouter.local_login_host` | hotspot interface's own LAN IP (see §4/§10) |
| `MikrotikRouter.payment_mode` | `platform_collected` |
| Walled garden | `mobilling.co.tz`, `*.mobilling.co.tz`, `pay.pesapal.com`, `*.pesapal.com` |

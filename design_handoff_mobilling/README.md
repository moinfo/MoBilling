# Handoff: MoBilling marketing site + sign-in

## Overview
Two screens for **MoBilling** — a WHMCS-style billing, hosting-automation and `.tz` domain platform for East African businesses, operated by Moinfotech (Kibaha, Tanzania):

1. **Landing page** — full marketing page: hero with live-dashboard preview, stats, how-it-works, 9 features, hosting & domains (dark section), testimonials, white-label reseller block, pricing with a Hosted / Self-hosted switch, FAQ accordion, CTA, contact, footer.
2. **Login** — business sign-in, split layout (brand panel + form), with validation, password reveal, "keep me signed in", and a WhatsApp sign-in-link alternative.

Both support **light and dark themes** via one toggle, persisted in `localStorage`.

## About the design files
The files in this bundle are **design references authored in HTML** — prototypes that show intended look, motion and behavior. They are **not production code to copy**. The task is to **recreate these designs in the target codebase's existing environment** (React/Next, Vue, Laravel Blade, etc.) using its established component patterns, routing, forms and state libraries. If no front-end environment exists yet, pick the most appropriate framework for the product and implement there.

Note on file format: the `.dc.html` files are self-contained prototype documents (a template plus a small logic class, rendered by the bundled `support.js`). Read them for markup, values and behavior — do not port `support.js` or its conventions into the product.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, shadows, copy and motion are final and should be reproduced closely. The only intentionally rough parts are noted under *Assets* and *Out of scope*.

---

## Screens / views

### 1. Landing page — `MoBilling Landing v2.dc.html`

Page container: full-width sections; every inner content block is centered with `max-width: 1280px; padding: 0 32px`.

#### 1.1 Top utility strip
- Background `--ink` (#0c1220), text `#9aa6b6`, IBM Plex Mono 12px, `letter-spacing: 0.05em`, padding `10px 32px`.
- Above it: a 4px full-bleed rule, `linear-gradient(90deg, #f5c518 0%, #2fae60 38%, #1a68b0 68%, #f0632c 100%)`.
- Left: `info@moinfo.co.tz`, `+255 689 011 111` (flex, `gap: 8px 24px`, wraps). Right: `CHAT ON WHATSAPP →` in `#4fd189`.

#### 1.2 Nav (sticky, `top: 0`, `z-index: 30`)
- Background `--panel` with `backdrop-filter: blur(8px)`, bottom border `1px solid --border`, padding `14px 32px`, flex, `gap: 28px`.
- Brand: logo image 34px tall + wordmark "MoBilling", Archivo 800, 20px, `letter-spacing: -0.03em`. `flex-shrink: 0`.
- Links (Features, Hosting & Domains, Reseller, Pricing, FAQ, Contact): 15px/500, `--text-2`; container `flex-wrap: wrap; gap: 8px 22px; flex: 1 1 auto; min-width: 0`; each link `white-space: nowrap`. Hover → `#1a68b0`.
- Right cluster (`flex-shrink: 0`): theme toggle (38×38, radius 11, 1px `--border`, bg `--bg-alt`, icon 20px), "Sign in" text link (15px/600), and primary button — bg `#1a68b0`, white, 15px/700, padding `11px 20px`, radius 10, shadow `0 10px 20px -12px rgba(26,104,176,0.9)`; hover `#12507f`.
- **Wrapping is deliberate**: nav links wrap onto a second row at narrow widths; brand and right cluster never shrink.

#### 1.3 Hero (dark)
- Section bg `--ink`, white text, `position: relative; overflow: hidden`, padding `84px 32px 96px`.
- Two decorative radial circles (absolute, non-interactive): 620px at `top:-180px; right:-120px` — `radial-gradient(circle at 30% 30%, rgba(26,104,176,0.55), transparent 68%)`; 560px at `bottom:-240px; left:-140px` — `rgba(47,174,96,0.32)`.
- Grid `minmax(0,1.02fr) minmax(0,1fr)`, `gap: 56px`, `align-items: center`.
- **Left column** (class `om-hero`, children animate in — see *Motion*):
  - Pill badge: bg `rgba(255,255,255,0.08)`, 1px `rgba(255,255,255,0.16)`, radius 999, padding `8px 14px`, IBM Plex Mono 11.5px `letter-spacing: 0.12em`, color `#ffd24a`, with a 7px `#2fae60` dot. Text `WHMCS-STYLE PLATFORM · BUILT FOR EAST AFRICA`.
  - H1 78px / `line-height: 0.93` / `letter-spacing: -0.04em` / weight 900: "Billing, hosting / & .tz domains / **on autopilot.**" — last line is gradient text `linear-gradient(90deg, #ffd24a, #4fd189 46%, #56a9e8)` with `background-clip: text; color: transparent`.
  - Body 19.5px/1.6, `#b3bdcb`, `max-width: 44ch`.
  - Buttons: primary `linear-gradient(90deg, #f5a11d, #f0632c)`, white, 16.5px/700, padding `16px 28px`, radius 12, shadow `0 18px 34px -18px rgba(240,99,44,0.85)`; secondary `rgba(255,255,255,0.08)` + 1px `rgba(255,255,255,0.22)`.
  - Four trust rows in a 2×2 grid (`gap: 14px 28px`), 14.5px `#c3ccd8`, each with a 6px dot: yellow `#ffd24a`, green `#4fd189`, blue `#56a9e8`, orange `#f5a11d`.
- **Right column — dashboard preview card** (`om-panel om-panel-inner`): bg `--panel`, radius 18, `overflow: hidden`, shadow `0 40px 80px -32px rgba(0,0,0,0.6)`, text `--text`.
  - Header row: `MOBILLING / DASHBOARD` (Plex Mono 11.5px, `0.1em`, `--text-3`) and `● LIVE` in `#2fae60`; the bullet pulses.
  - 3 metric tiles (`grid; gap: 12px; padding: 20px`), radius 12: Revenue MTD `TZS 4.2M` on `--tint-b` w/ label `#1a68b0`; Hosting `109` on `--tint-g` w/ `#23874a`; Domains `317` on `--tint-y` w/ `#99700a`. Values 23px/800, `letter-spacing: -0.03em`.
  - `RECENT INVOICES` label, then 4 rows (`padding: 13px 0`, divider `1px solid --row`): 30px rounded-9 avatar tile (tinted bg, initial), name 15px/600, amount Plex Mono 13px, status chip Plex Mono 10px radius 6 — PAID (`--tint-g`/`#1f7a45`), PENDING (`--tint-y`/`#99700a`), OVERDUE (`--tint-o`/`#c2461f`). Rows: Amina Traders 450,000 PAID · Kibaha Hardware 182,500 PENDING · TopNet Ltd 320,000 PAID · Salama Shops 95,000 OVERDUE.
  - Footer: two bordered mini-cards — "DOMAIN REGISTERED / amina-traders.co.tz · auto" and "PAYMENT RECEIVED / TZS 450,000 via M-Pesa".

#### 1.4 Stats strip
- 4 cards in a grid (`gap: 18px`) pulled up over the hero: `margin-top: -44px; z-index: 5`. Each: bg `--panel`, 1px `--border`, radius 16, padding `26px 24px`, shadow `0 24px 44px -30px rgba(16,23,37,0.35)`.
- Numbers 42px/800 `letter-spacing: -0.04em`: **500+** `#1a68b0` Businesses onboarded · **50K+** `#2fae60` Invoices generated · **300+** `#e0a512` Domains & hosting automated · **99.9%** `#f0632c` Uptime. Labels 14px `--text-3`.

#### 1.5 How it works
- Centered heading block: eyebrow `HOW IT WORKS` (Plex Mono 11.5px `0.14em`, `#2fae60`), H2 52px/1.02/`-0.04em`/800, sub 18.5px `--text-2` `max-width: 54ch`.
- 3 cards (`gap: 20px`), bg `--panel`, 1px `--border`, radius 16, `border-top: 4px solid` — blue `#1a68b0`, green `#2fae60`, amber `#f5a11d`. Each has a 44×44 radius-12 tinted icon tile with Plex Mono number (01/02/03), H3 22px/700, body 16px/1.6 `--text-2`.
- Copy: **Create your account** — "Sign up in seconds. Set your business profile and logo, then invite your team." · **Add services & pricing** — "Import clients, define hosting plans and domain pricing — connect your WHM server if you host." · **Sell on autopilot** — "Clients order and pay in your portal; provisioning, renewals, reminders and dunning run themselves."

#### 1.6 Features (9)
- Band bg `--bg-alt` with 1px `--border` top/bottom, padding `88px 32px 96px`. Centered heading: eyebrow `FEATURES` `#1a68b0`, H2 52px, sub 18.5px.
- 3-column grid, `gap: 20px`. Card: bg `--panel`, 1px `--border`, radius 16, padding `28px 26px 30px`; hover raises the card and switches border to the card's accent + a matching soft shadow.
- Each card: 44×44 radius-12 solid accent tile with a white 24px icon (yellow tile uses `#3a2c00` icon), H3 20px/700, body 15.5px/1.6.
- Accent + Material Symbols icon per card, in order: Invoicing & recurring billing (`#1a68b0`, `receipt_long`) · Quotations & proformas (`#2fae60`, `request_quote`) · Statutory bills (`#f5c518`, `account_balance`) · Payments & wallet (`#f0632c`, `payments`) · Client portal (`#1a68b0`, `space_dashboard`) · Support helpdesk (`#2fae60`, `support_agent`) · WhatsApp marketing (`#f5c518`, `campaign`) · Field marketing (`#f0632c`, `directions_walk`) · SMS & email notifications (gradient `135deg, #1a68b0, #2fae60`, `mark_email_unread`). Body copy verbatim in the HTML.

#### 1.7 Hosting & domains (dark)
- Section bg `--ink`, padding `92px 32px 96px`, one decorative green radial at `top:-160px; left:40%`.
- Centered heading: eyebrow `HOSTING & DOMAINS` `#4fd189`, H2 52px, sub `#aab5c4` `max-width: 60ch`.
- 6 cards, 3 columns, `gap: 18px`: bg `rgba(255,255,255,0.05)`, 1px `rgba(255,255,255,0.12)`, radius 16, padding `28px 26px 30px`. Each opens with a 42px radius-12 translucent tile (icon coloured `#4fd189` / `#ffd24a` / `#56a9e8`, cycling) beside a Plex Mono index 01–06.
- Cards: cPanel hosting automation (`dns`) · .tz domain registrar (`language`) · Auto-renewals from wallet (`autorenew`) · SSL & DNS management (`lock`) · One-click cPanel login (`login`) · Order → pay → provision (`shopping_cart`).
- Migration banner: `linear-gradient(100deg, rgba(240,99,44,0.16), rgba(245,161,29,0.08))`, 1px `rgba(245,161,29,0.35)`, radius 16, padding `30px 32px`, flex + wrap. H3 22px "Migrating from WHMCS?" + body `#c3ccd8`, and an orange-gradient CTA "Ask about migration →" (`white-space: nowrap`).

#### 1.8 Testimonials (toggleable)
- Rendered only when the `showTestimonials` flag is on.
- Centered heading: eyebrow `TESTIMONIALS` `#e0a512`, H2 52px "Loved by businesses across East Africa".
- 3 cards: bg `--panel`, 1px `--border`, radius 16, padding `30px 28px`, shadow `0 24px 44px -34px rgba(16,23,37,0.4)`. Top accent bar 34×4 radius 4 (blue / green / `#f5a11d`). Quote 17.5px/1.6, `text-wrap: pretty`. Attribution: 38px circular tinted initials + name 15px/700 + role 13.5px `--text-3`.
- Amina Hassan (Amina Traders, Dar es Salaam) · David Ochieng (Ochieng IT Solutions, Nairobi) · Fatuma Kombo (Kombo Supplies, Mombasa) — quotes verbatim in the HTML.

#### 1.9 Reseller block
- Full card: `linear-gradient(120deg, #0f4d8c 0%, #1a68b0 44%, #23874a 100%)`, white, radius 22, padding `60px 48px 56px`, `overflow: hidden`, plus a yellow radial at `top:-120px; right:-80px`.
- Centered: translucent pill `WHITE-LABEL RESELLER`, H2 52px "Your brand. Our engine.", sub `#dbe8f5` `max-width: 58ch`.
- 3 translucent cards (`rgba(255,255,255,0.12)`, 1px `rgba(255,255,255,0.22)`, radius 16): Your brand, your prices · We run the machinery · Isolated tenant workspace.
- Buttons centered: white/`#1a68b0` "Become a reseller →" and outlined "Talk to sales".

#### 1.10 Pricing
- Centered heading: eyebrow `PRICING`, H2 52px, sub 18.5px.
- **Switch**: pill container bg `--bg-alt`, 1px `--border-2`, radius 999, `padding: 5px`; buttons radius 999, `padding: 11px 22px`, 14.5px/700, `white-space: nowrap`, `flex-shrink: 0`. Active: bg `#1a68b0`, white, shadow `0 10px 20px -14px rgba(26,104,176,0.9)`; inactive transparent `--text-2`. Options: **Hosted plans** (default) / **Self-hosted licence**.
- **Hosted** — 4 columns, `gap: 18px`, `align-items: start`. Cards radius 18, padding `30px 26px`, flex column; the description line has `min-height: 40px` so prices align. Price 32px/800 `-0.04em`; cadence `PER 30 DAYS` Plex Mono 11px. Feature rows 15px with a coloured `✓`. CTA at `margin-top: auto`, radius 11, 15px/700, tinted (`--tint-*` bg + `--on-*` text).
  - Starter — TZS 10,000 — blue ticks — 50 invoices/mo, 20 clients, email support, basic reports.
  - Professional — TZS 25,000 — green ticks — unlimited invoices & clients, SMS notifications, advanced reports, priority support.
  - **Business (POPULAR)** — TZS 50,000 — dark card: bg `--ink`, white, radius 18, shadow `0 34px 60px -30px rgba(12,18,32,0.65)`; `POPULAR` chip Plex Mono 10px on `#f5c518` with `#0c1220` text; ticks `#4fd189`; CTA orange gradient "Get started →".
  - Enterprise — TZS 100,000 — orange ticks — unlimited users, white-label PDFs, custom integrations, SLA, 24/7 support.
- **Self-hosted** — 3 columns: MoBilling Lite TZS 10,000/mo or 80,000/yr (yellow) · MoBilling Reseller TZS 15,000/mo or 95,000/yr (solid `#1a68b0` CTA) · MoBilling Complete TZS 25,000/mo or 175,000/yr (green). `border-top: 4px solid` accent per card. Footnote centered 14px: "Self-hosted licences are governed by the **MoBilling Licence Agreement**."

#### 1.11 FAQ
- Grid `minmax(0,0.74fr) minmax(0,1.26fr)`, `gap: 56px`, left column `position: sticky; top: 100px`.
- Left: eyebrow `FAQ` `#2fae60`, H2 42px/1.05/`-0.04em`, and "Still have questions? Reach us on WhatsApp any time — +255 689 011 111."
- Right: accordion items in a `flex column; gap: 10px`. Item: bg `--bg-alt`, 1px `--border`, radius 14. Trigger is a full-width borderless button, `padding: 19px 22px`, question 17px/600 left-aligned, and a `+` / `−` glyph in `#1a68b0` (`flex-shrink: 0`). Open answer: 16px/1.65 `--text-2`, `padding: 0 22px 22px`, `max-width: 74ch`.
- **Single-open accordion**; item 0 open by default; clicking the open item closes it. 10 Q&As (verbatim in the HTML): WHMCS alternative · sell hosting & domains · reseller program · free trial · payment methods · TRA/KRA compliance · mobile use · data import · Swahili support · what happens if you stop paying.

#### 1.12 Closing CTA
- Gradient frame: outer div `linear-gradient(115deg, #f5c518 0%, #2fae60 42%, #1a68b0 100%)`, radius 22, `padding: 4px`; inner bg `--ink`, radius 19, padding `68px 40px 72px`, centered.
- Eyebrow `FREE TO START` `#ffd24a`; H2 56px/1.02/`-0.04em`/900; sub `#b3bdcb` `max-width: 52ch`; buttons: orange-gradient "Create free account →" and translucent "Chat with us".

#### 1.13 Contact
- Grid `minmax(0,0.8fr) minmax(0,1.2fr)`, `gap: 56px`. Left: eyebrow `CONTACT`, H2 42px "Get in touch", body 16.5px.
- Right: 2×2 cards (`gap: 16px`), bg `--panel`, 1px `--border`, radius 16, padding 24. Each: 38×38 radius-11 solid tile with white 21px icon (yellow uses `#3a2c00`), Plex Mono 10.5px label, then value.
- EMAIL `mail` `#1a68b0` → info@moinfo.co.tz · PHONE `call` `#f5c518` → +255 689 011 111 · WHATSAPP `chat` `#2fae60` → +255 689 011 111 · OFFICE `location_on` `#f0632c` → "Njuweni Hotel, 1st Floor, Room 134 / Kibaha, Tanzania".

#### 1.14 Footer
- bg `--ink`, `#9aa6b6`, padding `64px 32px 30px`. Grid `minmax(0,1.4fr) repeat(2, minmax(0,1fr))`, `gap: 48px`.
- Brand column: logo + wordmark, then 15.5px/1.6 blurb `max-width: 40ch`. Two link columns under Plex Mono labels `NAVIGATION` and `CONTACT US`, links 15.5px `#d3d9e1`, `flex column; gap: 10px`.
- Bottom bar: `margin-top: 52px`, `border-top: 1px solid #1e2634`, Plex Mono 11.5px `#6b7789`, space-between: "© 2026 MOBILLING. ALL RIGHTS RESERVED." / "POWERED BY MOINFOTECH" (link `#56a9e8`).

---

### 2. Login — `MoBilling Login.dc.html`

Root: `min-height: 100vh`, grid `minmax(0,1.02fr) minmax(0,1fr)`. **Business sign-in only** — there is no client-portal tab.

#### 2.1 Left brand panel
- bg `--ink`, white, padding `44px 56px 40px`, `flex column`, `overflow: hidden`; 4px brand gradient rule pinned to the top edge; blue radial `top:-180px; right:-140px` (560px) and green radial `bottom:-220px; left:-160px` (520px).
- Top: logo 36px + wordmark, linking back to the landing page.
- Middle (`margin: auto 0`, `max-width: 460px`, staggered entrance): pill `BUILT FOR EAST AFRICA` (`#ffd24a` text, green dot); H1 44px/1.02/`-0.04em`/800 "Billing & statutory management made simple"; body 17px `#b3bdcb` `max-width: 42ch`; three benefit rows — 40px radius-12 translucent tile + 15.5px `#dbe2ea` label:
  - `receipt_long` `#56a9e8` — Create invoices, quotations & proformas in seconds
  - `insert_chart` `#4fd189` — Track payments, bills & statutory obligations
  - `shield` `#ffd24a` — Secure multi-tenant platform with role-based access
- Stat strip card (gently floating): bg `rgba(255,255,255,0.06)`, 1px `rgba(255,255,255,0.14)`, radius 16, padding `22px 24px`; three figures 26px/800 with Plex Mono labels, separated by 1px×34px dividers — **500+** BUSINESSES · **50K+** INVOICES · **99.9%** UPTIME.
- Bottom: Plex Mono 10.5px `#6b7789`, space-between: "© 2026 MOINFOTECH. ALL RIGHTS RESERVED." / "INFO@MOINFO.CO.TZ".

#### 2.2 Right form panel
- bg `--bg`, `flex column`, padding `26px 32px 40px`.
- Header row (right-aligned): "← Back home" link (14.5px/600 `--text-2`) + theme toggle (38×38, radius 11).
- Form stage: `margin: auto`, `width: 100%`, `max-width: 424px` — this is what fixes the original screenshot's oversized empty right side.
- Title H2 34px/1.1/`-0.035em`/800 "Welcome back"; sub 16px `--text-2` "Sign in to continue to your dashboard."
- **Error banner** (only when there is an error): bg `rgba(240,99,44,0.1)`, 1px `rgba(240,99,44,0.35)`, text `#c2461f`, radius 12, padding `13px 15px`, `error` icon + message, 14.5px.
- **Fields** — label 14px/600 with an `#f0632c` asterisk; control row: bg `--field`, 1px `--border-2`, radius 12, `height: 52px`, `padding: 0 15px`, flex with `gap: 11px`, leading 20px icon in `--text-3`. Focus (on the wrapper): border `#1a68b0` + `box-shadow: 0 0 0 4px rgba(26,104,176,0.14)`. Inputs are borderless/transparent, 15.5px, inheriting `--text`.
  - Email or phone — icon `alternate_email`, placeholder "you@company.com or 0712 345 678", `autocomplete="username"`.
  - Password — icon `lock`, placeholder "Your password", `autocomplete="current-password"`, trailing 36×36 borderless reveal button toggling `visibility` / `visibility_off` and the input type. "Forgot password?" (13.5px/600) sits on the label row, right-aligned.
- Checkbox row 14.5px `--text-2`: 17px box, `accent-color: #1a68b0` — "Keep me signed in for 30 days", checked by default.
- **Submit**: full width, `height: 52px`, radius 12, 16px/700 white on `linear-gradient(90deg, #1a68b0, #12507f)`, shadow `0 16px 30px -18px rgba(26,104,176,0.9)`. Loading state: label "Signing in…", `opacity: 0.75`, `cursor: wait`, spinning `progress_activity` icon.
- Divider: 1px rules either side of Plex Mono `OR`.
- Secondary action: full-width outlined button, `height: 50px`, radius 12, 15px/600, `chat` icon in `#2fae60` — "Get a WhatsApp sign-in link".
- Footer line 15px centered: "Don't have an account? **Create one free**" → landing `#pricing`.
- Panel bottom, centered 13px `--text-3` with `verified_user` icon: "Protected by 2FA and role-based access control".

---

## Interactions & behavior

**Landing**
- Anchor nav to `#features`, `#hosting`, `#reseller`, `#pricing`, `#faq`, `#contact`.
- Pricing switch swaps the Hosted (4 cards) and Self-hosted (3 cards) groups. Initial tab is configurable (`Hosted` default).
- FAQ: single-open accordion, first item open initially, re-clicking closes.
- Theme toggle flips `data-theme` on `<html>` and writes `mobilling-theme` to `localStorage`; the stored value wins over the configured default on load.
- Testimonials section can be switched off entirely by flag.

**Login**
- Client-side validation on submit, in order: identifier required → must look like an email (contains `@` past position 0) or a phone (`/^[+0-9 ()-]{9,}$/`) → password ≥ 6 characters. First failure sets the error banner; typing in either field clears it.
- On a valid submit the prototype shows the loading state for ~1.4s then a "couldn't find an account" error — this is a **stub**. Replace with the real auth call: on success, redirect to the dashboard; on failure surface the server message in the same banner.
- "Keep me signed in for 30 days" should map to the long-lived session/refresh-token option.
- The WhatsApp button is a placeholder for a magic-link flow (send a sign-in link to the user's WhatsApp number) — wire or remove.

**Motion** (respect `prefers-reduced-motion` — all of it is disabled there)
- `om-in`: `opacity 0 → 1` with `translateY(22px) → 0`, `0.8–0.9s cubic-bezier(0.22,0.72,0.2,1)`.
- Hero left column staggers children by ~80ms (delays 0.05 → 0.41s); the dashboard panel enters at 0.3s, then floats forever: `om-float`, `translateY(0 → -10px → 0)`, 7s ease-in-out, 1.4s delay.
- `LIVE` dot pulses (`om-pulse`, 1.8s: opacity 1 → 0.45, scale 1 → 0.82).
- Scroll reveal: cards and section headings fade/rise as they enter the viewport, staggered ~70ms by position within their row, each element animating once. **Implement fail-open** — content must be visible if the observer never fires (in a framework, this is `IntersectionObserver` in an effect with the hidden state applied only after the observer attaches; ideally use a small reusable hook/directive).
- Card hover: `translateY(-6px)`, 0.35s, plus accent border/shadow. Button hover: `translateY(-2px)`, 0.2s; active returns to 0.
- Login: staged entrance on both columns, floating stat card, spinner on submit.

## State
**Landing** — `theme: 'light' | 'dark'` (persisted); `pricingTab: 'hosted' | 'self'`; `openFaq: number` (`-1` = all closed); reveal bookkeeping. No data fetching; all numbers, invoices and quotes are static content.

**Login** — `theme` (persisted); `identifier: string`; `password: string`; `showPassword: boolean`; `remember: boolean` (default `true`); `loading: boolean`; `error: string`. Real implementation adds the auth request, redirect target, and server-side rate-limit/lockout messaging.

## Design tokens

Light (`:root`) → Dark (`html[data-theme="dark"]`):

| Token | Light | Dark |
|---|---|---|
| `--bg` | `#ffffff` | `#0f1626` |
| `--bg-alt` | `#f6f9fc` | `#141d2e` |
| `--panel` | `#ffffff` | `#172032` |
| `--border` | `#e9eef4` | `#26324a` |
| `--border-2` | `#e3eaf2` (login `#d9e2ec`) | `#33405c` |
| `--row` | `#f3f6fa` | `#1d2739` |
| `--text` | `#101725` | `#eff3f8` |
| `--text-2` | `#5b6779` | `#a7b3c4` |
| `--text-3` | `#7b8798` | `#8d9aad` |
| `--ink` | `#0c1220` | `#080e19` |
| `--field` (login) | `#ffffff` | `#121a2a` |
| `--tint-b` | `#eef5fc` | `rgba(86,169,232,0.16)` |
| `--tint-g` | `#ecf7f0` | `rgba(79,209,137,0.16)` |
| `--tint-y` | `#fdf4e0` | `rgba(245,197,24,0.16)` |
| `--tint-o` | `#fdeee9` | `rgba(240,99,44,0.16)` |
| `--on-b` | `#1a68b0` | `#7ab6ec` |
| `--on-g` | `#23874a` | `#5ed294` |
| `--on-y` | `#99700a` | `#f0c645` |
| `--on-o` | `#c2461f` | `#f58a5f` |

Brand hues (theme-independent): blue `#1a68b0` (dark `#12507f`, light-on-dark `#56a9e8` / `#7ab6ec`), green `#2fae60` (`#23874a`, `#4fd189`), yellow `#f5c518` (`#e0a512`, `#ffd24a`), orange `#f0632c` (`#f5a11d`). CTA gradient `linear-gradient(90deg, #f5a11d, #f0632c)`; brand rule `linear-gradient(90deg, #f5c518, #2fae60 38%, #1a68b0 68%, #f0632c)`.

Type: **Archivo** 400–900 for UI/display; **IBM Plex Mono** 400–600 for eyebrows, labels, numerics and chips. Scale used: 78 / 56 / 52 / 44 / 42 / 34 / 32 / 22 / 20 / 19 / 17.5 / 16.5 / 16 / 15.5 / 15 / 14.5 / 14 / 13.5 / 13 / 11.5 / 11 / 10.5 px. Display headings pair a tight `letter-spacing` (−0.03 to −0.05em) with `line-height` 0.93–1.05; body copy runs 1.6–1.66 with `text-wrap: pretty` on long paragraphs.

Spacing: 4-based; section padding 84–96px vertical, 32–34px horizontal gutters; card padding 24–32px; grid gaps 16 / 18 / 20 / 22px; 1px hairline grids use a `--border` background behind `gap: 1px`.

Radii: 999 (pills/buttons), 22 (feature frames), 18–19 (panels/price cards), 16 (cards), 14 (accordion), 12–13 (fields, icon tiles, buttons), 11 (small buttons), 6–9 (chips).

Shadows: `0 24px 44px -30px rgba(16,23,37,0.35)` (raised card) · `0 34px 60px -30px rgba(12,18,32,0.65)` (dark price card) · `0 40px 80px -32px rgba(0,0,0,0.6)` (hero panel) · `0 16px 30px -18px rgba(26,104,176,0.9)` (blue CTA) · `0 18px 34px -18px rgba(240,99,44,0.85)` (orange CTA) · focus ring `0 0 0 4px rgba(26,104,176,0.14)`.

Icons: **Material Symbols Rounded** (weight 400, unfilled, 24 opsz), rendered at 17–26px. Names used are listed per section above.

## Assets
- `assets/mobilling-logo.png` — the MoBilling mark supplied by the client (326×414, transparent). Swap for an SVG in production; keep the wordmark as live text.
- Fonts load from Google Fonts (Archivo, IBM Plex Mono, Material Symbols Rounded) — self-host or use the codebase's existing font pipeline.
- No photography is used. If the marketing team wants imagery, the hero right column and the reseller block are the natural slots.

## Out of scope / open items
- No responsive breakpoints below ~1100px were designed. All multi-column grids need mobile/tablet rules (hero and login collapse to one column; feature/pricing grids to 1–2 columns; nav needs a mobile menu). Type scale should step down accordingly.
- Auth, payments, and every number on the page are static/stubbed.
- Legal pages (licence agreement, privacy, terms), signup, forgot-password and the dashboard itself are not designed.
- Copy is final English only; the product supports Swahili, so plan for i18n keys rather than hardcoded strings.

## Files
- `MoBilling Landing v2.dc.html` — the landing page to implement.
- `MoBilling Login.dc.html` — the login screen to implement.
- `reference-only/MoBilling Landing v3.dc.html` — an alternative editorial/art direction for the same content (cream paper, grain texture, serif italic accents). Not the chosen design; kept for context only.
- `support.js` — prototype runtime, needed only to open the HTML files in a browser. Do not port.
- `assets/mobilling-logo.png` — brand mark.

To view a prototype: open the `.dc.html` file directly in a browser (keep `support.js` and `assets/` alongside it).

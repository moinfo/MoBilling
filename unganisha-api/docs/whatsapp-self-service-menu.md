# WhatsApp self-service menu (staff reference)

The bot answers clients on the tenant's WhatsApp (MoSMS shared number). Every message exists in Kiswahili (sw) and English (en); the client
picks the language once and can switch it later (More services > 6). Numbers below are what the client types. **MENU** (or NYUMBANI / CANCEL /
ANZA UPYA) returns to the main menu from anywhere; **0** goes back one level (at the main menu, 0 logs out).

## Getting in

1. First contact: language choice (1 English / 2 Kiswahili) -> "Do you have an account?" 1) Yes 2) No.
2. Known phone: the client proves identity with the registered **surname**, then the registered **email** as a second chance (5 wrong answers
   lock the number for a while and alert staff).
3. **Several accounts share the phone**: "This number has more than one account. Choose: 1) A\*\*\* M\*\*\* 2) J\*\*\* K\*\*\*" (masked names, at
   most 5); the choice is remembered and surname verification runs for that account only.
4. Unknown phone: offer to register (name, then optional email - reply RUKA / SKIP). A Tanzanian number is stored as `0` + 9 digits; a number from
   another country is stored in full international digits (e.g. `254712345678`) and answered on that number.
5. A client whose status is not `active` (inactive / merged / suspended) gets "Akaunti yako imesimamishwa. Tafadhali wasiliana nasi." / "Your
   account has been suspended. Please contact us." and no menu; staff get a heads-up notification (once a day per client).
6. Verified login lasts 30 days; each step of a flow times out after 10 minutes (60 for payments) without losing the login.

## Main menu

| # | Kiswahili | English |
|---|---|---|
| 1 | Domain Registration | Domain Registration |
| 2 | Domain Renewal | Domain Renewal |
| 6 | WHOIS ya Domain | Domain WHOIS |
| 7 | Angalia kama Domain Inapatikana | Check Domain Availability |
| 8 | Badilisha Nameservers (DNS) | Change Nameservers (DNS) |
| 11 | Domain Zangu | My Domains |
| 3 | Website Hosting | Website Hosting |
| 4 | Business Email Hosting | Business Email Hosting |
| 12 | Hosting Yangu | My Hosting |
| 5 | Angalia na Lipa Invoice | View and Pay Invoices |
| 9 | Taarifa za Akaunti | Account Information |
| 10 | Huduma Zaidi | More services |
| 0 | Toka (Logout) | Logout |

Other keywords: **MOSMS** (bulk SMS/WhatsApp account help), **STAFF** / **WAFANYAKAZI** (staff PIN login, assist a client),
**STOP / UNSUBSCRIBE / ACHA / SITAKI** and **START / ANZA / WASHA** (see Reminders).

Confirmations always use `1) Ndiyo / Yes` and `2) Hapana / No` (words such as ndiyo, ndio, yes, y, ok, hapana, no, n also work). A number that is not
valid at a step is answered with "Sorry, reply 1, 2 or 0." naming the valid choices. While the renewal list (option 2) is open, a number outside
the list (e.g. 5 of 2, or 10-12) is rejected that way; MENU leaves it.

## Submenus

**3) Website Hosting**: 1) Order new hosting, 2) My hosting.

**11) My Domains**: list (max 9, type a name to search) -> card with expiry, status, auto-renew, renewal price -> `1) Renew`.
Domains that are paid but not yet registered are listed under the list as "Inaandaliwa (malipo yamepokelewa)" / "Being set up (payment
received)".

**12) My Hosting**: list -> card (plan, domain, expiry, status) -> Renew / Manage hosting (Open cPanel, Upgrade package, My email accounts,
Connect domain, unpaid invoices, Contact support, Reset cPanel password with an emailed 6-digit code). Paid hosting still being provisioned is
shown as "Being set up".

**10) More services**

| # | Kiswahili | English | What it does |
|---|---|---|---|
| 1 | Server Zangu (Cloud Server) | My Servers (Cloud Server) | List/search own servers, details, `1) Reboot` (confirmed, rate-limited, audited) |
| 2 | Zinazokaribia kuisha | Expiring soon | Domains/hosting expiring, pick one to renew and pay |
| 3 | Msaada | Support | One-message support ticket (3 per day per client) |
| 4 | Oda zangu (zisizolipwa) | My orders (unpaid) | Pending unpaid orders (name, type, amount, invoice, age; max 9). Card: `1) Lipa sasa / Pay now`, `2) Futa oda hii / Delete this order` (confirmed; releases the coupon and cancels the invoice and the pending domain/subscription; only unpaid orders, never paid or part-paid ones). Orders already paid but being set up are listed as "Being set up". |
| 5 | Malipo na risiti | Payments & receipts | 1) last 5 payments (date, invoice, amount, method) -> `1) Nitumie risiti` (text receipt + button to the client's portal payments page); 2) last 5 paid invoices -> `1) Nitumie invoice` (button to the invoice page); 3) Statement: total invoiced, total paid, balance due, last 30 days, button to the full portal statement |
| 6 | Lugha | Language | Confirm, switch sw <-> en; the login is kept and the main menu is shown in the new language |

The channel cannot send document attachments, so receipts and invoices are sent as a text summary plus a link button (the portal asks the client to
sign in; the invoice page uses the invoice's own link).

**5) View and Pay Invoices**: unpaid invoices (max 9, type a number to search) -> `1) Pay online` (card / mobile money link, reused for 30
minutes if the amount is the same) or `2) Payment details` (bank / mobile money, approved by staff).

## Reminders and STOP

Domain-expiry and other reminder/notification messages sent to a client on WhatsApp stop when the client sends **STOP**, **UNSUBSCRIBE**,
**ACHA** or **SITAKI** (whole message, any case); reply: "Sawa, hutapokea vikumbusho vya WhatsApp tena. Andika ANZA kuwasha tena." /
"Okay, you will no longer receive WhatsApp reminders. Type START to turn them back on." **START / ANZA / WASHA** turns them back on (only for
a client who is opted out; otherwise "ANZA" is treated as a normal message). The flag is `clients.whatsapp_opt_out_at`. Email/SMS are
unaffected, security notices (cPanel password changed, EPP code shown) are still sent, and the bot still answers messages the client starts.

## Safety behaviour worth knowing

- Messages from one phone are processed one at a time, and an identical message repeated within 3 seconds is ignored, so a retried "YES" cannot
  create a second order, invoice or reboot (the second one gets nothing, or "Your previous request is still being processed").
- More than 30 messages in 10 minutes from one phone: one polite notice, then silence.
- Logs never contain what the client typed at EPP/PIN/OTP/password steps; error text is masked (SQL values, codes, long numbers).
- Staff-assist sessions last 2 hours, show an "Assisting ..." banner, cannot change nameservers, and stamp every action with the staff user.
- Clients never see the domain/cloud supplier names or USD prices; amounts are in TZS.

## Staff menu: receive a payment (option 3)

STAFF -> PIN -> staff menu: `1) Followups Zangu`, `2) Tafuta Mteja Kumsaidia`, `3) Pokea Malipo (Lipa Namba / Benki)`.
Option 3 records an OFFLINE payment (mobile money / lipa namba / bank transfer) against an unpaid invoice. Same money path as the web
page "Receive payments" (`App\Services\OfflinePaymentService`).

1. Type a client name, phone or invoice number (or `LIST` for the 9 oldest unpaid invoices; a longer result shows a "9 of N" notice).
2. Pick the invoice number -> card (total / paid / balance) -> pick the payment method (the tenant's configured methods, never Pesapal).
3. Type the transaction ID / reference (4-40 letters/digits, no spaces) or paste the whole payment SMS: the bot shows what it understood
   (reference, amount, sender) and asks `1) Yes 2) No` before using it.
4. `1) Pay full balance  2) Other amount` (partial allowed; never more than the balance - over-payments and client credit are web-only).
5. Summary (Client, Invoice, Method, Ref, Amount, New balance) -> `1) Yes, record`. Only then is it recorded; the client gets the normal receipt.

Rules: needs the `payments_in.create` permission; a reference already used with the same method in the last 90 days is refused (no override
on WhatsApp - use the web page); the same amount on the same invoice within 10 minutes is refused; paid/cancelled invoices are refused.
`0` goes back one step (at the search step `0`/`LIST` lists invoices), `RUDI` returns to the staff menu, `MENU` leaves staff mode.
The payment note says "Recorded via WhatsApp staff menu" and `received_by` is the staff user. A client session can never reach this flow.

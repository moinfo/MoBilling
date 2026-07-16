# HIKVISION Attendance Device Integration

> Goal: pull staff check-in / check-out times straight from a HIKVISION
> access-control / face terminal into MoBilling's **Attendance** module, instead
> of a clerk typing every time by hand.
>
> **Current status: CAPTURE MODE.** The device pushes each swipe to a public
> webhook; we log the raw event so we can confirm the exact on-the-wire format
> and map each device employee number to a MoBilling staff member. Events are
> **not yet written into attendance records** — that's the next phase (§7).

---

## 1. Why event-push (and not polling)

The terminal sits on the **office LAN**; the MoBilling server is in the **cloud**.
The cloud cannot reach *into* the office network to poll the device's ISAPI API,
and opening an inbound port on the office router to the device is a security
liability (these devices have a long CVE history).

So we use the direction that *does* work: the device makes an **outbound** HTTPS
call to us on every event. HIKVISION exposes this as:

- **Notify Surveillance Center** / **HTTP Listening** / **Alarm Server**
  (naming varies by model / firmware).

The device is the client, MoBilling is the server. No inbound office ports, no
VPN, no ISAPI credentials stored in the cloud.

```
[ HIKVISION terminal ]  --- outbound HTTPS POST on each swipe --->  [ MoBilling webhook ]
   (office LAN)                                                        (mobilling.co.tz)
```

---

## 2. Moving parts

| Piece | Where |
|---|---|
| Public capture webhook | `POST/GET /api/attendance/device/{token}` → `DeviceAttendanceController@capture` |
| Config (URL) endpoint | `GET /api/attendance/device-config` → `@config` |
| Recent events endpoint | `GET /api/attendance/device-events` → `@events` |
| Regenerate token | `POST /api/attendance/device-regenerate` → `@regenerate` |
| Controller | `app/Http/Controllers/DeviceAttendanceController.php` |
| Device model | `app/Models/AttendanceDevice.php` (`attendance_devices`) |
| Event log model | `app/Models/AttendanceDeviceEvent.php` (`attendance_device_events`) |
| Migrations | `2026_07_06_140000_create_attendance_devices.php`, `2026_07_06_140001_create_attendance_device_events.php` |
| Frontend "Device" tab | `mobilling-ui/src/pages/Attendance.tsx` → `DeviceTab` |
| Frontend API | `mobilling-ui/src/api/attendance.ts` (`getDeviceConfig`, `getDeviceEvents`, `regenerateDeviceToken`) |

---

## 3. Security model

- The capture route lives in the **public** section of `routes/api.php`, **outside**
  the `auth:sanctum` + tenant middleware group — a physical device can't hold a
  bearer token or a tenant session.
- Authorization is instead a **per-tenant random 40-char token** embedded in the
  URL path (`/api/attendance/device/<token>`). `capture()` looks up an
  `AttendanceDevice` by `token` **and** `is_active = true`; unknown/inactive token
  → `404`. The token also tells us **which tenant** the event belongs to.
- The token can be rotated any time from the Device tab ("Regenerate URL").
  The old URL stops working immediately; the device must be re-pointed.
- The three management endpoints (`device-config`, `device-events`,
  `device-regenerate`) are inside the authed group and gated by the
  **`attendance.manage`** permission via the `AuthorizesPermissions` trait.
- The capture handler is **defensive**: the raw body is capped at 20 000 chars
  (HIKVISION multipart can carry a base64 face snapshot we don't want to store),
  string inputs are capped at 8 000 chars, and only the first 60 parsed fields
  are kept. It never throws on a malformed body — it just logs what it can and
  returns `200`, because devices retry aggressively on any non-200.

---

## 4. Data model

### `attendance_devices`
One row per tenant (auto-created on first Device-tab visit).

| Column | Notes |
|---|---|
| `id` uuid | |
| `tenant_id` | owner (from the auth'd manager who created it) |
| `name` | default `"HIKVISION device"` |
| `token` (64, unique) | secret in the webhook URL |
| `is_active` | inactive token → 404 |
| `last_event_at` | bumped on every capture |

### `attendance_device_events`
Append-only capture log. **This is a raw-inspection buffer, not attendance data.**

| Column | Notes |
|---|---|
| `id` uuid | |
| `tenant_id` | nullable (set from the device) |
| `attendance_device_id` | nullable |
| `content_type` | so we can tell JSON vs multipart vs form |
| `employee_no` | **best-effort** extract (see §6) |
| `event_time` | **best-effort** extract, parsed to a timestamp |
| `payload` | raw body, capped 20 000 chars |
| `parsed` (json) | flattened text fields for inspection |
| `processed` (bool) | reserved for §7 — becomes `true` once an event is imported into attendance |
| `created_at` | when we received it |

Indexed on `(tenant_id, created_at)`.

---

## 5. Device-side setup

On the terminal (web UI, or iVMS-4200 → *Remote Configuration*):

1. Open the **Device** tab in MoBilling → **Attendance** and copy the **Webhook URL**.
   It looks like `https://mobilling.co.tz/api/attendance/device/<40-char-token>`.
2. On the device: **Network → Advanced Settings → HTTP Listening**
   *(or **Event → Basic Event → Notify Surveillance Center / Alarm Server**
   — exact path depends on model/firmware)*. Set:
   - **Destination IP / Host / URL** → the host part (`mobilling.co.tz`)
   - **URL / path** → everything after the host (`/api/attendance/device/<token>`)
   - **Protocol** → HTTP(S), **Port** → 443
3. Enable **event upload** for **Access Control / Face / Card** events (so a swipe
   generates a push, not just alarms).
4. Save, then have one person swipe. The event should appear in the Device tab
   within a few seconds (the list auto-refreshes every 5s).

> If nothing arrives: the device usually can only reach the internet over port 80/443,
> confirm HTTPS/443 is selected, and confirm the office firewall allows outbound
> HTTPS from the device's IP.

---

## 6. How we parse an event (capture phase)

HIKVISION event formats vary by model and firmware — some POST **JSON**, some POST
**multipart/form-data** (event JSON in one part + a face JPEG in another). So we
**don't hard-code a schema yet**. `capture()`:

1. Stores the raw body verbatim (capped).
2. Flattens whatever it can read — multipart/form fields via `$request->except([])`,
   or, if the body is `application/json`, `json_decode` + a recursive `flatten()`
   (nested objects collapsed to leaf keys, last key wins).
3. Best-effort pulls the employee number from the first of:
   `employeeNoString`, `employeeNo`, `employee_no`, `cardNo`.
4. Best-effort pulls the time from the first of: `dateTime`, `time`, `event_time`,
   parsed with Carbon.

Everything lands in `parsed` (json) so we can eyeball the **real** field names for a
given device and firm up the mapping in §7.

**Verified in testing** with a simulated `AccessControllerEvent` JSON push:
`employee_no` extracted correctly, `dateTime` parsed to a timestamp, unknown token → `404`.

---

## 7. Next phase — importing events into attendance (NOT done yet)

Once we've confirmed the real format from a live swipe, the plan:

1. **Employee → staff map.** Add a `device_employee_no` to `users` (or a small
   mapping table) so a device number resolves to a MoBilling user. Surface it in
   the Device tab (one dropdown per unmatched `employee_no` seen in the log).
2. **Fold events into `Attendance`.** For each unprocessed event on a working day:
   - first swipe of the day → `check_in_at`
   - last swipe of the day → `check_out_at`
   (or use the device's own in/out `eventType` if it distinguishes them).
   Reuse the existing `Attendance` upsert (`user_id` + `date` unique) — the same
   rows the Record tab and `attendance:apply-penalties` already use, so deductions
   keep working unchanged.
3. Mark the event `processed = true`.
4. Decide processing trigger: inline on capture (simplest) vs. a small scheduled
   command draining unprocessed events (more robust to bad data).

Nothing above changes the deductions engine — it only replaces **manual entry** in
the Record tab with **auto-filled** times. Manual entry stays as the fallback /
override.

---

## 8. Open question to close before §7

**Exact device model + firmware version** — this determines whether events arrive as
JSON or multipart and what the employee-number / event-time field names actually are.
Capture one real swipe, read it off the Device tab, and the §7 parser can be finalised.

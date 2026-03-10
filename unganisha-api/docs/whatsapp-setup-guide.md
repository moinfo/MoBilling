# WhatsApp Business API Integration Guide

## Overview

MoBilling supports automated invoice reminders via WhatsApp Business API (Meta Cloud API). This guide walks you through the complete setup process.

## Prerequisites

- A Facebook account
- A Meta Business Manager account (business.facebook.com)
- A phone number for WhatsApp Business (can be different from your personal WhatsApp)
- A Meta for Developers account

---

## Step 1: Create a Meta for Developers Account

1. Go to **developers.facebook.com**
2. Click **Get Started** or **Create Account**
3. Complete the registration steps:
   - **Register** — Accept the terms
   - **Verify account** — Enter your mobile number linked to your Facebook profile and verify with SMS code
     > **Tip:** If the phone verification shows "You can only complete this action in Accounts Center", try a different number already linked to your Facebook account, or verify via credit card instead.
   - **Contact info** — Enter your email
   - **About you** — Select your role (e.g., Developer)

## Step 2: Create a Meta App

1. Go to **developers.facebook.com/apps**
2. Click **Create App**
3. Select **Other** as the use case, then click **Next**
4. Select **Business** as the app type
5. Fill in:
   - **App name**: e.g., "MoBilling WhatsApp"
   - **App contact email**: your email
   - **Business Account**: Select your MoinfoTech business account
6. Click **Create App**

## Step 3: Add WhatsApp Product

1. In your app dashboard, scroll to **Add Products to Your App**
2. Find **WhatsApp** and click **Set Up**
3. You'll be taken to the WhatsApp Getting Started page

## Step 4: Get API Credentials

From the **WhatsApp > API Setup** page:

### Phone Number ID
- Shown under the "From" phone number section
- Example: `123456789012345`

### WhatsApp Business Account ID
- Shown at the top of the API Setup page
- Example: `987654321098765`

### Temporary Access Token (for testing)
- Click **Generate** to get a temporary token
- This token expires in **24 hours** — use it for testing only

### Permanent Access Token (for production)
1. Go to **business.facebook.com** → Settings → Users → **System Users**
2. Click **Add** to create a new system user
   - Name: e.g., "MoBilling API"
   - Role: **Admin**
3. Click on the system user → **Add Assets**
   - Select **Apps** → Choose your WhatsApp app → Enable **Full Control**
4. Click **Generate New Token**
   - Select your app
   - Check these permissions:
     - `whatsapp_business_messaging`
     - `whatsapp_business_management`
   - Click **Generate Token**
5. **Copy and save** the token securely — it won't be shown again

## Step 5: Register a Business Phone Number

1. In the WhatsApp API Setup page, you can use the **test number** provided by Meta for testing
2. For production, click **Add Phone Number** to register your business number
3. Verify the number via SMS or voice call
4. This is the number messages will be sent FROM to your clients

## Step 6: Add Test Recipients (Sandbox Mode)

While in development mode:
1. Go to **WhatsApp > API Setup**
2. Under "To" field, click **Manage phone number list**
3. Add phone numbers you want to test with
4. Each recipient must confirm by replying to a verification message

> **Note:** In production mode (after app review), you can send to any number.

## Step 7: Configure MoBilling

### WhatsApp Settings Tab

1. Go to **MoBilling > Settings > WhatsApp**
2. Enter your credentials:
   - **Phone Number ID** — from Step 4
   - **Access Token** — temporary (testing) or permanent (production)
   - **Business Account ID** — from Step 4
3. Enable the integration toggle
4. Enable auto-reminders toggle if you want automated reminders

### Reminder Settings Tab

1. Go to **Settings > Reminders**
2. Enable **WhatsApp notifications enabled** (master switch)
3. Enable **WhatsApp reminders enabled** (auto-reminders)

### Manual Reminders

1. Go to **Invoices** list
2. Select unpaid invoices
3. Click **Send Reminder**
4. Choose **WhatsApp** as the channel
5. Click **Send Reminder**

---

## How It Works

### Automated Reminders
When the system's scheduled reminder job runs, it checks each tenant's settings:
- If `whatsapp_enabled` AND `reminder_whatsapp_enabled` are both true
- The system sends a formatted WhatsApp message to the client's phone number
- Includes invoice number, amount, due date, and pay link (if online payment is enabled)

### Message Format

**Upcoming Invoice Reminder:**
```
📋 *Invoice Reminder*

*INV-2026-0001*
Amount: *TZS 50,000.00*
Balance Due: *TZS 50,000.00*
Due Date: 24 Mar 2026
⏳ 14 day(s) remaining

💳 Pay online: https://mobilling.co.tz/pay/...

— MoinfoTech
```

**Overdue Invoice:**
```
🔴 *Payment Overdue*

*INV-2026-0001*
Amount: *TZS 50,000.00*
Balance Due: *TZS 50,000.00*
Overdue by: *7 day(s)*

⚠️ Please make payment immediately to avoid service disruption.

💳 Pay online: https://mobilling.co.tz/pay/...

— MoinfoTech
```

---

## Phone Number Formatting

The system automatically formats Tanzanian phone numbers:
- `0689011111` → `255689011111`
- `+255689011111` → `255689011111`
- `255689011111` → `255689011111` (no change)

---

## Troubleshooting

### "WhatsApp send failed" error
- Check that your access token hasn't expired (temporary tokens expire in 24h)
- Verify the Phone Number ID is correct
- Ensure the recipient's number is in the test recipients list (sandbox mode)

### Messages not being sent
- Check **Settings > Reminders** — both WhatsApp master switch and reminders toggle must be ON
- Verify the client has a valid phone number
- Check Laravel logs: `storage/logs/laravel.log`

### "Tenant has no WhatsApp credentials configured"
- Go to **Settings > WhatsApp** and enter all three credentials

### Rate Limits
- Meta imposes rate limits based on your phone number's quality rating
- New numbers start with a limit of ~250 unique recipients per 24 hours
- Limit increases automatically based on message quality and volume

---

## Production Checklist

- [ ] Create a permanent access token (System User token)
- [ ] Register and verify your business phone number
- [ ] Submit your app for Meta review (required for sending to non-test numbers)
- [ ] Set up a webhook for delivery receipts (optional)
- [ ] Monitor message quality in WhatsApp Manager

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  MoBilling                        │
│                                                   │
│  Notification ──→ WhatsAppChannel ──→ WhatsAppService
│  (toWhatsApp)     (send method)       (HTTP to Meta API)
│                                                   │
│  Tenant Settings:                                 │
│  - whatsapp_enabled (master switch)               │
│  - reminder_whatsapp_enabled (auto-reminders)     │
│  - whatsapp_phone_number_id                       │
│  - whatsapp_access_token (encrypted)              │
│  - whatsapp_business_account_id                   │
└───────────────────────┬─────────────────────────┘
                        │ HTTPS
                        ▼
            ┌───────────────────────┐
            │  Meta Cloud API       │
            │  graph.facebook.com   │
            │  /v18.0/{phone_id}/   │
            │  messages             │
            └───────────────────────┘
```

## Files Reference

| File | Purpose |
|------|---------|
| `app/Services/WhatsAppService.php` | HTTP client for Meta Cloud API |
| `app/Channels/WhatsAppChannel.php` | Laravel notification channel |
| `config/whatsapp.php` | API version and timeout config |
| `app/Models/Tenant.php` | WhatsApp fields (fillable, casts, hidden) |
| `app/Notifications/RecurringInvoiceReminderNotification.php` | Upcoming invoice reminder with `toWhatsApp()` |
| `app/Notifications/InvoiceOverdueReminderNotification.php` | Overdue reminder with `toWhatsApp()` |
| `app/Http/Controllers/SettingsController.php` | WhatsApp settings API endpoints |
| `database/migrations/2026_03_10_300000_add_whatsapp_fields_to_tenants_table.php` | Database migration |

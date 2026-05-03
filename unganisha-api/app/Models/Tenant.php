<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

class Tenant extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'name', 'email', 'phone', 'address',
        'logo_url', 'tax_id', 'currency', 'is_active',
        'trial_ends_at',
        'email_enabled', 'smtp_host', 'smtp_port', 'smtp_username',
        'smtp_password', 'smtp_encryption', 'smtp_from_email', 'smtp_from_name',
        'sms_enabled', 'gateway_email', 'gateway_username', 'sender_id', 'sms_authorization',
        // Branding
        'website', 'logo_path',
        'bank_name', 'bank_account_name', 'bank_account_number', 'bank_branch',
        'payment_instructions', 'payment_methods',
        // Pesapal integration
        'pesapal_enabled', 'pesapal_consumer_key', 'pesapal_consumer_secret',
        'pesapal_ipn_id', 'pesapal_sandbox',
        // Reminder templates
        'reminder_email_subject', 'reminder_email_body',
        'overdue_email_subject', 'overdue_email_body',
        'reminder_sms_body', 'overdue_sms_body',
        'reminder_sms_enabled', 'reminder_email_enabled',
        // WhatsApp Business API
        'whatsapp_enabled', 'reminder_whatsapp_enabled',
        'whatsapp_phone_number_id', 'whatsapp_access_token', 'whatsapp_business_account_id',
        // Invoice/quote email templates
        'invoice_email_subject', 'invoice_email_body',
        // Email branding
        'email_footer_text',
        // Subscription settings
        'subscription_grace_days',
        // Late fee settings
        'late_fee_enabled', 'late_fee_percent', 'late_fee_days',
    ];

    protected $hidden = [
        'smtp_password',
        'sms_authorization',
        'pesapal_consumer_key',
        'pesapal_consumer_secret',
        'whatsapp_access_token',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'email_enabled' => 'boolean',
        'sms_enabled' => 'boolean',
        'smtp_password' => 'encrypted',
        'sms_authorization' => 'encrypted',
        'trial_ends_at' => 'datetime',
        'reminder_sms_enabled' => 'boolean',
        'reminder_email_enabled' => 'boolean',
        'whatsapp_enabled' => 'boolean',
        'reminder_whatsapp_enabled' => 'boolean',
        'whatsapp_access_token' => 'encrypted',
        'payment_methods' => 'array',
        'pesapal_enabled' => 'boolean',
        'pesapal_sandbox' => 'boolean',
        'pesapal_consumer_secret' => 'encrypted',
        'subscription_grace_days' => 'integer',
        'late_fee_enabled' => 'boolean',
        'late_fee_percent' => 'decimal:2',
        'late_fee_days' => 'integer',
    ];

    protected $appends = ['logo_url'];

    public function getLogoUrlAttribute(): ?string
    {
        return $this->logo_path ? Storage::disk('public')->url($this->logo_path) : null;
    }

    public function users()
    {
        return $this->hasMany(User::class);
    }

    public function roles(): HasMany
    {
        return $this->hasMany(Role::class);
    }

    public function allowedPermissions(): BelongsToMany
    {
        return $this->belongsToMany(Permission::class, 'tenant_permissions');
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(TenantSubscription::class)->withoutGlobalScopes();
    }

    public function activeSubscription(): HasOne
    {
        return $this->hasOne(TenantSubscription::class)
            ->withoutGlobalScopes()
            ->where('status', 'active')
            ->where('ends_at', '>', now())
            ->latest('ends_at');
    }

    public function isOnTrial(): bool
    {
        return $this->trial_ends_at && $this->trial_ends_at->isFuture();
    }

    public function hasActiveSubscription(): bool
    {
        return $this->activeSubscription()->exists();
    }

    public function hasAccess(): bool
    {
        return $this->is_active && ($this->isOnTrial() || $this->hasActiveSubscription());
    }

    /**
     * @return string trial|subscribed|expired|deactivated
     */
    public function subscriptionStatus(): string
    {
        if (!$this->is_active) {
            return 'deactivated';
        }

        if ($this->hasActiveSubscription()) {
            return 'subscribed';
        }

        if ($this->isOnTrial()) {
            return 'trial';
        }

        return 'expired';
    }

    public function daysRemaining(): int
    {
        if ($this->hasActiveSubscription()) {
            $sub = $this->activeSubscription;
            return $sub ? (int) now()->diffInDays($sub->ends_at, false) : 0;
        }

        if ($this->isOnTrial()) {
            return (int) now()->diffInDays($this->trial_ends_at, false);
        }

        return 0;
    }
}

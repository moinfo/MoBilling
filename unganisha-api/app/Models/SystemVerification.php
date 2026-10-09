<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class SystemVerification extends Model
{
    use HasFactory, HasUuids, SoftDeletes, BelongsToTenant;

    /**
     * The single registry of daily closing figures a system can require.
     * Adding a genuinely new figure (not just toggling these) still needs a
     * column on system_verification_reports plus a case in
     * StoreSystemVerificationReportRequest — this list just keeps every
     * place that enumerates "which fields exist" (admin toggles, report
     * validation, the frontend field registry) pointed at one source.
     */
    public const AVAILABLE_FIELDS = [
        'cash' => 'Cash',
        'sales' => 'Sales',
        'credit' => 'Credit',
        'gain_loss' => 'Gain / Loss',
    ];

    protected $fillable = [
        'tenant_id', 'name', 'domain_name', 'client_id',
        'login_username', 'login_password',
        // Each assigned person (and each system) can have their own daily
        // check-in window — this is not one rule for the whole tenant.
        'window_from', 'window_to',
        'assigned_user_id', 'is_active',
        'required_fields',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        // Decryptable, not hashed — the assigned staff and admin need to read
        // this back to actually log in to the client's system. Not $hidden,
        // unlike tenants.smtp_password — this one is meant to be shown.
        'login_password' => 'encrypted',
        'required_fields' => 'array',
    ];

    /**
     * Null means "all of them" — keeps every system created before this
     * setting existed behaving exactly as it did (all four required).
     */
    public function requiredFields(): array
    {
        return $this->required_fields ?? array_keys(self::AVAILABLE_FIELDS);
    }

    public function assignedUser()
    {
        return $this->belongsTo(User::class, 'assigned_user_id');
    }

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function reports()
    {
        return $this->hasMany(SystemVerificationReport::class);
    }

    public function todaysReport()
    {
        return $this->hasOne(SystemVerificationReport::class)
            ->whereDate('report_date', today());
    }
}

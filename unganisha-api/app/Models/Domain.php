<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Domain extends Model
{
    use HasUuids, BelongsToTenant;

    public const STATUSES = ['pending', 'active', 'expired', 'transferred_out', 'cancelled', 'failed'];

    protected $fillable = [
        'tenant_id', 'client_id', 'registrar_account_id', 'name', 'status',
        'registrant_handle', 'admin_handle', 'nsset_handle', 'keyset_handle',
        'registered_at', 'expires_at', 'auto_renew', 'client_subscription_id',
        'epp_auth_info', 'meta', 'legacy_id',
    ];

    protected $casts = [
        'registered_at' => 'date',
        'expires_at'    => 'date',
        'auto_renew'    => 'boolean',
        'epp_auth_info' => 'encrypted',
        'meta'          => 'array',
    ];

    protected $hidden = ['epp_auth_info'];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function registrarAccount()
    {
        return $this->belongsTo(RegistrarAccount::class);
    }

    public function subscription()
    {
        return $this->belongsTo(ClientSubscription::class, 'client_subscription_id');
    }

    public function logs()
    {
        return $this->hasMany(DomainLog::class)->latest();
    }

    /**
     * `name` has an unconditional DB-level unique constraint (a domain name
     * is a genuinely global resource — only one row can ever exist for it),
     * so a fresh order for a name whose only existing row is
     * cancelled/transferred_out must revive that row rather than insert a
     * new one, or it hits a raw 1062 duplicate-key error even though every
     * application-level uniqueness check (which excludes those statuses)
     * says it's fine to proceed. Deliberately not tenant-scoped — the same
     * global exclusion the uniqueness checks use, so whichever tenant
     * successfully orders the name next legitimately takes over the row,
     * same as it would at the real registry.
     *
     * Registry-specific fields reset to null on revive (a previous life's
     * handles/dates must not survive); $attributes can still override any
     * of them explicitly (e.g. addExisting() sets its own expires_at).
     */
    public static function reviveOrCreate(array $attributes): self
    {
        $registryReset = [
            'registrant_handle' => null, 'admin_handle' => null,
            'nsset_handle' => null, 'keyset_handle' => null,
            'registered_at' => null, 'expires_at' => null, 'epp_auth_info' => null,
        ];

        $existing = static::withoutGlobalScopes()
            ->where('name', $attributes['name'])
            ->whereIn('status', ['cancelled', 'transferred_out'])
            ->first();

        if ($existing) {
            $existing->fill(array_merge($registryReset, $attributes))->save();
            return $existing->fresh();
        }

        return static::create($attributes);
    }
}

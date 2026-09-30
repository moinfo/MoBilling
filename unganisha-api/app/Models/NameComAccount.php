<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** A tenant's Name.com API credential set (several per tenant; one is the default). The token is write-only. */
class NameComAccount extends Model
{
    use HasUuids, BelongsToTenant;

    protected $table = 'namecom_accounts';

    protected $fillable = [
        'tenant_id', 'label', 'is_default', 'username', 'token', 'token_hint', 'is_sandbox', 'status', 'status_message', 'last_verified_at',
    ];

    protected $casts = [
        'token'            => 'encrypted',
        'is_sandbox'       => 'boolean',
        'is_default'       => 'boolean',
        'last_verified_at' => 'datetime',
    ];

    protected $hidden = ['token'];

    public function toSafeArray(): array
    {
        // A wallet-gated reseller tenant's default account is a duplicate of
        // Moinfotech's own real credentials (see ResellerProvisioningService)
        // — it has to be, for their tenant to actually check/register
        // domains — but the reseller has no operational reason to see the
        // real Name.com username behind it, and every reason not to: it
        // identifies the actual supplier account, which a white-label
        // reseller's own view should never reveal.
        $isWalletGated = (bool) Tenant::withoutGlobalScopes()->find($this->tenant_id)?->is_wallet_gated;

        return [
            'id'               => $this->id,
            'label'            => $this->label ?: $this->username,
            'is_default'       => (bool) $this->is_default,
            'username'         => $isWalletGated ? null : $this->username,
            'token_hint'       => $this->token_hint ? '••••' . $this->token_hint : null,
            'is_sandbox'       => $this->is_sandbox,
            'status'           => $this->status,
            'status_message'   => $this->status_message,
            'last_verified_at' => $this->last_verified_at,
        ];
    }

    public function displayLabel(): string
    {
        return $this->label ?: $this->username;
    }

    /** The tenant's default account (explicit default, else the oldest). Ignores the request-scoped tenant filter. */
    public static function defaultFor(string $tenantId): ?self
    {
        return static::withoutGlobalScopes()->where('tenant_id', $tenantId)->orderByDesc('is_default')->orderBy('created_at')->orderBy('id')->first();
    }

    public static function findFor(string $tenantId, ?string $id): ?self
    {
        if (!$id) return null;
        return static::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('id', $id)->first();
    }
}

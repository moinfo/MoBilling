<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** A domain a WhatsApp expiry reminder invited the client to renew by replying "1". */
class WhatsappReminderTarget extends Model
{
    public $timestamps = false;

    protected $fillable = ['tenant_id', 'phone', 'client_id', 'domain_id', 'expires_at', 'created_at'];

    protected $casts = ['expires_at' => 'datetime', 'created_at' => 'datetime'];

    public function domain()
    {
        return $this->belongsTo(Domain::class);
    }

    /** Open (unexpired) targets for one tenant+phone, newest reminder first. */
    public static function openFor(string $tenantId, string $phone)
    {
        return static::where('tenant_id', $tenantId)->where('phone', $phone)
            ->where('expires_at', '>', now())->orderByDesc('created_at')->get();
    }

    /** Record (or refresh) a target; one row per phone+domain. */
    public static function record(string $tenantId, string $phone, string $clientId, string $domainId, int $days = 9): self
    {
        $t = static::where('tenant_id', $tenantId)->where('phone', $phone)->where('domain_id', $domainId)->first();
        $attrs = ['client_id' => $clientId, 'expires_at' => now()->addDays($days)];
        if ($t) {
            $t->update($attrs + ['created_at' => now()]);
            return $t;
        }
        return static::create($attrs + ['tenant_id' => $tenantId, 'phone' => $phone, 'domain_id' => $domainId, 'created_at' => now()]);
    }
}

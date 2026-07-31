<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * An FCM registration token for one signed-in device.
 *
 * Deliberately NOT BelongsToTenant: pushes are dispatched from queue jobs and
 * webhooks where no tenant context is bound, and the owner morph already
 * scopes every read.
 */
class DeviceToken extends Model
{
    use HasUuids;

    protected $fillable = [
        'tenant_id', 'owner_type', 'owner_id', 'token', 'platform', 'app', 'last_seen_at',
    ];

    protected $casts = [
        'last_seen_at' => 'datetime',
    ];

    public function owner()
    {
        return $this->morphTo();
    }

    /** Every token that should receive a notification aimed at $notifiable. */
    public static function tokensFor(object $notifiable): array
    {
        // Invoice/receipt/ticket notifications target the Client record; the
        // devices belong to its portal logins, so fan out through them.
        if ($notifiable instanceof Client) {
            $userIds = ClientUser::where('client_id', $notifiable->id)
                ->where('is_active', true)->pluck('id');

            return static::where('owner_type', ClientUser::class)
                ->whereIn('owner_id', $userIds)->pluck('token')->all();
        }

        return static::where('owner_type', $notifiable::class)
            ->where('owner_id', $notifiable->getKey())
            ->pluck('token')->all();
    }
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class CronLog extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'tenant_id', 'command', 'description', 'results',
        'status', 'error', 'started_at', 'finished_at',
    ];

    protected $casts = [
        'results' => 'array',
        'started_at' => 'datetime',
        'finished_at' => 'datetime',
        'created_at' => 'datetime',
    ];

    public function tenant()
    {
        return $this->belongsTo(Tenant::class);
    }

    protected static function booted(): void
    {
        // One place to catch every scheduled-command failure rather than a
        // notification call at each of the ~4 `CronLog::create([...'status'
        // => 'failed'...])` sites in app/Console/Commands — new commands get
        // this for free too.
        static::created(function (self $log) {
            if ($log->status !== 'failed') {
                return;
            }

            try {
                $superAdmins = User::where('role', 'super_admin')->get();
                if ($superAdmins->isNotEmpty()) {
                    \Illuminate\Support\Facades\Notification::send(
                        $superAdmins,
                        new \App\Notifications\CronJobFailedNotification($log),
                    );
                }
            } catch (\Throwable $e) {
                \Illuminate\Support\Facades\Log::warning('CronLog failure notification failed', ['error' => $e->getMessage()]);
            }
        });
    }
}

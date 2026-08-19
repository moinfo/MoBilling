<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StaffSalary extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['tenant_id', 'user_id', 'basic_salary', 'effective_from', 'notes'];

    protected $casts = [
        'effective_from' => 'date',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** The salary in effect for a given date — latest row whose effective_from is on/before it. */
    public static function effectiveFor(string $userId, string $date): ?self
    {
        return static::withoutGlobalScopes()
            ->where('user_id', $userId)
            ->where('effective_from', '<=', $date)
            ->orderByDesc('effective_from')
            ->first();
    }
}

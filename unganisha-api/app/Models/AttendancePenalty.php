<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
class AttendancePenalty extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = [
        'tenant_id', 'user_id', 'date', 'penalty_type', 'amount', 'notes',
        'waived', 'waived_by', 'waived_at', 'waive_reason',
    ];
    protected $casts = ['date' => 'date', 'amount' => 'decimal:2', 'waived' => 'boolean', 'waived_at' => 'datetime'];
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}

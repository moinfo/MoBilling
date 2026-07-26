<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
class Attendance extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = ['tenant_id', 'user_id', 'date', 'status', 'status_note', 'check_in_at', 'check_out_at'];
    protected $casts = ['date' => 'date', 'check_in_at' => 'datetime', 'check_out_at' => 'datetime'];

    /** Excused-day statuses that suppress absence/late marks and deductions. */
    public const EXCUSED = ['leave', 'sick', 'field'];

    public function isExcused(): bool
    {
        return in_array($this->status, self::EXCUSED, true);
    }

    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}

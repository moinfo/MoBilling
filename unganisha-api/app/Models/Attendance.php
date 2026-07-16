<?php
namespace App\Models;
use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
class Attendance extends Model
{
    use HasUuids, BelongsToTenant;
    protected $fillable = ['tenant_id', 'user_id', 'date', 'check_in_at', 'check_out_at'];
    protected $casts = ['date' => 'date', 'check_in_at' => 'datetime', 'check_out_at' => 'datetime'];
    public function user(): BelongsTo { return $this->belongsTo(User::class); }
}

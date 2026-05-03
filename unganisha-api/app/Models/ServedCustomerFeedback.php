<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ServedCustomerFeedback extends Model
{
    use HasUuids, BelongsToTenant;

    protected $table = 'served_customer_feedbacks';

    protected $fillable = [
        'served_customer_id', 'called_at', 'rating',
        'outcome', 'feedback', 'challenges', 'internal_notes',
        'created_by_user_id',
    ];

    protected $casts = [
        'called_at' => 'datetime',
        'rating'    => 'integer',
    ];

    public function customer(): BelongsTo
    {
        return $this->belongsTo(ServedCustomer::class, 'served_customer_id');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_user_id');
    }
}

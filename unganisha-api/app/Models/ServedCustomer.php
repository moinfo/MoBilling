<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ServedCustomer extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['name', 'phone', 'served_date', 'notes', 'created_by_user_id'];

    protected $casts = [
        'served_date' => 'date',
    ];

    public function services(): BelongsToMany
    {
        return $this->belongsToMany(ServedService::class, 'served_customer_service');
    }

    public function feedbacks(): HasMany
    {
        return $this->hasMany(ServedCustomerFeedback::class)->latest();
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_user_id');
    }
}

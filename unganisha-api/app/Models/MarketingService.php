<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class MarketingService extends Model
{
    use HasUuids, BelongsToTenant;

    protected $table = 'marketing_services';

    protected $fillable = ['name', 'sort_order'];
}

<?php

namespace App\Models;

use App\Traits\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class ClientDesignOrder extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = [
        'client_id', 'title', 'design_type', 'description', 'reference_url',
        'assigned_designer_id', 'status', 'due_date', 'file_url',
        'revision_count', 'revision_notes', 'price', 'created_by',
    ];

    protected $casts = [
        'due_date'       => 'date',
        'revision_count' => 'integer',
        'price'          => 'decimal:2',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class);
    }

    public function designer()
    {
        return $this->belongsTo(User::class, 'assigned_designer_id');
    }
}

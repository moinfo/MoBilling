<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Release extends Model
{
    use HasUuids;

    protected $fillable = ['version', 'changelog', 'download_url', 'is_active', 'released_at'];

    protected $casts = [
        'is_active' => 'boolean',
        'released_at' => 'datetime',
    ];

    /** Simple string comparison works for plain semver (1.2.3) — no pre-release/build metadata expected here. */
    public function isNewerThan(string $version): bool
    {
        return version_compare($this->version, $version, '>');
    }
}

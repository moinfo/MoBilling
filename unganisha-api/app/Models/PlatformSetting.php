<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class PlatformSetting extends Model
{
    use HasUuids;

    protected $fillable = ['key', 'value'];

    public static function get(string $key, ?string $default = null): ?string
    {
        return static::where('key', $key)->value('value') ?? $default;
    }

    public static function set(string $key, ?string $value): void
    {
        static::updateOrCreate(['key' => $key], ['value' => $value]);
    }

    public static function getBankDetails(): array
    {
        $settings = static::whereIn('key', [
            'platform_bank_name',
            'platform_bank_account_name',
            'platform_bank_account_number',
            'platform_bank_branch',
            'platform_payment_instructions',
        ])->pluck('value', 'key');

        return [
            'bank_name' => $settings['platform_bank_name'] ?? '',
            'bank_account_name' => $settings['platform_bank_account_name'] ?? '',
            'bank_account_number' => $settings['platform_bank_account_number'] ?? '',
            'bank_branch' => $settings['platform_bank_branch'] ?? '',
            'payment_instructions' => $settings['platform_payment_instructions'] ?? '',
        ];
    }
}

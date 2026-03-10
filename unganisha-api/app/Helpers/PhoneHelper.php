<?php

namespace App\Helpers;

class PhoneHelper
{
    /**
     * Normalize a phone number to digits only, stripping country code prefix.
     * Returns the last 9 digits (local number without country code).
     *
     * Examples:
     *   0652894205       → 652894205
     *   +255 652 894 205 → 652894205
     *   +255652894205    → 652894205
     *   255652894205     → 652894205
     *   652894205        → 652894205
     */
    public static function normalize(string $phone): string
    {
        // Strip everything except digits
        $digits = preg_replace('/\D/', '', $phone);

        // Remove leading country code (255 for Tanzania, 254 for Kenya)
        if (strlen($digits) >= 12 && str_starts_with($digits, '255')) {
            $digits = substr($digits, 3);
        } elseif (strlen($digits) >= 12 && str_starts_with($digits, '254')) {
            $digits = substr($digits, 3);
        }

        // Remove leading zero
        if (str_starts_with($digits, '0')) {
            $digits = substr($digits, 1);
        }

        // Return last 9 digits (local number)
        return substr($digits, -9);
    }

    /**
     * Build a where clause that matches a phone column against a normalized input.
     * Compares last 9 digits of both values.
     */
    public static function wherePhone($query, string $column, string $phone)
    {
        $normalized = self::normalize($phone);

        if (strlen($normalized) < 7) {
            // Too short to be a valid phone — won't match anything
            return $query->whereRaw('1 = 0');
        }

        // Compare last 9 digits of the stored phone (stripped of non-digits)
        return $query->whereRaw(
            "RIGHT(REGEXP_REPLACE({$column}, '[^0-9]', ''), 9) = ?",
            [$normalized]
        );
    }
}

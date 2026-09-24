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
     * Country code of a phone number when it is unambiguous, else null. A number with more than 9 digits and no
     * leading 0 carries its country code as the leading digits (255 Tanzania, 254 Kenya ...); 0xxxxxxxxx or a bare
     * 9-digit number is national/unknown -> null.
     */
    public static function countryCode(string $phone): ?string
    {
        $digits = preg_replace('/\D/', '', $phone);
        if (str_starts_with($digits, '00')) {
            $digits = substr($digits, 2);
        }
        if (strlen($digits) < 11 || str_starts_with($digits, '0')) {
            return null;
        }

        return substr($digits, 0, strlen($digits) - 9);
    }

    /** Digits only, no leading 00 or + (E.164 without the plus), e.g. 255712345678. */
    public static function e164(string $phone): string
    {
        $digits = preg_replace('/\D/', '', $phone);

        return str_starts_with($digits, '00') ? substr($digits, 2) : $digits;
    }

    /** True for a number that is known to belong to another country than Tanzania. */
    public static function isForeign(string $phone): bool
    {
        $cc = self::countryCode($phone);

        return $cc !== null && $cc !== '255';
    }

    /**
     * Build a where clause that matches a phone column against a normalized input.
     * Compares last 9 digits of both values.
     *
     * When $rawPhone (the number as received, with its country code) has a known country code, a stored number
     * whose own country code is known and DIFFERENT is not a match (a 254... number never matches a Tanzanian
     * client that merely shares the last 9 digits). A stored 0xxxxxxxxx (10 digits) is national Tanzanian format,
     * so it counts as 255; a bare 9-digit or unrecognisable stored value is unknown and stays a match.
     */
    public static function wherePhone($query, string $column, string $phone, ?string $rawPhone = null)
    {
        $normalized = self::normalize($phone);

        if (strlen($normalized) < 7) {
            // Too short to be a valid phone — won't match anything
            return $query->whereRaw('1 = 0');
        }

        // Compare last 9 digits of the stored phone (stripped of non-digits)
        $query->whereRaw(
            "RIGHT(REGEXP_REPLACE({$column}, '[^0-9]', ''), 9) = ?",
            [$normalized]
        );

        $cc = $rawPhone !== null ? self::countryCode($rawPhone) : null;
        if ($cc !== null) {
            $d = "REGEXP_REPLACE({$column}, '[^0-9]', '')";
            $query->whereRaw(
                "((CASE WHEN LENGTH({$d}) >= 11 AND LEFT({$d}, 1) <> '0' THEN LEFT({$d}, LENGTH({$d}) - 9) "
                . "WHEN LENGTH({$d}) = 10 AND LEFT({$d}, 1) = '0' THEN '255' ELSE NULL END) IS NULL "
                . "OR (CASE WHEN LENGTH({$d}) >= 11 AND LEFT({$d}, 1) <> '0' THEN LEFT({$d}, LENGTH({$d}) - 9) "
                . "WHEN LENGTH({$d}) = 10 AND LEFT({$d}, 1) = '0' THEN '255' ELSE NULL END) = ?)",
                [$cc]
            );
        }

        return $query;
    }
}

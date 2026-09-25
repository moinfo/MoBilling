<?php

namespace App\Services;

/**
 * Best-effort reader for pasted mobile-money SMS / bank credit alerts (English + Kiswahili).
 * It only PRE-FILLS a form: nothing here records money, and every field may come back null.
 */
class PaymentMessageParser
{
    private const AMOUNT_RE = '/(?:TSh|TZS|T\.?\s?Shs?\.?|Sh\.?)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i';
    private const NOT_AMOUNT_CONTEXT = '/(balance|salio|fee|ada|charge|gharama|limit)[^0-9]{0,12}$/i';
    private const REF_RE = '/(?:\bRef(?:erence)?\.?(?:\s*(?:No|ID|Number)\.?)?|Txn\.?\s*(?:ID|No)\.?|Trans(?:action)?\.?\s*(?:ID|No|Number)\.?|Muamala\s*(?:Namba|ID|No)\.?|Kumbukumbu(?:\s*(?:Namba|No))?\.?|Receipt\s*(?:No|Number)\.?|Namba\s*ya\s*muamala)\s*(?:is|ni)?\s*[:#\-]?\s*([A-Z0-9][A-Z0-9._\-]{5,29})/i';

    public static function parse(string $text): array
    {
        $text = trim(preg_replace('/\s+/u', ' ', $text));

        return [
            'amount'         => self::amount($text),
            'reference'      => self::reference($text),
            'phone'          => self::phone($text),
            'name'           => self::name($text),
            'invoice_number' => self::invoiceNumber($text),
        ];
    }

    private static function amount(string $t): ?float
    {
        if (!preg_match_all(self::AMOUNT_RE, $t, $m, PREG_OFFSET_CAPTURE)) {
            return null;
        }
        foreach ($m[1] as $i => [$num, $off]) {
            $before = substr($t, max(0, $m[0][$i][1] - 20), min(20, $m[0][$i][1]));
            if (preg_match(self::NOT_AMOUNT_CONTEXT, $before)) {
                continue;
            }
            $v = (float) str_replace(',', '', $num);

            return $v > 0 ? $v : null;
        }

        return null;
    }

    private static function reference(string $t): ?string
    {
        if (preg_match_all(self::REF_RE, $t, $m)) {
            foreach ($m[1] as $cand) {
                $cand = rtrim($cand, '.-_');
                // a code must carry a digit (rejects words such as "Reference" / "Received")
                if (preg_match('/\d/', $cand) && strlen($cand) >= 6) {
                    return strtoupper($cand);
                }
            }
        }
        // M-Pesa style: the message opens with the code ("QGH7X8K2LM Confirmed. ...")
        if (preg_match('/^([A-Z0-9]{8,12})\s+(?:Confirmed|Imethibitishwa)/i', $t, $m) && preg_match('/\d/', $m[1])) {
            return strtoupper($m[1]);
        }

        return null;
    }

    private static function phone(string $t): ?string
    {
        if (preg_match('/(?<![\d])(?:\+?255|0)[67]\d{8}(?!\d)/', $t, $m)) {
            $d = preg_replace('/\D/', '', $m[0]);

            return str_starts_with($d, '0') ? '255' . substr($d, 1) : $d;
        }

        return null;
    }

    private static function name(string $t): ?string
    {
        $stop = '(?=\s*(?:[\d.,(\-\x{2013}]|\bon\b|\bat\b|\btarehe\b|\bsaa\b|\bRef|\bMuamala\b|\bKumbukumbu\b|\bTrans|\bTxn\b|\bNew\b|\bSalio\b|\bBalance\b|$))';
        // "from JOHN DOE 2557..." / "kutoka kwa JOHN DOE"
        if (preg_match('/(?:\bfrom|\bkutoka(?:\s+kwa)?)\s+(?!kwa\b)([A-Za-z][A-Za-z\' ]{2,40}?)' . $stop . '/u', $t, $m)) {
            return self::cleanName($m[1]);
        }
        // "kutoka 255712345678 - JOHN DOE" / "from 0712345678 JOHN DOE"
        if (preg_match('/(?:\bfrom|\bkutoka(?:\s+kwa)?)\s+\+?[0-9]{9,12}\s*[-\x{2013}]?\s*([A-Za-z][A-Za-z\' ]{2,40}?)' . $stop . '/u', $t, $m)) {
            return self::cleanName($m[1]);
        }

        return null;
    }

    private static function cleanName(string $n): ?string
    {
        $n = trim($n);

        return strlen($n) >= 3 ? mb_convert_case($n, MB_CASE_TITLE) : null;
    }

    private static function invoiceNumber(string $t): ?string
    {
        // Our own numbering: INV-2026-0012 (also tolerates a client typing INV0012 / INV 12 in the narration)
        return preg_match('/\b(INV(?:-?\d{4})?-?\d{2,6})\b/i', $t, $m) ? strtoupper($m[1]) : null;
    }
}

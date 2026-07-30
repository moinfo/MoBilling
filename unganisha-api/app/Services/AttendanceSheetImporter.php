<?php

namespace App\Services;

use App\Models\User;
use Carbon\Carbon;

/**
 * Imports an iVMS-4200 Time & Attendance export (CSV) into attendance.
 *
 * The export's columns vary by report type and locale, so the caller supplies a
 * mapping (which column is the person, the date, the times). Two time shapes are
 * supported:
 *   - 'inout'  : the row already has a check-in column and a check-out column.
 *   - 'single' : one punch per row (a time or datetime); rows are grouped per
 *                person+day and reduced to earliest-in / latest-out.
 * Staff are matched by name or by device employee number. Unmatched identities
 * are reported back so the operator can fix the mapping and re-upload.
 */
class AttendanceSheetImporter
{
    public function __construct(private AttendanceUpserter $upserter) {}

    /**
     * Read a CSV file into [headers, rows] for preview/mapping.
     *
     * @return array{headers:string[],rows:array<int,array<int,string>>,total:int}
     */
    public function parse(string $path, int $previewLimit = 8): array
    {
        $all = $this->readRows($path);
        $headers = array_shift($all) ?? [];

        return [
            'headers' => $headers,
            'rows'    => array_slice($all, 0, $previewLimit),
            'total'   => count($all),
        ];
    }

    /**
     * Read the whole sheet into trimmed string rows (header first). Handles
     * what iVMS-4200 actually exports as "CSV": UTF-16LE/BE or UTF-8 with a
     * BOM, and comma, semicolon or tab delimiters (auto-detected).
     *
     * @return array<int,array<int,string>>
     */
    private function readRows(string $path): array
    {
        $content = (string) @file_get_contents($path);
        if ($content === '') {
            return [];
        }

        // Normalise encoding to UTF-8.
        if (str_starts_with($content, "\xFF\xFE")) {
            $content = mb_convert_encoding(substr($content, 2), 'UTF-8', 'UTF-16LE');
        } elseif (str_starts_with($content, "\xFE\xFF")) {
            $content = mb_convert_encoding(substr($content, 2), 'UTF-8', 'UTF-16BE');
        } elseif (str_starts_with($content, "\xEF\xBB\xBF")) {
            $content = substr($content, 3);
        } elseif (str_contains($content, "\x00")) {
            // UTF-16 without a BOM (NUL bytes betray it).
            $content = mb_convert_encoding($content, 'UTF-8', 'UTF-16LE');
        }

        // Whatever the source was, end up with clean UTF-8 — json_encode
        // rejects the whole response over a single stray byte otherwise.
        if (!mb_check_encoding($content, 'UTF-8')) {
            $from = mb_detect_encoding($content, ['UTF-8', 'Windows-1252', 'ISO-8859-1'], true) ?: 'Windows-1252';
            $content = mb_convert_encoding($content, 'UTF-8', $from);
        }
        $content = (string) mb_convert_encoding($content, 'UTF-8', 'UTF-8'); // scrub residual invalid sequences

        $lines = preg_split('/\r\n|\r|\n/', $content) ?: [];
        $firstLine = '';
        foreach ($lines as $l) {
            if (trim($l) !== '') { $firstLine = $l; break; }
        }

        // Pick the delimiter that splits the header into the most columns.
        $delim = ',';
        $best = 0;
        foreach ([',', ';', "\t"] as $d) {
            $n = count(str_getcsv($firstLine, $d));
            if ($n > $best) { $best = $n; $delim = $d; }
        }

        $rows = [];
        foreach ($lines as $l) {
            if (trim($l) === '') {
                continue;
            }
            $rows[] = array_map(fn ($v) => trim((string) $v), str_getcsv($l, $delim));
        }

        return $rows;
    }

    /**
     * Import the file per the mapping.
     *
     * @param  array{
     *   match_by:string, identity_col:int, date_col:?int,
     *   time_mode:string, in_col:?int, out_col:?int, time_col:?int
     * }  $map
     * @return array{days:int,matched_rows:int,unmatched:array<string,int>,skipped:int}
     */
    public function import(string $tenantId, string $path, array $map): array
    {
        // person identity => user id
        $users = User::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('is_active', true)
            ->get(['id', 'name', 'device_employee_no']);
        $byName = $users->keyBy(fn ($u) => $this->norm($u->name));
        $byNo   = $users->filter(fn ($u) => $u->device_employee_no)->keyBy(fn ($u) => (string) $u->device_employee_no);

        $matchByName = ($map['match_by'] ?? 'name') === 'name';
        $single = ($map['time_mode'] ?? 'single') === 'single';

        // grouped[userId][date] = Carbon[]
        $grouped = [];
        $matchedRows = 0;
        $skipped = 0;
        $unmatched = [];

        $allRows = $this->readRows($path);
        array_shift($allRows); // header

        foreach ($allRows as $data) {
            $cell = fn ($i) => $i === null || $i < 0 ? null : trim((string) ($data[$i] ?? ''));

            $identity = $cell($map['identity_col']);
            if ($identity === null || $identity === '') {
                $skipped++;
                continue;
            }

            $user = $matchByName ? $byName->get($this->norm($identity)) : $byNo->get($identity);
            if (!$user) {
                $unmatched[$identity] = ($unmatched[$identity] ?? 0) + 1;
                continue;
            }

            // Resolve the day + the swipe time(s) for this row.
            $dateStr = $map['date_col'] !== null ? $cell($map['date_col']) : null;

            if ($single) {
                $t = $this->parseDateTime($cell($map['time_col']), $dateStr);
                if (!$t) { $skipped++; continue; }
                $grouped[$user->id][$t->toDateString()][] = $t;
                $matchedRows++;
            } else {
                $in  = $this->parseDateTime($cell($map['in_col']), $dateStr);
                $out = $this->parseDateTime($cell($map['out_col']), $dateStr);
                if (!$in && !$out) { $skipped++; continue; }
                $day = ($in ?? $out)->toDateString();
                foreach ([$in, $out] as $t) {
                    if ($t) { $grouped[$user->id][$day][] = $t; }
                }
                $matchedRows++;
            }
        }

        $days = 0;
        foreach ($grouped as $uid => $perDay) {
            foreach ($perDay as $day => $times) {
                if ($this->upserter->applyDay($tenantId, $uid, $day, $times)) {
                    $days++;
                }
            }
        }

        return ['days' => $days, 'matched_rows' => $matchedRows, 'unmatched' => $unmatched, 'skipped' => $skipped];
    }

    private function norm(string $s): string
    {
        return preg_replace('/\s+/', ' ', mb_strtolower(trim($s)));
    }

    /**
     * Parse a time or datetime cell. If $value is time-only (HH:MM[:SS]) a
     * separate $dateStr supplies the day; a full datetime is used as-is.
     */
    private function parseDateTime(?string $value, ?string $dateStr): ?Carbon
    {
        $value = $value !== null ? trim($value) : '';
        if ($value === '' || $value === '-') {
            return null;
        }
        try {
            // time-only → needs a date
            if (preg_match('/^\d{1,2}:\d{2}(:\d{2})?$/', $value)) {
                if (!$dateStr) {
                    return null;
                }
                return Carbon::parse(trim($dateStr) . ' ' . $value);
            }
            return Carbon::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }
}

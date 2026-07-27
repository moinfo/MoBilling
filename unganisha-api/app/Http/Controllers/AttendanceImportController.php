<?php

namespace App\Http\Controllers;

use App\Services\AttendanceSheetImporter;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

/**
 * Upload an iVMS-4200 Time & Attendance CSV export and fold it into attendance.
 * Two steps: preview (parse headers + guess the mapping) then commit (import
 * per the confirmed mapping). The file is re-sent on commit — nothing is stored.
 */
class AttendanceImportController extends Controller
{
    use AuthorizesPermissions;

    public function preview(Request $request, AttendanceSheetImporter $importer)
    {
        $this->authorizePermission('attendance.manage');
        $request->validate([
            'file' => 'required|file|mimes:csv,txt|max:10240',
        ]);

        $parsed = $importer->parse($request->file('file')->getRealPath());

        return response()->json([
            'data' => [
                'headers' => $parsed['headers'],
                'rows'    => $parsed['rows'],
                'total'   => $parsed['total'],
                'guess'   => $this->guessMapping($parsed['headers']),
            ],
        ]);
    }

    public function commit(Request $request, AttendanceSheetImporter $importer)
    {
        $this->authorizePermission('attendance.manage');
        $data = $request->validate([
            'file'         => 'required|file|mimes:csv,txt|max:10240',
            'match_by'     => 'required|in:name,employee_no',
            'identity_col' => 'required|integer|min:0',
            'date_col'     => 'nullable|integer|min:0',
            'time_mode'    => 'required|in:single,inout',
            'time_col'     => 'nullable|integer|min:0|required_if:time_mode,single',
            'in_col'       => 'nullable|integer|min:0|required_if:time_mode,inout',
            'out_col'      => 'nullable|integer|min:0|required_if:time_mode,inout',
        ]);

        $res = $importer->import(
            auth()->user()->tenant_id,
            $request->file('file')->getRealPath(),
            [
                'match_by'     => $data['match_by'],
                'identity_col' => (int) $data['identity_col'],
                'date_col'     => isset($data['date_col']) ? (int) $data['date_col'] : null,
                'time_mode'    => $data['time_mode'],
                'time_col'     => isset($data['time_col']) ? (int) $data['time_col'] : null,
                'in_col'       => isset($data['in_col']) ? (int) $data['in_col'] : null,
                'out_col'      => isset($data['out_col']) ? (int) $data['out_col'] : null,
            ],
        );

        return response()->json(['data' => $res]);
    }

    /** Best-effort column guesses from iVMS header names (0-based indexes, or null). */
    private function guessMapping(array $headers): array
    {
        $find = function (array $needles) use ($headers) {
            foreach ($headers as $i => $h) {
                $h = mb_strtolower($h);
                foreach ($needles as $n) {
                    if (str_contains($h, $n)) {
                        return $i;
                    }
                }
            }
            return null;
        };

        $nameCol = $find(['name', 'jina']);
        $noCol   = $find(['employee no', 'employee id', 'person id', 'job no', 'emp', 'card no']);
        $dateCol = $find(['date', 'tarehe']);
        $inCol   = $find(['on-duty', 'on duty', 'check-in', 'check in', 'clock in', 'first', 'time in']);
        $outCol  = $find(['off-duty', 'off duty', 'check-out', 'check out', 'clock out', 'last', 'time out']);
        $timeCol = $find(['time', 'muda', 'datetime', 'punch']);

        $hasInOut = $inCol !== null && $outCol !== null;

        return [
            'match_by'     => $noCol !== null ? 'employee_no' : 'name',
            'identity_col' => $noCol ?? $nameCol ?? 0,
            'date_col'     => $dateCol,
            'time_mode'    => $hasInOut ? 'inout' : 'single',
            'in_col'       => $inCol,
            'out_col'      => $outCol,
            'time_col'     => $hasInOut ? null : ($timeCol ?? $dateCol),
        ];
    }
}

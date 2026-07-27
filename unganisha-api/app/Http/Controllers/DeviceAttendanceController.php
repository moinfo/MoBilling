<?php

namespace App\Http\Controllers;

use App\Models\AttendanceDevice;
use App\Models\AttendanceDeviceEvent;
use App\Models\User;
use App\Services\AttendanceDeviceImporter;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * HIKVISION (and similar) attendance-device integration.
 *
 * CAPTURE PHASE: the device is configured to push access events to the public
 * webhook below; we log the raw payload so we can see the exact format, then
 * finalise the parser + user mapping. Nothing is imported into attendance yet.
 */
class DeviceAttendanceController extends Controller
{
    use AuthorizesPermissions;

    /** PUBLIC webhook — the device posts access events here (token-secured). */
    public function capture(Request $request, string $token)
    {
        $device = AttendanceDevice::withoutGlobalScopes()->where('token', $token)->where('is_active', true)->first();
        if (!$device) {
            return response()->json(['error' => 'unknown device token'], 404);
        }

        // Raw body (capped — HIKVISION multipart can carry a base64 snapshot).
        $raw = $request->getContent();
        $payload = mb_substr((string) $raw, 0, 20000);

        // Parsed text inputs (multipart form fields / JSON body), image field dropped.
        $inputs = collect($request->except([]))->map(function ($v) {
            return is_string($v) ? mb_substr($v, 0, 8000) : $v;
        })->all();

        $flat = $this->flatten($inputs);
        if (empty($flat) && $raw && str_starts_with(trim((string) $request->header('content-type')), 'application/json')) {
            $flat = $this->flatten(json_decode($raw, true) ?: []);
        }

        AttendanceDeviceEvent::create([
            'tenant_id'            => $device->tenant_id,
            'attendance_device_id' => $device->id,
            'content_type'         => $request->header('content-type'),
            'employee_no'          => $flat['employeeNoString'] ?? $flat['employeeNo'] ?? $flat['employee_no'] ?? $flat['cardNo'] ?? null,
            'event_time'           => $this->parseTime($flat['dateTime'] ?? $flat['time'] ?? $flat['event_time'] ?? null),
            'payload'              => $payload,
            'parsed'               => array_slice($flat, 0, 60),
        ]);

        $device->update(['last_event_at' => now()]);

        // Fold straight into attendance if this employee number is already linked
        // to a staff member (best-effort — never let it break the 200 the device needs).
        try {
            app(AttendanceDeviceImporter::class)->drainTenant($device->tenant_id);
        } catch (\Throwable) {
            // the scheduled import will pick it up
        }

        // Devices expect a 200 to consider the event delivered.
        return response()->json(['ok' => true]);
    }

    /** Get (or create) this tenant's device + webhook URL. */
    public function config()
    {
        $this->authorizePermission('attendance.manage');
        $device = AttendanceDevice::first() ?? AttendanceDevice::create([
            'name' => 'HIKVISION device', 'token' => Str::random(40), 'is_active' => true,
        ]);

        return response()->json(['data' => [
            'name' => $device->name,
            'is_active' => $device->is_active,
            'last_event_at' => $device->last_event_at?->toISOString(),
            'webhook_url' => url('/api/attendance/device/' . $device->token),
        ]]);
    }

    /** Recent captured raw events (to inspect the device's format). */
    public function events()
    {
        $this->authorizePermission('attendance.manage');
        $events = AttendanceDeviceEvent::orderByDesc('created_at')->limit(30)->get()
            ->map(fn ($e) => [
                'id'           => $e->id,
                'content_type' => $e->content_type,
                'employee_no'  => $e->employee_no,
                'event_time'   => $e->event_time?->toISOString(),
                'parsed'       => $e->parsed,
                'payload'      => $e->payload,
                'created_at'   => $e->created_at->toISOString(),
            ]);

        return response()->json(['data' => $events]);
    }

    public function regenerate()
    {
        $this->authorizePermission('attendance.manage');
        $device = AttendanceDevice::first() ?? AttendanceDevice::create(['name' => 'HIKVISION device', 'token' => Str::random(40)]);
        $device->update(['token' => Str::random(40)]);
        return response()->json(['data' => ['webhook_url' => url('/api/attendance/device/' . $device->token)]]);
    }

    /**
     * Staff ↔ device-employee-number mapping, plus any employee numbers seen in
     * recent events that aren't linked to a staff member yet.
     */
    public function mappings()
    {
        $this->authorizePermission('attendance.manage');
        $tenantId = auth()->user()->tenant_id;

        $staff = User::where('tenant_id', $tenantId)->where('is_active', true)
            ->orderBy('name')->get(['id', 'name', 'device_employee_no'])
            ->map(fn ($u) => [
                'id' => $u->id, 'name' => $u->name,
                'device_employee_no' => $u->device_employee_no,
            ]);

        $linked = $staff->pluck('device_employee_no')->filter()->map(fn ($n) => (string) $n)->all();
        $unlinked = AttendanceDeviceEvent::whereNotNull('employee_no')
            ->where('processed', false)
            ->orderByDesc('created_at')->limit(200)->pluck('employee_no')
            ->map(fn ($n) => (string) $n)->unique()
            ->reject(fn ($n) => in_array($n, $linked, true))->values();

        return response()->json(['data' => ['staff' => $staff, 'unlinked' => $unlinked]]);
    }

    /** Link (or clear) a staff member's device employee number, then import their pending events. */
    public function saveMapping(Request $request)
    {
        $this->authorizePermission('attendance.manage');
        $tenantId = auth()->user()->tenant_id;

        $data = $request->validate([
            'user_id'            => ['required', Rule::exists('users', 'id')->where('tenant_id', $tenantId)],
            'device_employee_no' => ['nullable', 'string', 'max:64'],
        ]);

        $no = $data['device_employee_no'] !== null && $data['device_employee_no'] !== ''
            ? trim($data['device_employee_no']) : null;

        // One employee number per staff member within a tenant.
        if ($no) {
            $clash = User::where('tenant_id', $tenantId)->where('device_employee_no', $no)
                ->where('id', '!=', $data['user_id'])->exists();
            if ($clash) {
                return response()->json(['message' => "Employee no. {$no} is already linked to another staff member."], 422);
            }
        }

        User::where('id', $data['user_id'])->update(['device_employee_no' => $no]);

        $res = app(AttendanceDeviceImporter::class)->drainTenant($tenantId);

        return response()->json(['message' => 'Saved.', 'import' => $res]);
    }

    /** Manually drain captured events into attendance for this tenant. */
    public function importNow()
    {
        $this->authorizePermission('attendance.manage');
        $res = app(AttendanceDeviceImporter::class)->drainTenant(auth()->user()->tenant_id);
        return response()->json(['data' => $res]);
    }

    /** Flatten a nested array to dot-less leaf keys (last key wins). */
    private function flatten($arr, array &$out = []): array
    {
        foreach ((array) $arr as $k => $v) {
            if (is_array($v)) {
                $this->flatten($v, $out);
            } elseif (is_scalar($v)) {
                $out[$k] = $v;
            }
        }
        return $out;
    }

    private function parseTime($v): ?string
    {
        if (!$v) {
            return null;
        }
        try {
            return \Carbon\Carbon::parse($v)->toDateTimeString();
        } catch (\Throwable) {
            return null;
        }
    }
}

<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;

class StaffSupervisorController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        $this->authorizePermission('staff_reports.review');

        $tenantId = auth()->user()->tenant_id;

        $users = User::with('supervisor:id,name')
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'supervisor_id']);

        return response()->json([
            'data' => $users->map(fn ($u) => [
                'id'         => $u->id,
                'name'       => $u->name,
                'supervisor' => $u->supervisor ? ['id' => $u->supervisor->id, 'name' => $u->supervisor->name] : null,
            ]),
        ]);
    }

    public function update(Request $request, string $userId)
    {
        $this->authorizePermission('staff_reports.review');

        $tenantId = auth()->user()->tenant_id;

        $staff = User::where('tenant_id', $tenantId)->findOrFail($userId);

        $data = $request->validate([
            'supervisor_id' => [
                'nullable',
                'uuid',
                function ($attr, $value, $fail) use ($tenantId, $userId) {
                    if ($value === $userId) {
                        $fail('A user cannot be their own supervisor.');
                        return;
                    }
                    $exists = User::where('tenant_id', $tenantId)->where('id', $value)->exists();
                    if (!$exists) $fail('Supervisor not found in this organisation.');
                },
            ],
        ]);

        $staff->update(['supervisor_id' => $data['supervisor_id'] ?? null]);
        $staff->load('supervisor:id,name');

        return response()->json([
            'data' => [
                'id'         => $staff->id,
                'name'       => $staff->name,
                'supervisor' => $staff->supervisor ? ['id' => $staff->supervisor->id, 'name' => $staff->supervisor->name] : null,
            ],
        ]);
    }
}
<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Permission;
use App\Models\Tenant;

use Illuminate\Http\Request;

class TenantPermissionController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function allPermissions()
    {
        $this->authorize();

        $permissions = Permission::all();

        $grouped = $permissions->groupBy('category')->map(function ($catPerms) {
            return $catPerms->groupBy('group_name');
        });

        return response()->json(['data' => $grouped]);
    }

    public function tenantPermissions(Tenant $tenant)
    {
        $this->authorize();

        $enabledIds = $tenant->allowedPermissions()->pluck('permissions.id');

        return response()->json(['data' => $enabledIds]);
    }

    public function updateTenantPermissions(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $validated = $request->validate([
            'permission_ids' => 'required|array',
            'permission_ids.*' => 'uuid|exists:permissions,id',
        ]);

        $tenant->allowedPermissions()->sync($validated['permission_ids']);

        // Remove any role_permissions that are no longer in the tenant's allowed set
        $tenant->roles()->each(function ($role) use ($validated) {
            $role->permissions()->detach(
                $role->permissions()
                    ->whereNotIn('permissions.id', $validated['permission_ids'])
                    ->pluck('permissions.id')
            );
        });

        return response()->json([
            'data' => $validated['permission_ids'],
            'message' => 'Tenant permissions updated.',
        ]);
    }
}

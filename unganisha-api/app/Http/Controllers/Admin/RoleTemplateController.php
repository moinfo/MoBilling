<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Permission;
use App\Models\Role;
use Illuminate\Http\Request;

class RoleTemplateController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    /**
     * List the three global role types with permission counts.
     */
    public function index()
    {
        $this->authorize();

        $allPermCount = Permission::count();

        $adminRoles = Role::where('name', 'admin')->where('is_system', true)->with('permissions')->get();
        $userRoles = Role::where('name', 'user')->where('is_system', true)->with('permissions')->get();

        return response()->json([
            'data' => [
                [
                    'type' => 'super_admin',
                    'label' => 'Super Admin',
                    'description' => 'Full access — bypasses all permission checks',
                    'permissions_count' => $allPermCount,
                    'total_permissions' => $allPermCount,
                    'tenants_count' => null,
                    'editable' => false,
                ],
                [
                    'type' => 'admin',
                    'label' => 'Tenant Admin',
                    'description' => 'Default administrator role for each tenant',
                    'permissions_count' => $this->intersectionCount($adminRoles),
                    'total_permissions' => $allPermCount,
                    'tenants_count' => $adminRoles->count(),
                    'editable' => true,
                ],
                [
                    'type' => 'user',
                    'label' => 'Tenant User',
                    'description' => 'Default user role for each tenant',
                    'permissions_count' => $this->intersectionCount($userRoles),
                    'total_permissions' => $allPermCount,
                    'tenants_count' => $userRoles->count(),
                    'editable' => true,
                ],
            ],
        ]);
    }

    /**
     * Show permissions for a role type.
     * Returns all permissions grouped + which IDs are enabled (intersection across all tenants).
     */
    public function show(string $type)
    {
        $this->authorize();

        if (!in_array($type, ['super_admin', 'admin', 'user'])) {
            return response()->json(['message' => 'Invalid role type'], 404);
        }

        $allPermissions = Permission::all();
        $grouped = $allPermissions->groupBy('category')->map(fn($catPerms) => $catPerms->groupBy('group_name'));

        if ($type === 'super_admin') {
            $enabledIds = $allPermissions->pluck('id');
        } else {
            $enabledIds = $this->computeIntersection($type);
        }

        return response()->json([
            'data' => [
                'type' => $type,
                'grouped_permissions' => $grouped,
                'enabled_ids' => $enabledIds,
            ],
        ]);
    }

    /**
     * Update permissions for a role type across ALL tenants.
     */
    public function update(Request $request, string $type)
    {
        $this->authorize();

        if (!in_array($type, ['admin', 'user'])) {
            return response()->json(['message' => 'Cannot edit this role type'], 422);
        }

        $validated = $request->validate([
            'permission_ids' => 'present|array',
            'permission_ids.*' => 'uuid|exists:permissions,id',
        ]);

        $permissionIds = $validated['permission_ids'];

        $roles = Role::where('name', $type)
            ->where('is_system', true)
            ->get();

        $updated = 0;
        foreach ($roles as $role) {
            // Only assign permissions the tenant is allowed to have
            $allowedIds = $role->tenant->allowedPermissions()->pluck('permissions.id')->toArray();
            $applicableIds = array_intersect($permissionIds, $allowedIds);
            $role->permissions()->sync($applicableIds);
            $updated++;
        }

        return response()->json([
            'message' => ucfirst($type) . " role updated across {$updated} tenants.",
            'tenants_updated' => $updated,
        ]);
    }

    /**
     * Compute the intersection of permission IDs across all system roles of a given type.
     */
    private function computeIntersection(string $type): \Illuminate\Support\Collection
    {
        $roles = Role::where('name', $type)
            ->where('is_system', true)
            ->with('permissions')
            ->get();

        if ($roles->isEmpty()) {
            return collect();
        }

        $intersection = $roles->first()->permissions->pluck('id');

        foreach ($roles->skip(1) as $role) {
            $intersection = $intersection->intersect($role->permissions->pluck('id'));
        }

        return $intersection->values();
    }

    private function intersectionCount($roles): int
    {
        if ($roles->isEmpty()) {
            return 0;
        }

        $intersection = $roles->first()->permissions->pluck('id');

        foreach ($roles->skip(1) as $role) {
            $intersection = $intersection->intersect($role->permissions->pluck('id'));
        }

        return $intersection->count();
    }
}

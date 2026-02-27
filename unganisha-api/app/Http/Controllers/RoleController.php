<?php

namespace App\Http\Controllers;

use App\Models\Permission;
use App\Models\Role;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class RoleController extends Controller
{
    use AuthorizesPermissions;

    public function index()
    {
        $this->authorizePermission('settings.users');

        $roles = Role::where('tenant_id', auth()->user()->tenant_id)
            ->withCount('users')
            ->with('permissions:id,name')
            ->orderBy('is_system', 'desc')
            ->orderBy('name')
            ->get();

        return response()->json(['data' => $roles]);
    }

    public function store(Request $request)
    {
        $this->authorizePermission('settings.users');

        $tenantId = auth()->user()->tenant_id;

        $validated = $request->validate([
            'name' => [
                'required', 'string', 'max:50', 'regex:/^[a-z0-9_]+$/',
                Rule::unique('roles')->where('tenant_id', $tenantId),
            ],
            'label' => 'required|string|max:100',
            'permissions' => 'required|array|min:1',
            'permissions.*' => 'uuid|exists:permissions,id',
        ]);

        // Verify permissions are within tenant's allowed set
        $allowedPermIds = auth()->user()->tenant->allowedPermissions()->pluck('permissions.id')->toArray();
        $invalidPerms = array_diff($validated['permissions'], $allowedPermIds);
        if (!empty($invalidPerms)) {
            return response()->json(['message' => 'Some permissions are not available for your organization.'], 422);
        }

        $role = Role::create([
            'tenant_id' => $tenantId,
            'name' => $validated['name'],
            'label' => $validated['label'],
            'is_system' => false,
        ]);

        $role->permissions()->sync($validated['permissions']);

        return response()->json([
            'data' => $role->load('permissions:id,name')->loadCount('users'),
        ], 201);
    }

    public function update(Request $request, Role $role)
    {
        $this->authorizePermission('settings.users');

        if ($role->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $validated = $request->validate([
            'label' => 'required|string|max:100',
            'permissions' => 'required|array|min:1',
            'permissions.*' => 'uuid|exists:permissions,id',
        ]);

        // Verify permissions are within tenant's allowed set
        $allowedPermIds = auth()->user()->tenant->allowedPermissions()->pluck('permissions.id')->toArray();
        $invalidPerms = array_diff($validated['permissions'], $allowedPermIds);
        if (!empty($invalidPerms)) {
            return response()->json(['message' => 'Some permissions are not available for your organization.'], 422);
        }

        $role->update(['label' => $validated['label']]);
        $role->permissions()->sync($validated['permissions']);

        return response()->json([
            'data' => $role->fresh()->load('permissions:id,name')->loadCount('users'),
        ]);
    }

    public function destroy(Role $role)
    {
        $this->authorizePermission('settings.users');

        if ($role->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        if ($role->is_system) {
            return response()->json(['message' => 'System roles cannot be deleted.'], 422);
        }

        if ($role->users()->count() > 0) {
            return response()->json(['message' => 'Cannot delete a role that has users assigned. Reassign users first.'], 422);
        }

        $role->delete();

        return response()->json(['message' => 'Role deleted successfully.']);
    }

    public function availablePermissions()
    {
        $user = auth()->user();

        if ($user->isSuperAdmin()) {
            $permissions = Permission::all();
        } else {
            $permissions = $user->tenant->allowedPermissions;
        }

        // Group by category then by group_name
        $grouped = $permissions->groupBy('category')->map(function ($catPerms) {
            return $catPerms->groupBy('group_name');
        });

        return response()->json(['data' => $grouped]);
    }
}

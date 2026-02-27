<?php

namespace App\Http\Controllers;

use App\Http\Resources\UserResource;
use App\Models\Role;
use App\Models\User;
use App\Traits\AuthorizesPermissions;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class UserController extends Controller
{
    use AuthorizesPermissions;

    public function index(Request $request)
    {
        $query = User::where('tenant_id', auth()->user()->tenant_id);

        if ($request->has('search')) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->where('name', 'LIKE', "%{$search}%")
                  ->orWhere('email', 'LIKE', "%{$search}%");
            });
        }

        return UserResource::collection(
            $query->with('role')->orderBy('name')->paginate($request->per_page ?? 20)
        );
    }

    public function store(Request $request)
    {
        $this->authorizePermission('settings.users');

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255|unique:users,email',
            'password' => 'required|string|min:8',
            'phone' => 'nullable|string|max:20',
            'role_id' => ['required', 'uuid', Rule::exists('roles', 'id')->where('tenant_id', auth()->user()->tenant_id)],
        ]);

        $validated['tenant_id'] = auth()->user()->tenant_id;

        // Set the legacy role column based on the new role
        $role = Role::find($validated['role_id']);
        $validated['role'] = $role->name === 'admin' ? 'admin' : 'user';

        $user = User::create($validated);

        return new UserResource($user->load('role'));
    }

    public function update(Request $request, User $user)
    {
        $this->authorizePermission('settings.users');

        if ($user->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => ['required', 'email', 'max:255', Rule::unique('users')->ignore($user->id)],
            'password' => 'nullable|string|min:8',
            'phone' => 'nullable|string|max:20',
            'role_id' => ['required', 'uuid', Rule::exists('roles', 'id')->where('tenant_id', auth()->user()->tenant_id)],
        ]);

        if (empty($validated['password'])) {
            unset($validated['password']);
        }

        // Set the legacy role column based on the new role
        $role = Role::find($validated['role_id']);
        $validated['role'] = $role->name === 'admin' ? 'admin' : 'user';

        $user->update($validated);

        return new UserResource($user->load('role'));
    }

    public function toggleActive(User $user)
    {
        $this->authorizePermission('settings.users');

        if ($user->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        // Prevent self-deactivation
        if ($user->id === auth()->id()) {
            return response()->json(['message' => 'You cannot deactivate yourself'], 422);
        }

        $user->update(['is_active' => !$user->is_active]);

        return new UserResource($user->load('role'));
    }
}

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

    /**
     * Just id + name, for populating an "assign to" picker — deliberately
     * not gated by settings.users (that's team *management*: create, edit
     * roles, deactivate accounts). Any authenticated staff member needs to
     * see their own teammates' names to assign a ticket, a WhatsApp lead, a
     * field-marketing session, etc.; requiring settings.users for that shut
     * out every non-admin role tenant-wide (confirmed on ARG SPARKLES: 18 of
     * 20 users, everyone but admin/accountant, got a silent empty list).
     */
    public function assignable(Request $request)
    {
        return response()->json([
            'data' => User::where('tenant_id', auth()->user()->tenant_id)
                ->where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'name']),
        ]);
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

    public function impersonate(User $user)
    {
        $this->authorizePermission('settings.users');

        if ($user->tenant_id !== auth()->user()->tenant_id) {
            return response()->json(['message' => 'Not found'], 404);
        }

        if (!$user->is_active) {
            return response()->json(['message' => 'Cannot impersonate an inactive user'], 422);
        }

        if ($user->id === auth()->id()) {
            return response()->json(['message' => 'You cannot impersonate yourself'], 422);
        }

        $token = $user->createToken('impersonation')->plainTextToken;

        try {
            $actor = auth()->user();
            $others = User::withPermission($actor->tenant_id, 'settings.users')
                ->reject(fn ($u) => $u->id === $actor->id);
            if ($others->isNotEmpty()) {
                \Illuminate\Support\Facades\Notification::send(
                    $others,
                    new \App\Notifications\ImpersonationUsedNotification($actor, $user),
                );
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Impersonation-used notification failed', ['error' => $e->getMessage()]);
        }

        return response()->json([
            'user'                => new UserResource($user->load('role')),
            'token'               => $token,
            'subscription_status' => null,
            'days_remaining'      => null,
        ]);
    }
}

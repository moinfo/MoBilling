<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\Role;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\AdminPasswordResetNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class AdminUserController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function index(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $query = User::where('tenant_id', $tenant->id);

        if ($search = $request->input('search')) {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('email', 'like', "%{$search}%");
            });
        }

        return UserResource::collection(
            $query->with('role')->orderBy('name')->paginate($request->input('per_page', 20))
        );
    }

    public function store(Request $request, Tenant $tenant)
    {
        $this->authorize();

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255|unique:users,email',
            'password' => 'required|string|min:8',
            'phone' => 'nullable|string|max:20',
            'role_id' => ['required', 'uuid', Rule::exists('roles', 'id')->where('tenant_id', $tenant->id)],
        ]);

        $validated['tenant_id'] = $tenant->id;

        // Set legacy role column based on the new role
        $role = Role::find($validated['role_id']);
        $validated['role'] = $role->name === 'admin' ? 'admin' : 'user';

        $user = User::create($validated);

        return new UserResource($user->load('role'));
    }

    public function update(Request $request, Tenant $tenant, User $user)
    {
        $this->authorize();

        if ($user->tenant_id !== $tenant->id) {
            abort(404);
        }

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => ['required', 'email', 'max:255', Rule::unique('users')->ignore($user->id)],
            'password' => 'nullable|string|min:8',
            'phone' => 'nullable|string|max:20',
            'role_id' => ['required', 'uuid', Rule::exists('roles', 'id')->where('tenant_id', $tenant->id)],
        ]);

        if (empty($validated['password'])) {
            unset($validated['password']);
        }

        // Set legacy role column based on the new role
        $role = Role::find($validated['role_id']);
        $validated['role'] = $role->name === 'admin' ? 'admin' : 'user';

        $user->update($validated);

        return new UserResource($user->load('role'));
    }

    public function toggleActive(Tenant $tenant, User $user)
    {
        $this->authorize();

        if ($user->tenant_id !== $tenant->id) {
            abort(404);
        }

        $user->update(['is_active' => !$user->is_active]);

        return new UserResource($user);
    }

    /**
     * Superadmin support action: generate a fresh password for this user.
     * Returned in the response (not just emailed) so the admin can copy it
     * and send it manually — e.g. over WhatsApp — when email delivery is
     * unreliable (self-hosted SMTP landing in spam, no email on file, etc).
     * Email is still attempted best-effort when the user has one; a failure
     * there never blocks the reset itself, since the password is already
     * in hand either way.
     */
    public function resetPassword(Tenant $tenant, User $user)
    {
        $this->authorize();

        if ($user->tenant_id !== $tenant->id) {
            abort(404);
        }

        $newPassword = Str::password(14);
        $user->forceFill(['password' => Hash::make($newPassword)])->save();

        $emailSent = false;
        if ($user->email) {
            try {
                $user->notify(new AdminPasswordResetNotification($tenant, $newPassword));
                $emailSent = true;
            } catch (\Throwable $e) {
                report($e);
            }
        }

        return response()->json([
            'message' => $emailSent ? "New password sent to {$user->email}." : 'New password generated.',
            'password' => $newPassword,
            'email_sent' => $emailSent,
        ]);
    }
}

<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class SettingsController extends Controller
{
    public function updateCompany(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Only admins can update company settings.'], 403);
        }

        $validated = $request->validate([
            'name'     => 'required|string|max:255',
            'email'    => 'required|email|max:255',
            'phone'    => 'nullable|string|max:50',
            'address'  => 'nullable|string|max:1000',
            'tax_id'   => 'nullable|string|max:100',
            'currency' => 'required|string|max:10',
        ]);

        $tenant = $request->user()->tenant;
        $tenant->update($validated);

        return response()->json(['tenant' => $tenant->fresh()]);
    }

    public function updateProfile(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'name'             => 'required|string|max:255',
            'email'            => 'required|email|max:255|unique:users,email,' . $user->id,
            'phone'            => 'nullable|string|max:50',
            'current_password' => 'nullable|required_with:password|string',
            'password'         => 'nullable|min:8|confirmed',
        ]);

        if (!empty($validated['password'])) {
            if (!Hash::check($validated['current_password'], $user->password)) {
                throw ValidationException::withMessages([
                    'current_password' => ['The current password is incorrect.'],
                ]);
            }
        }

        $user->update([
            'name'  => $validated['name'],
            'email' => $validated['email'],
            'phone' => $validated['phone'] ?? $user->phone,
            ...(!empty($validated['password']) ? ['password' => $validated['password']] : []),
        ]);

        return response()->json(['user' => $user->fresh()->load('tenant')]);
    }
}

<?php

namespace App\Traits;

trait AuthorizesPermissions
{
    protected function authorizePermission(string ...$permissions): void
    {
        $user = auth()->user();

        if ($user->isSuperAdmin()) {
            return;
        }

        if (!$user->hasAnyPermission($permissions)) {
            abort(403, 'You do not have permission to perform this action.');
        }
    }
}

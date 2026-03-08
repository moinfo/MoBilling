<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Fix roles that have menu.* permissions but lack the corresponding .read
 * data permissions. Without the read permission the API returns 403 even
 * though the user can see the menu item.
 */
return new class extends Migration
{
    /**
     * Map of menu permission => required read permission(s).
     */
    private array $menuToRead = [
        'menu.clients'              => ['clients.read'],
        'menu.products'             => ['products.read'],
        'menu.quotations'           => ['documents.read'],
        'menu.proformas'            => ['documents.read'],
        'menu.invoices'             => ['documents.read'],
        'menu.payments_in'          => ['payments_in.read'],
        'menu.client_subscriptions' => ['client_subscriptions.read'],
        'menu.next_bills'           => ['client_subscriptions.read'],
        'menu.statutories'          => ['statutories.read'],
        'menu.statutory_bills'      => ['bills.read'],
        'menu.bill_categories'      => ['bills.read'],
        'menu.payments_out'         => ['payments_out.read'],
        'menu.expense_categories'   => ['expense_categories.read'],
        'menu.expenses'             => ['expenses.read'],
    ];

    public function up(): void
    {
        // Build a lookup of permission name => id
        $permissions = DB::table('permissions')
            ->pluck('id', 'name')
            ->toArray();

        // Get all roles
        $roles = DB::table('roles')->get();

        foreach ($roles as $role) {
            $rolePermIds = DB::table('role_permissions')
                ->where('role_id', $role->id)
                ->pluck('permission_id')
                ->toArray();

            // Reverse lookup: permission_id => name
            $idToName = array_flip($permissions);
            $rolePermNames = array_map(fn ($id) => $idToName[$id] ?? null, $rolePermIds);

            $toAttach = [];

            foreach ($this->menuToRead as $menuPerm => $readPerms) {
                // If role has this menu permission...
                if (in_array($menuPerm, $rolePermNames)) {
                    foreach ($readPerms as $readPerm) {
                        // ...but lacks the read permission
                        if (!in_array($readPerm, $rolePermNames) && isset($permissions[$readPerm])) {
                            $readPermId = $permissions[$readPerm];
                            if (!in_array($readPermId, $toAttach)) {
                                $toAttach[] = $readPermId;
                            }
                        }
                    }
                }
            }

            if (!empty($toAttach)) {
                $rows = array_map(fn ($permId) => [
                    'role_id' => $role->id,
                    'permission_id' => $permId,
                ], $toAttach);

                DB::table('role_permissions')->insert($rows);
            }
        }
    }

    public function down(): void
    {
        // No safe rollback — manually added permissions cannot be distinguished
    }
};

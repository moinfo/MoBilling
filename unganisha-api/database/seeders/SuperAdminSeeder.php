<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

class SuperAdminSeeder extends Seeder
{
    public function run(): void
    {
        User::updateOrCreate(
            ['email' => 'admin@mobilling.com'],
            [
                'name' => 'Super Admin',
                'password' => env('SUPER_ADMIN_PASSWORD', 'password'),
                'role' => 'super_admin',
                'tenant_id' => null,
                'is_active' => true,
            ]
        );
    }
}

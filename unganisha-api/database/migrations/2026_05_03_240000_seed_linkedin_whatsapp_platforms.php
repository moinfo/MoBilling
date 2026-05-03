<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        $newPlatforms = [
            ['name' => 'linkedin',          'label' => 'LinkedIn',          'color' => 'blue',  'icon' => 'brand-linkedin',  'sort_order' => 6],
            ['name' => 'whatsapp_channel',  'label' => 'WhatsApp Channel',  'color' => 'green', 'icon' => 'brand-whatsapp',  'sort_order' => 7],
            ['name' => 'whatsapp_status',   'label' => 'WhatsApp Status',   'color' => 'teal',  'icon' => 'brand-whatsapp',  'sort_order' => 8],
        ];

        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            foreach ($newPlatforms as $p) {
                // Only insert if this platform doesn't already exist for this tenant
                $exists = DB::table('social_platforms')
                    ->where('tenant_id', $tenantId)
                    ->where('name', $p['name'])
                    ->exists();

                if (!$exists) {
                    DB::table('social_platforms')->insert([
                        'id'          => (string) Str::uuid(),
                        'tenant_id'   => $tenantId,
                        'profile_url' => null,
                        'is_active'   => true,
                        'created_at'  => now(),
                        'updated_at'  => now(),
                        ...$p,
                    ]);
                }
            }
        }
    }

    public function down(): void
    {
        DB::table('social_platforms')
            ->whereIn('name', ['linkedin', 'whatsapp_channel', 'whatsapp_status'])
            ->delete();
    }
};

<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\SmsPurchase;
use App\Models\Tenant;
use App\Models\User;
use App\Services\ResellerService;
use Illuminate\Support\Facades\Log;

class DashboardController extends Controller
{
    private function authorize(): void
    {
        if (!auth()->user()->isSuperAdmin()) {
            abort(403, 'Unauthorized');
        }
    }

    public function summary()
    {
        $this->authorize();

        $totalTenants = Tenant::count();
        $activeTenants = Tenant::where('is_active', true)->count();
        $smsEnabledTenants = Tenant::where('sms_enabled', true)->count();
        $totalUsers = User::count();

        // SMS purchase stats
        $completedPurchases = SmsPurchase::withoutGlobalScopes()->where('status', 'completed');
        $totalSmsRevenue = (clone $completedPurchases)->sum('total_amount');
        $totalSmsSold = (clone $completedPurchases)->sum('sms_quantity');
        $pendingPurchases = SmsPurchase::withoutGlobalScopes()->where('status', 'pending')->count();

        // Master SMS balance
        $masterSmsBalance = null;
        try {
            $reseller = new ResellerService();
            $balanceResult = $reseller->getMasterBalance();
            $masterSmsBalance = $balanceResult['sms_balance'] ?? null;
        } catch (\Throwable $e) {
            Log::warning('Failed to fetch master SMS balance', ['error' => $e->getMessage()]);
        }

        // Recent purchases
        $recentPurchases = SmsPurchase::withoutGlobalScopes()
            ->with(['tenant:id,name', 'user:id,name'])
            ->latest()
            ->limit(5)
            ->get()
            ->map(fn ($p) => [
                'id' => $p->id,
                'tenant_name' => $p->tenant?->name,
                'user_name' => $p->user?->name,
                'sms_quantity' => $p->sms_quantity,
                'total_amount' => $p->total_amount,
                'status' => $p->status,
                'created_at' => $p->created_at?->format('Y-m-d H:i'),
            ]);

        return response()->json([
            'total_tenants' => $totalTenants,
            'active_tenants' => $activeTenants,
            'sms_enabled_tenants' => $smsEnabledTenants,
            'total_users' => $totalUsers,
            'master_sms_balance' => $masterSmsBalance,
            'total_sms_revenue' => round($totalSmsRevenue, 2),
            'total_sms_sold' => (int) $totalSmsSold,
            'pending_purchases' => $pendingPurchases,
            'recent_purchases' => $recentPurchases,
        ]);
    }
}

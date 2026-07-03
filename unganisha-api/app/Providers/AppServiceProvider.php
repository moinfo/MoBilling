<?php

namespace App\Providers;

use App\Models\ClientSubscription;
use App\Observers\ClientSubscriptionObserver;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     *
     * NOTE: LogNotification and LogNotificationFailure are registered
     * automatically via Laravel's listener auto-discovery (they live in
     * app/Listeners with typed handle() methods). Do NOT also register them
     * manually here — that double-binds the listeners and writes every
     * communication_log row twice.
     */
    public function boot(): void
    {
        // Hosting provisioning: subscription status transitions -> WHM jobs
        ClientSubscription::observe(ClientSubscriptionObserver::class);
    }
}

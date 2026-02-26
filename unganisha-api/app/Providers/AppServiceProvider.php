<?php

namespace App\Providers;

use App\Listeners\LogNotification;
use App\Listeners\LogNotificationFailure;
use Illuminate\Notifications\Events\NotificationFailed;
use Illuminate\Notifications\Events\NotificationSent;
use Illuminate\Support\Facades\Event;
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
     */
    public function boot(): void
    {
        Event::listen(NotificationSent::class, LogNotification::class);
        Event::listen(NotificationFailed::class, LogNotificationFailure::class);
    }
}

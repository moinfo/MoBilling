<?php

use Illuminate\Support\Facades\Schedule;

Schedule::command('bills:send-reminders')->dailyAt('08:00');
Schedule::command('subscriptions:expire')->hourly();

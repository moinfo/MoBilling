<?php

use Illuminate\Support\Facades\Schedule;

Schedule::command('bills:generate-recurring')->dailyAt('09:00');
Schedule::command('bills:send-reminders')->dailyAt('08:00');
Schedule::command('invoices:process-recurring')->dailyAt('07:00');
Schedule::command('invoices:process-overdue')->dailyAt('08:30');
Schedule::command('subscriptions:expire')->hourly();

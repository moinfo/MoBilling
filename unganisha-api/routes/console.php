<?php

use Illuminate\Support\Facades\Schedule;

Schedule::command('subscriptions:expire')->dailyAt('06:00')->withoutOverlapping();
Schedule::command('invoices:process-recurring')->dailyAt('07:00')->withoutOverlapping();
Schedule::command('followups:process')->dailyAt('07:30')->withoutOverlapping();
Schedule::command('bills:send-reminders')->dailyAt('08:00')->withoutOverlapping();
Schedule::command('invoices:process-overdue')->dailyAt('08:30')->withoutOverlapping();
Schedule::command('bills:generate-recurring')->dailyAt('09:00')->withoutOverlapping();

<?php

use Illuminate\Support\Facades\Schedule;

Schedule::command('hosting:reconcile')->dailyAt('05:30')->withoutOverlapping();
Schedule::command('domains:sync')->dailyAt('05:45')->withoutOverlapping();
Schedule::command('domains:process-renewals')->dailyAt('06:30')->withoutOverlapping();
Schedule::command('subscriptions:expire')->dailyAt('06:00')->withoutOverlapping();
Schedule::command('invoices:process-recurring')->dailyAt('07:00')->withoutOverlapping();
Schedule::command('followups:process')->dailyAt('07:30')->withoutOverlapping();
Schedule::command('bills:send-reminders')->dailyAt('08:00')->withoutOverlapping();
Schedule::command('invoices:process-overdue')->dailyAt('08:30')->withoutOverlapping();
Schedule::command('bills:generate-recurring')->dailyAt('09:00')->withoutOverlapping();
Schedule::command('subscriptions:suspend-unpaid')->dailyAt('09:30')->withoutOverlapping();
Schedule::command('satisfaction-calls:schedule')->dailyAt('07:15')->withoutOverlapping();
Schedule::command('staff-reports:send-reminders')->dailyAt('09:45')->withoutOverlapping();

// Daily system verification reminders. Africa/Dar_es_Salaam = UTC+3 — set
// explicitly so the schedule isn't sensitive to APP_TIMEZONE drifting.
// First reminder at 20:00 (saa mbili usiku); final at 22:00.
Schedule::command('verifications:send-reminders')->dailyAt('20:00')->timezone('Africa/Dar_es_Salaam')->withoutOverlapping();
Schedule::command('verifications:send-reminders --second-reminder')->dailyAt('22:00')->timezone('Africa/Dar_es_Salaam')->withoutOverlapping();

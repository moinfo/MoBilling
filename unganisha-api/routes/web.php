<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Reached only via nginx's crawler-user-agent rewrite (see the site
// configs) — real browsers never hit this. See LinkPreviewController.
Route::get('/link-preview', [\App\Http\Controllers\LinkPreviewController::class, 'show']);

<?php

namespace App\Http\Controllers;

use App\Models\LicensePlan;

/** Public (no auth) — landing page pricing for self-hosted licenses. Admin CRUD lives in Admin\LicensePlanController. */
class LicensePlanController extends Controller
{
    public function index()
    {
        return response()->json([
            'data' => LicensePlan::where('is_active', true)->orderBy('product')->get(),
        ]);
    }
}

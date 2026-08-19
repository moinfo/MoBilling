<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\File;

/**
 * Serves the self-hosted License Agreement text — shown to a customer
 * during /install (acceptance is required and recorded on the Tenant) and
 * on the public /license-agreement page for prospective buyers.
 *
 * The text lives in a plain file rather than the database because it's
 * legal content revised by editing the file and redeploying, the same way
 * any other static copy on the site is revised — not a runtime-configurable
 * business setting.
 */
class LicenseAgreementController extends Controller
{
    public const VERSION = '1.0';
    public const EFFECTIVE_DATE = '2026-08-18';

    public function show()
    {
        return response()->json([
            'data' => [
                'version' => self::VERSION,
                'effective_date' => self::EFFECTIVE_DATE,
                'content' => File::get(resource_path('legal/license-agreement.txt')),
            ],
        ]);
    }
}

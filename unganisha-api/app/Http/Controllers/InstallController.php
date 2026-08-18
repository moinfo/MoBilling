<?php

namespace App\Http\Controllers;

use App\Services\TenantProvisioningService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rules\Password;

/**
 * Self-hosted first-run setup wizard — reachable with no auth and, for the
 * first two steps, no working database connection at all (that's the point:
 * it's what configures one). Every action re-checks isInstalled() first;
 * once a tenant exists this entire surface locks itself out permanently —
 * there is no way to re-run it against an install that already has data.
 *
 * The license server it calls out to (mobilling.co.tz) is MoBilling's own
 * hosted service — this controller runs on the CUSTOMER's server, not ours;
 * see LicenseValidationController for the other side of that call.
 */
class InstallController extends Controller
{
    private const REQUIRED_EXTENSIONS = [
        'pdo_mysql', 'mbstring', 'openssl', 'tokenizer', 'xml', 'ctype', 'json', 'bcmath', 'fileinfo', 'curl',
    ];

    private const WRITABLE_PATHS = [
        'storage', 'storage/app', 'storage/framework', 'storage/framework/cache',
        'storage/framework/sessions', 'storage/framework/views', 'storage/logs', 'bootstrap/cache',
    ];

    private const LICENSE_SERVER_URL = 'https://mobilling.co.tz/api/license/validate';

    /**
     * True once a tenant exists (or the lock file is present) — the only
     * check that matters for safety. Tolerant of "no DB configured yet",
     * which correctly means "definitely not installed" rather than an error.
     */
    private function isInstalled(): bool
    {
        if (Storage::disk('local')->exists('installed.lock')) {
            return true;
        }

        try {
            if (!Schema::hasTable('tenants')) {
                return false;
            }
            return DB::table('tenants')->exists();
        } catch (\Throwable $e) {
            return false;
        }
    }

    private function blockIfInstalled()
    {
        if ($this->isInstalled()) {
            return response()->json(['message' => 'This MoBilling install is already set up.'], 403);
        }
        return null;
    }

    public function status()
    {
        return response()->json(['installed' => $this->isInstalled()]);
    }

    public function requirements()
    {
        if ($blocked = $this->blockIfInstalled()) {
            return $blocked;
        }

        $extensions = collect(self::REQUIRED_EXTENSIONS)
            ->map(fn ($ext) => ['name' => $ext, 'loaded' => extension_loaded($ext)]);

        $writable = collect(self::WRITABLE_PATHS)
            ->map(fn ($path) => ['path' => $path, 'writable' => is_dir(base_path($path)) && is_writable(base_path($path))]);

        $envPath = base_path('.env');
        $envWritable = file_exists($envPath) ? is_writable($envPath) : is_writable(base_path());

        $phpOk = version_compare(PHP_VERSION, '8.2.0', '>=');
        $allOk = $phpOk
            && $extensions->every(fn ($e) => $e['loaded'])
            && $writable->every(fn ($w) => $w['writable'])
            && $envWritable;

        return response()->json([
            'php_version' => PHP_VERSION,
            'php_ok' => $phpOk,
            'extensions' => $extensions->values(),
            'writable' => $writable->values(),
            'env_writable' => $envWritable,
            'all_ok' => $allOk,
        ]);
    }

    public function testDatabase(Request $request)
    {
        if ($blocked = $this->blockIfInstalled()) {
            return $blocked;
        }

        $data = $request->validate([
            'host' => 'required|string|max:255',
            'port' => 'required|numeric',
            'database' => 'required|string|max:255',
            'username' => 'required|string|max:255',
            'password' => 'nullable|string|max:255',
        ]);

        try {
            new \PDO(
                "mysql:host={$data['host']};port={$data['port']};dbname={$data['database']}",
                $data['username'],
                $data['password'] ?? '',
                [\PDO::ATTR_TIMEOUT => 5],
            );
        } catch (\PDOException $e) {
            return response()->json(['message' => 'Could not connect to that database: ' . $e->getMessage()], 422);
        }

        $this->writeEnv([
            'DB_CONNECTION' => 'mysql',
            'DB_HOST' => $data['host'],
            'DB_PORT' => (string) $data['port'],
            'DB_DATABASE' => $data['database'],
            'DB_USERNAME' => $data['username'],
            'DB_PASSWORD' => $data['password'] ?? '',
        ]);

        if (!env('APP_KEY')) {
            Artisan::call('key:generate', ['--force' => true]);
        }
        Artisan::call('config:clear');

        return response()->json(['message' => 'Database connected.']);
    }

    public function migrate()
    {
        if ($blocked = $this->blockIfInstalled()) {
            return $blocked;
        }

        try {
            Artisan::call('migrate', ['--force' => true]);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Migration failed: ' . $e->getMessage()], 500);
        }

        return response()->json(['message' => 'Database schema created.']);
    }

    /** Dry check only (no side effects on this server) — lets the wizard show a clear error before the customer fills out the whole admin form. */
    public function checkLicense(Request $request)
    {
        if ($blocked = $this->blockIfInstalled()) {
            return $blocked;
        }

        $data = $request->validate(['license_key' => 'required|string|max:100']);

        $result = $this->callLicenseServer($data['license_key'], $request->getHost());
        if (!$result['valid']) {
            return response()->json(['message' => $result['message']], 422);
        }

        return response()->json(['data' => $result]);
    }

    /** Final step — re-validates the license (idempotent: same domain binds again fine) before actually provisioning. */
    public function createTenant(Request $request, TenantProvisioningService $provisioning)
    {
        if ($blocked = $this->blockIfInstalled()) {
            return $blocked;
        }

        $data = $request->validate([
            'license_key' => 'required|string|max:100',
            'company_name' => 'required|string|max:255',
            'company_email' => 'required|email|max:255',
            'currency' => 'nullable|string|max:10',
            'admin_name' => 'required|string|max:255',
            'admin_email' => 'required|email|max:255',
            'admin_password' => ['required', Password::min(8)],
        ]);

        $result = $this->callLicenseServer($data['license_key'], $request->getHost());
        if (!$result['valid']) {
            return response()->json(['message' => $result['message']], 422);
        }

        [$tenant, $adminUser] = $provisioning->provision(
            [
                'name' => $data['company_name'],
                'email' => $data['company_email'],
                'currency' => $data['currency'] ?? 'TZS',
                'is_self_hosted' => true,
            ],
            [
                'name' => $data['admin_name'],
                'email' => $data['admin_email'],
                'password' => $data['admin_password'],
            ],
            $result['product'] ?? 'general',
        );

        Storage::disk('local')->put('installed.lock', json_encode([
            'installed_at' => now()->toIso8601String(),
            'license_key' => $data['license_key'],
            'product' => $result['product'] ?? 'general',
        ], JSON_PRETTY_PRINT));

        return response()->json([
            'message' => 'Installation complete.',
            'data' => ['tenant_id' => $tenant->id, 'admin_email' => $adminUser->email],
        ], 201);
    }

    /** @return array{valid: bool, message: string, product?: string, expires_at?: ?string} */
    private function callLicenseServer(string $licenseKey, string $domain): array
    {
        try {
            $response = Http::timeout(10)->post(self::LICENSE_SERVER_URL, [
                'license_key' => $licenseKey,
                'domain' => $domain,
                'app_version' => config('app.version', 'unknown'),
            ]);
        } catch (\Throwable $e) {
            return ['valid' => false, 'message' => 'Could not reach the MoBilling license server. Check this server\'s internet connection.'];
        }

        $body = $response->json() ?? [];
        if (!$response->successful() || !($body['valid'] ?? false)) {
            return ['valid' => false, 'message' => $body['message'] ?? 'Invalid or expired license key.'];
        }

        return [
            'valid' => true,
            'message' => 'OK',
            'product' => $body['product'] ?? 'general',
            'expires_at' => $body['expires_at'] ?? null,
        ];
    }

    /** Minimal, targeted .env key writer — replaces an existing KEY=value line or appends it. */
    private function writeEnv(array $values): void
    {
        $path = base_path('.env');
        $content = file_exists($path) ? file_get_contents($path) : '';

        foreach ($values as $key => $value) {
            $escaped = str_contains($value, ' ') || $value === '' ? '"' . str_replace('"', '\\"', $value) . '"' : $value;
            $line = "{$key}={$escaped}";

            if (preg_match("/^{$key}=.*$/m", $content)) {
                $content = preg_replace("/^{$key}=.*$/m", $line, $content);
            } else {
                $content .= (str_ends_with($content, "\n") || $content === '' ? '' : "\n") . $line . "\n";
            }
        }

        file_put_contents($path, $content);
    }
}

<?php

namespace App\Services;

use App\Models\DeviceToken;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Sends push notifications through the FCM HTTP v1 API.
 *
 * Auth is a Google service-account JWT exchanged for an OAuth token — done
 * with openssl directly so no new composer dependency is needed. Configure
 * with FCM_CREDENTIALS=/path/to/service-account.json; when unset the service
 * is a silent no-op so every notification channel stays safe to enable.
 */
class FcmService
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private ?array $credentials = null;

    public function __construct()
    {
        $path = config('services.fcm.credentials');
        if ($path && is_readable($path)) {
            $decoded = json_decode((string) file_get_contents($path), true);
            if (is_array($decoded) && isset($decoded['project_id'], $decoded['private_key'], $decoded['client_email'])) {
                $this->credentials = $decoded;
            }
        }
    }

    public function isConfigured(): bool
    {
        return $this->credentials !== null;
    }

    /**
     * Push to every device registered to $notifiable. Dead tokens (device
     * uninstalled the app) are pruned as FCM reports them.
     */
    public function sendTo(object $notifiable, string $title, string $body, array $data = []): void
    {
        if (!$this->isConfigured()) {
            return;
        }

        foreach (DeviceToken::tokensFor($notifiable) as $token) {
            $this->send($token, $title, $body, $data);
        }
    }

    public function send(string $token, string $title, string $body, array $data = []): void
    {
        if (!$this->isConfigured()) {
            return;
        }

        try {
            $response = Http::withToken($this->accessToken())
                ->post(
                    "https://fcm.googleapis.com/v1/projects/{$this->credentials['project_id']}/messages:send",
                    [
                        'message' => [
                            'token' => $token,
                            'notification' => ['title' => $title, 'body' => $body],
                            // FCM data values must all be strings, and the field
                            // itself must serialize as a JSON object even when
                            // empty — a bare PHP [] encodes as JSON [] (a list),
                            // which FCM rejects outright ("Cannot bind a list to
                            // map for field 'data'"). Casting to stdClass forces
                            // {} instead.
                            'data' => (object) array_map('strval', $data),
                        ],
                    ]
                );

            // UNREGISTERED / NOT_FOUND → the app was uninstalled or the token
            // rotated; keeping the row would just waste sends forever.
            if ($response->status() === 404 || $response->json('error.details.0.errorCode') === 'UNREGISTERED') {
                DeviceToken::where('token', $token)->delete();
            } elseif ($response->failed()) {
                Log::warning('FCM send failed', ['status' => $response->status(), 'body' => $response->json()]);
            }
        } catch (\Throwable $e) {
            // A push is never worth failing the surrounding job over.
            Log::warning("FCM send error: {$e->getMessage()}");
        }
    }

    /** Service-account JWT -> OAuth access token, cached until near expiry. */
    private function accessToken(): string
    {
        return Cache::remember('fcm.access_token', now()->addMinutes(50), function () {
            $now = time();
            $claims = [
                'iss' => $this->credentials['client_email'],
                'scope' => self::SCOPE,
                'aud' => self::TOKEN_URL,
                'iat' => $now,
                'exp' => $now + 3600,
            ];

            $segments = [
                $this->base64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'])),
                $this->base64url(json_encode($claims)),
            ];
            $signingInput = implode('.', $segments);

            openssl_sign($signingInput, $signature, $this->credentials['private_key'], OPENSSL_ALGO_SHA256);
            $jwt = $signingInput . '.' . $this->base64url($signature);

            $response = Http::asForm()->post(self::TOKEN_URL, [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ])->throw();

            return $response->json('access_token');
        });
    }

    private function base64url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}

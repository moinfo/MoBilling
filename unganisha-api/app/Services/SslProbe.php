<?php

namespace App\Services;

/**
 * Best-effort TLS certificate check on a domain's website (port 443).
 * Shown to clients ("Valid SSL, expires ...") and on the staff domain view.
 * Failures are normal (no site / no SSL) and recorded as ssl_valid=false.
 */
class SslProbe
{
    /** @return array{ssl_valid:bool, ssl_expires_at:?string, ssl_starts_at:?string, ssl_issuer:?string} */
    public static function probe(string $domain, int $timeout = 6): array
    {
        $none = ['ssl_valid' => false, 'ssl_expires_at' => null, 'ssl_starts_at' => null, 'ssl_issuer' => null];

        try {
            $ctx = stream_context_create(['ssl' => [
                'capture_peer_cert' => true,
                'verify_peer'       => true,
                'verify_peer_name'  => true,
                'SNI_enabled'       => true,
            ]]);
            $sock = @stream_socket_client("ssl://{$domain}:443", $errno, $errstr, $timeout, STREAM_CLIENT_CONNECT, $ctx);
            if (!$sock) {
                return $none;
            }
            $cert = stream_context_get_params($sock)['options']['ssl']['peer_certificate'] ?? null;
            fclose($sock);
            if (!$cert) {
                return $none;
            }
            $parsed = openssl_x509_parse($cert);

            return [
                'ssl_valid'      => isset($parsed['validTo_time_t']) && $parsed['validTo_time_t'] > time(),
                'ssl_expires_at' => isset($parsed['validTo_time_t']) ? date('Y-m-d', $parsed['validTo_time_t']) : null,
                'ssl_starts_at'  => isset($parsed['validFrom_time_t']) ? date('Y-m-d', $parsed['validFrom_time_t']) : null,
                'ssl_issuer'     => $parsed['issuer']['O'] ?? $parsed['issuer']['CN'] ?? null,
            ];
        } catch (\Throwable) {
            return $none;
        }
    }
}

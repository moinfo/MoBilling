<?php

namespace App\Services;

/**
 * Queries the TZNIC (.tz) WHOIS server directly over port 43 — the same data
 * as https://whois.tznic.or.tz, but in-house so staff don't leave MoBilling.
 * The registry runs FRED's whoisd, whose output is block/key-value text.
 */
class TznicWhoisService
{
    private const HOST = 'whois.tznic.or.tz';
    private const PORT = 43;

    /**
     * @return array{
     *   domain:string, found:bool, raw:string,
     *   registrar:?string, registrant:?string, statuses:string[],
     *   admins:string[], nsset:?string, nameservers:string[],
     *   registered:?string, changed:?string, expire:?string
     * }
     */
    public function lookup(string $domain): array
    {
        $domain = $this->normalise($domain);
        $raw = $this->query($domain);

        $found = $raw !== '' && !str_contains($raw, 'no entries found') && str_contains($raw, "\ndomain:");

        $out = [
            'domain' => $domain, 'found' => $found, 'raw' => $raw,
            'registrar' => null, 'registrant' => null, 'statuses' => [],
            'admins' => [], 'nsset' => null, 'nameservers' => [],
            'registered' => null, 'changed' => null, 'expire' => null,
        ];
        if (!$found) {
            return $out;
        }

        // The first block (up to the first blank line) is the domain record;
        // later blocks are contact/nsset details that carry the nserver lines.
        $lines = preg_split('/\r?\n/', $raw);
        $inDomainBlock = false;
        $domainBlockDone = false;

        foreach ($lines as $line) {
            if ($line === '' || $line[0] === '%') {
                if ($inDomainBlock) {
                    $domainBlockDone = true;
                    $inDomainBlock = false;
                }
                continue;
            }
            if (!preg_match('/^([a-z0-9\-]+):\s*(.+?)\s*$/i', $line, $m)) {
                continue;
            }
            [$key, $val] = [strtolower($m[1]), $m[2]];

            if ($key === 'domain' && !$domainBlockDone) {
                $inDomainBlock = true;
            }

            if ($inDomainBlock) {
                match ($key) {
                    'registrar'  => $out['registrar'] = $val,
                    'registrant' => $out['registrant'] = $val,
                    'nsset'      => $out['nsset'] = $val,
                    'status'     => $out['statuses'][] = $val,
                    'admin-c'    => $out['admins'][] = $val,
                    'registered' => $out['registered'] = $val,
                    'changed'    => $out['changed'] = $val,
                    'expire'     => $out['expire'] = $val,
                    default      => null,
                };
            }

            if ($key === 'nserver') {
                // "ns1.google.com" or "ns.example.tz 196.44.x.x"
                $out['nameservers'][] = trim(explode(' ', $val)[0]);
            }
        }

        $out['nameservers'] = array_values(array_unique(array_filter($out['nameservers'])));

        return $out;
    }

    /** Lowercase, strip scheme/path/spaces, keep the bare host. */
    public function normalise(string $domain): string
    {
        $domain = strtolower(trim($domain));
        $domain = preg_replace('#^https?://#', '', $domain);
        $domain = explode('/', $domain)[0];
        return trim($domain, '.');
    }

    private function query(string $domain): string
    {
        $errno = 0;
        $errstr = '';
        $fp = @fsockopen(self::HOST, self::PORT, $errno, $errstr, 8);
        if (!$fp) {
            return '';
        }
        stream_set_timeout($fp, 8);
        fwrite($fp, $domain . "\r\n");
        $out = '';
        while (!feof($fp)) {
            $chunk = fread($fp, 4096);
            if ($chunk === false) {
                break;
            }
            $out .= $chunk;
            $meta = stream_get_meta_data($fp);
            if ($meta['timed_out']) {
                break;
            }
        }
        fclose($fp);
        return $out;
    }
}

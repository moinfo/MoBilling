<?php

namespace App\Services\Registrar;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Domain;
use App\Models\NameComAccount;
use App\Models\User;
use App\Notifications\NameComAccountInvalidNotification;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * Bulk read-only refresh of every Name.com-linked domain through NameComDomainService::refresh(),
 * using each domain's OWN account credentials. Cursor-chunked so no web request runs long
 * (the UI loops chunk by chunk; the nightly command loops until done). Paced well under
 * Name.com's 20 req/s, with an hourly budget per account (limit 3000/h). A rejected token
 * (401/403) marks the account invalid, notifies staff once, and skips the rest of its domains.
 */
class NameComBulkSync
{
    public const CHUNK = 25;
    public const HOURLY_BUDGET = 2500;
    /** Gap between Name.com calls (ms) = max ~10 req/s. Tests set 0. */
    public static int $gapMs = 100;
    private static float $last = 0.0;

    public function __construct(private NameComDomainService $svc) {}

    public static function query(string $tenantId): Builder
    {
        return Domain::withoutGlobalScopes()->where('tenant_id', $tenantId)
            ->whereNotNull('meta->namecom')
            ->whereNotIn('status', ['cancelled', 'transferred_out']);
    }

    /**
     * @return array{processed:int, updated:int, unchanged:int, failed:int, skipped:int, failures: array<int,array{domain:string,reason:string}>, next:?string, total:int}
     */
    public function runChunk(string $tenantId, ?string $after = null, int $limit = self::CHUNK): array
    {
        $limit = max(1, min($limit, self::CHUNK));
        $out = ['processed' => 0, 'updated' => 0, 'unchanged' => 0, 'failed' => 0, 'skipped' => 0, 'failures' => [], 'next' => null, 'total' => self::query($tenantId)->count()];

        $q = self::query($tenantId)->orderBy('id');
        if ($after) $q->where('id', '>', $after);
        $domains = $q->limit($limit)->get();
        $default = NameComAccount::defaultFor($tenantId);

        foreach ($domains as $domain) {
            $out['processed']++;
            $out['next'] = $domain->id;
            $accId = $domain->meta['namecom']['account_id'] ?? null;
            $account = ($accId ? NameComAccount::findFor($tenantId, $accId) : null) ?? $default;

            if (!$account) { $this->fail($out, $domain, 'No Name.com account is connected.'); continue; }
            if ($account->status === 'invalid') {
                $out['skipped']++;
                $this->note($out, $domain, 'Skipped: the token for account "' . $account->displayLabel() . '" was rejected. Update it under Domains > Name.com.');
                continue;
            }
            if (!$this->withinBudget($account)) {
                $out['skipped']++;
                $this->note($out, $domain, 'Skipped: hourly Name.com request budget reached; it will be refreshed on the next run.');
                continue;
            }

            $this->pace();
            try {
                $r = $this->svc->refresh($domain);
                $r['changed'] ? $out['updated']++ : $out['unchanged']++;
            } catch (NameComApiException $e) {
                if (in_array($e->httpStatus, [401, 403], true)) {
                    $this->invalidate($account, $e->getMessage());
                }
                $this->fail($out, $domain, $e->getMessage());
            } catch (RegistrarApiException $e) {
                $this->fail($out, $domain, preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage()));
            } catch (\Throwable $e) {
                Log::warning('Name.com bulk sync error', ['domain' => $domain->name, 'error' => $e->getMessage()]);
                $this->fail($out, $domain, 'Unexpected error.');
            }
        }

        if ($domains->count() < $limit) $out['next'] = null;
        return $out;
    }

    /** Everything for one tenant (nightly command). @return array totals */
    public function runAll(string $tenantId): array
    {
        $tot = ['processed' => 0, 'updated' => 0, 'unchanged' => 0, 'failed' => 0, 'skipped' => 0, 'failures' => []];
        $cursor = null;
        do {
            $c = $this->runChunk($tenantId, $cursor);
            foreach (['processed', 'updated', 'unchanged', 'failed', 'skipped'] as $k) $tot[$k] += $c[$k];
            $tot['failures'] = array_slice(array_merge($tot['failures'], $c['failures']), 0, 50);
            $cursor = $c['next'];
        } while ($cursor);
        return $tot;
    }

    private function fail(array &$out, Domain $d, string $reason): void
    {
        $out['failed']++;
        $this->note($out, $d, $reason);
    }

    private function note(array &$out, Domain $d, string $reason): void
    {
        if (count($out['failures']) < 50) $out['failures'][] = ['domain' => $d->name, 'reason' => $reason];
    }

    private function pace(): void
    {
        if (self::$gapMs > 0) {
            $wait = self::$last + self::$gapMs / 1000 - microtime(true);
            if ($wait > 0) usleep((int) ($wait * 1e6));
        }
        self::$last = microtime(true);
    }

    private function withinBudget(NameComAccount $a): bool
    {
        $key = 'namecom:bulk:' . $a->id . ':' . now()->format('YmdH');
        $n = Cache::add($key, 0, 3700) ? 0 : (int) Cache::get($key, 0);
        if ($n >= self::HOURLY_BUDGET) return false;
        Cache::increment($key);
        return true;
    }

    /** Mark once (it becomes 'invalid' so later domains/runs skip) and tell staff with Name.com settings access. */
    private function invalidate(NameComAccount $a, string $reason): void
    {
        if ($a->status === 'invalid') return;
        $a->update(['status' => 'invalid', 'status_message' => mb_substr($reason, 0, 250), 'last_verified_at' => now()]);
        try {
            $users = User::withoutGlobalScopes()->where('tenant_id', $a->tenant_id)->get()->filter(fn ($u) => $u->hasPermission('domains.settings'));
            foreach ($users as $u) $u->notify(new NameComAccountInvalidNotification($a->displayLabel(), mb_substr($reason, 0, 120)));
        } catch (\Throwable $e) {
            Log::warning('Name.com invalid-account notice failed', ['error' => $e->getMessage()]);
        }
    }
}

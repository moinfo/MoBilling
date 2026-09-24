<?php

namespace App\Http\Controllers;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Models\Domain;
use App\Services\Registrar\NameComDomainService;
use App\Services\Registrar\NameComTransferService;
use Illuminate\Http\Request;

/** Staff transfer-out tools for linked Name.com domains (permission domains.transfer; no invoice guard). */
class DomainTransferController extends Controller
{
    public function __construct(private NameComTransferService $svc) {}

    private function guard(Domain $domain): void
    {
        abort_unless(NameComDomainService::isLinked($domain), 422, 'This domain is not linked to Name.com.');
    }

    private function fail(\Throwable $e)
    {
        if ($e instanceof \DomainException) return response()->json(['message' => $e->getMessage()], 422);
        if ($e instanceof NameComApiException || $e instanceof RegistrarApiException) {
            return response()->json(['message' => preg_replace('/^Registrar \S+ failed: /', '', $e->getMessage())], 422);
        }
        throw $e;
    }

    public function show(Domain $domain)
    {
        $this->guard($domain);
        try {
            return response()->json(['data' => $this->svc->state($domain) + ['client_block' => $this->svc->clientBlock($domain)]]);
        } catch (\Throwable $e) {
            return $this->fail($e);
        }
    }

    public function lock(Request $request, Domain $domain)
    {
        return $this->change($domain, true);
    }

    public function unlock(Request $request, Domain $domain)
    {
        return $this->change($domain, false);
    }

    private function change(Domain $domain, bool $lock)
    {
        $this->guard($domain);
        try {
            $s = $this->svc->setLock($domain, $lock, ['by_user' => auth()->id()], false);
        } catch (\Throwable $e) {
            return $this->fail($e);
        }
        return response()->json(['data' => $s, 'message' => $lock ? 'Domain locked.' : 'Domain unlocked.']);
    }

    public function authCode(Request $request, Domain $domain)
    {
        $this->guard($domain);
        try {
            $code = $this->svc->authCode($domain, ['by_user' => auth()->id()], false);
        } catch (\Throwable $e) {
            return $this->fail($e);
        }
        return response()->json(['auth_code' => $code])->header('Cache-Control', 'no-store');
    }
}

<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Http\Controllers\Controller;
use App\Models\Domain;
use App\Services\Registrar\NameComDomainService;
use App\Services\Registrar\NameComTransferService;
use Illuminate\Http\Request;

/**
 * Client-facing domain lock / transfer code. Wording is deliberately supplier-neutral:
 * no provider names, no internal errors, ever.
 */
class PortalDomainTransferController extends Controller
{
    private const GENERIC = 'We could not complete this right now. If the domain was registered or changed recently it may be under a transfer restriction. Please try again later or contact us.';

    public function __construct(private NameComTransferService $svc) {}

    private function own(Request $request, Domain $domain, bool $adminOnly): void
    {
        $user = $request->user();
        abort_unless($domain->client_id === $user->client_id && NameComDomainService::isLinked($domain), 404);
        if ($adminOnly) abort_unless($user->role === 'admin', 403, 'Only portal administrators can manage the domain lock and transfer code.');
    }

    private function confirmed(Request $request, Domain $domain): ?\Illuminate\Http\JsonResponse
    {
        $typed = strtolower(trim((string) $request->input('confirm_domain')));
        return $typed === strtolower($domain->name) ? null
            : response()->json(['message' => 'Type the domain name exactly to confirm.'], 422);
    }

    private function fail(\Throwable $e)
    {
        if ($e instanceof \DomainException) return response()->json(['message' => $e->getMessage()], 422);
        if ($e instanceof NameComApiException || $e instanceof RegistrarApiException) {
            report($e);
            return response()->json(['message' => self::GENERIC], 422);
        }
        throw $e;
    }

    public function show(Request $request, Domain $domain)
    {
        $this->own($request, $domain, false);
        try {
            $s = $this->svc->state($domain);
        } catch (NameComApiException | RegistrarApiException) {
            return response()->json(['message' => 'Could not read the domain lock status right now - please try again shortly.'], 422);
        }
        $block = $this->svc->clientBlock($domain);
        return response()->json(['data' => $s + [
            'blocked'        => $block !== null,
            'blocked_reason' => $block,
            'is_admin'       => $request->user()->role === 'admin',
        ]]);
    }

    public function lock(Request $request, Domain $domain)
    {
        return $this->change($request, $domain, true);
    }

    public function unlock(Request $request, Domain $domain)
    {
        return $this->change($request, $domain, false);
    }

    private function change(Request $request, Domain $domain, bool $lock)
    {
        $this->own($request, $domain, true);
        if (!$lock && ($r = $this->confirmed($request, $domain))) return $r;
        try {
            $s = $this->svc->setLock($domain, $lock, ['by_portal_user' => $request->user()->id], true);
        } catch (\Throwable $e) {
            return $this->fail($e);
        }
        return response()->json(['data' => $s, 'message' => $lock ? 'Domain lock enabled.' : 'Domain unlocked. It can now be transferred to another provider.']);
    }

    public function authCode(Request $request, Domain $domain)
    {
        $this->own($request, $domain, true);
        if ($r = $this->confirmed($request, $domain)) return $r;
        try {
            $code = $this->svc->authCode($domain, ['by_portal_user' => $request->user()->id], true);
        } catch (\Throwable $e) {
            return $this->fail($e);
        }
        return response()->json(['auth_code' => $code])->header('Cache-Control', 'no-store');
    }
}

<?php

namespace App\Http\Controllers\Portal;

use App\Exceptions\NameComApiException;
use App\Exceptions\RegistrarApiException;
use App\Http\Controllers\Controller;
use App\Models\Domain;
use App\Services\Registrar\NameComDomainService;
use App\Services\Registrar\NameComManagerService as Mgr;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Client-facing "Domain Manager": DNS records, contact details, website / email forwarding and
 * custom nameserver hosts for the client's own linked domain.
 *
 * NEUTRAL BY RULE: no supplier names, account labels or raw upstream errors ever reach these
 * responses - every registrar-side failure is mapped to generic text by Mgr::clientMessage().
 * Reads: any portal user of the owning client. Writes: portal administrators only.
 */
class PortalDomainManagerController extends Controller
{
    private const READ_FAIL = 'We could not load this right now. Please try again shortly.';

    public function __construct(private Mgr $mgr) {}

    private function own(Request $request, Domain $domain, bool $write): array
    {
        $user = $request->user();
        abort_unless($domain->client_id === $user->client_id && NameComDomainService::isLinked($domain), 404);
        if ($write) {
            abort_unless($user->role === 'admin', 403, 'Only portal administrators can change these settings.');
            abort_unless(in_array($domain->status, ['active', 'expired'], true), 422, 'This domain is not active yet.');
        }
        return ['by_portal_user' => $user->id];
    }

    private function read(callable $f): JsonResponse
    {
        try {
            return response()->json(['data' => $f()]);
        } catch (NameComApiException | RegistrarApiException $e) {
            report($e);
            return response()->json(['message' => self::READ_FAIL], 422);
        }
    }

    /** Runs a write; maps every failure to client-safe text. */
    private function write(callable $f, string $okMessage, int $ok = 200): JsonResponse
    {
        try {
            $data = $f();
        } catch (\InvalidArgumentException | \DomainException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        } catch (NameComApiException | RegistrarApiException $e) {
            report($e);
            return response()->json(['message' => Mgr::clientMessage($e)], 422);
        }
        return response()->json(['data' => $data, 'message' => $okMessage], $ok);
    }

    // ── DNS records ──

    public function dns(Request $request, Domain $domain): JsonResponse
    {
        $this->own($request, $domain, false);
        return $this->read(fn () => $this->mgr->dns($domain) + ['is_admin' => $request->user()->role === 'admin']);
    }

    private const RECORD_RULES = ['type' => 'required|string|max:10', 'name' => 'nullable|string|max:253', 'target' => 'required|string|max:2000',
        'ttl_sec' => 'nullable|integer', 'priority' => 'nullable|integer', 'weight' => 'nullable|integer', 'port' => 'nullable|integer',
        'service' => 'nullable|string|max:60', 'protocol' => 'nullable|string|max:10'];

    public function recordStore(Request $request, Domain $domain): JsonResponse
    {
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(self::RECORD_RULES);
        return $this->write(fn () => $this->mgr->addRecord($domain, $in, $actor), 'DNS record added.', 201);
    }

    public function recordUpdate(Request $request, Domain $domain, string $id): JsonResponse
    {
        abort_unless(ctype_digit($id), 404);
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(self::RECORD_RULES);
        return $this->write(fn () => $this->mgr->editRecord($domain, $id, $in, $actor), 'DNS record updated.');
    }

    public function recordDestroy(Request $request, Domain $domain, string $id): JsonResponse
    {
        abort_unless(ctype_digit($id), 404);
        $actor = $this->own($request, $domain, true);
        return $this->write(function () use ($domain, $id, $actor) { $this->mgr->deleteRecord($domain, $id, $actor); return null; }, 'DNS record removed.');
    }

    /** Explicit one-click switch to our DNS servers; the client must confirm (never done silently). */
    public function useDefaultServers(Request $request, Domain $domain): JsonResponse
    {
        $request->validate(['confirm' => 'accepted']);
        $actor = $this->own($request, $domain, true);
        return $this->write(function () use ($domain, $actor) {
            $r = $this->mgr->useDefaultDnsServers($domain, $actor);
            return ['changed' => $r['changed']];
        }, 'Your domain now uses our DNS servers. It can take up to a few hours to take effect everywhere.');
    }

    // ── contacts ──

    public function contacts(Request $request, Domain $domain): JsonResponse
    {
        $this->own($request, $domain, false);
        return $this->read(fn () => $this->mgr->contacts($domain) + ['is_admin' => $request->user()->role === 'admin']);
    }

    public function contactsUpdate(Request $request, Domain $domain): JsonResponse
    {
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(['confirm' => 'accepted', 'contacts' => 'required|array|min:1']);
        $edited = array_intersect_key($in['contacts'], array_flip(Mgr::ROLES));
        $bad = array_diff(array_keys($in['contacts']), Mgr::ROLES);
        if ($bad || !$edited) return response()->json(['message' => 'Unknown contact type.'], 422);
        return $this->write(function () use ($domain, $edited, $actor) {
            $r = $this->mgr->saveContacts($domain, $edited, $actor);
            return ['changed' => $r['changed']];
        }, 'Contact details saved. A verification email may be sent to the registrant email address.');
    }

    // ── forwarding ──

    public function forwarding(Request $request, Domain $domain): JsonResponse
    {
        $this->own($request, $domain, false);
        return $this->read(fn () => [
            'url' => $this->mgr->urlForwards($domain), 'email' => $this->mgr->emailForwards($domain),
            'max' => Mgr::MAX_FORWARDS, 'is_admin' => $request->user()->role === 'admin',
        ]);
    }

    private const URL_RULES = ['host' => 'nullable|string|max:253', 'target' => 'required|string|max:2000', 'type' => 'nullable|string|max:12', 'title' => 'nullable|string|max:200'];

    public function urlStore(Request $request, Domain $domain): JsonResponse
    {
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(self::URL_RULES);
        return $this->write(fn () => $this->mgr->addUrlForward($domain, $in, $actor), 'Website forwarding added. It can take up to 24 hours to take effect.', 201);
    }

    public function urlUpdate(Request $request, Domain $domain, string $id): JsonResponse
    {
        abort_unless(ctype_digit($id), 404);
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(['host' => 'sometimes|nullable|string|max:253', 'target' => 'sometimes|string|max:2000', 'type' => 'sometimes|string|max:12', 'title' => 'sometimes|nullable|string|max:200']);
        return $this->write(fn () => $this->mgr->editUrlForward($domain, $id, $in, $actor), 'Website forwarding updated. It can take up to 24 hours to take effect.');
    }

    public function urlDestroy(Request $request, Domain $domain, string $id): JsonResponse
    {
        abort_unless(ctype_digit($id), 404);
        $actor = $this->own($request, $domain, true);
        return $this->write(function () use ($domain, $id, $actor) { $this->mgr->deleteUrlForward($domain, $id, $actor); return null; }, 'Website forwarding removed.');
    }

    public function emailStore(Request $request, Domain $domain): JsonResponse
    {
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(['box' => 'required|string|max:80', 'to' => 'required|string|max:254']);
        return $this->write(fn () => $this->mgr->addEmailForward($domain, $in, $actor), 'Email forwarding added.', 201);
    }

    public function emailUpdate(Request $request, Domain $domain, string $box): JsonResponse
    {
        abort_unless(preg_match('/^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$/', $box) === 1, 404);
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(['to' => 'required|string|max:254']);
        return $this->write(fn () => $this->mgr->editEmailForward($domain, $box, $in, $actor), 'Email forwarding updated.');
    }

    public function emailDestroy(Request $request, Domain $domain, string $box): JsonResponse
    {
        abort_unless(preg_match('/^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$/', $box) === 1, 404);
        $actor = $this->own($request, $domain, true);
        return $this->write(function () use ($domain, $box, $actor) { $this->mgr->deleteEmailForward($domain, $box, $actor); return null; }, 'Email forwarding removed.');
    }

    // ── custom nameserver hosts ──

    public function hosts(Request $request, Domain $domain): JsonResponse
    {
        $this->own($request, $domain, false);
        return $this->read(fn () => ['hosts' => $this->mgr->hosts($domain), 'max' => Mgr::MAX_HOSTS, 'is_admin' => $request->user()->role === 'admin']);
    }

    public function hostStore(Request $request, Domain $domain): JsonResponse
    {
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(['host' => 'required|string|max:253', 'ips' => 'required|array|min:1|max:10', 'ips.*' => 'required|string|max:45']);
        return $this->write(fn () => $this->mgr->addHost($domain, $in['host'], $in['ips'], $actor), 'Custom nameserver host added.', 201);
    }

    public function hostUpdate(Request $request, Domain $domain, string $host): JsonResponse
    {
        $actor = $this->own($request, $domain, true);
        $in = $request->validate(['ips' => 'required|array|min:1|max:10', 'ips.*' => 'required|string|max:45']);
        return $this->write(fn () => $this->mgr->editHost($domain, $host, $in['ips'], $actor), 'Custom nameserver host updated.');
    }
}

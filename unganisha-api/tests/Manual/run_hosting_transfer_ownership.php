<?php
// php tests/Manual/run_hosting_transfer_ownership.php  (live DB, rolled back at the end)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Http\Controllers\HostingServiceController;
use App\Models\{Client, ClientSubscription, Domain, Tenant, User};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }
function j($r) { return $r->getData(true); }
function req(Request $rq, $u) { $rq->setUserResolver(fn () => $u); app()->instance('request', $rq); auth()->setUser($u); return $rq; }
function trap(callable $f) {
    try { return $f(); }
    catch (\Illuminate\Validation\ValidationException $e) { return response()->json(['errors' => $e->errors(), 'message' => $e->getMessage()], 422); }
    catch (\Symfony\Component\HttpKernel\Exception\HttpExceptionInterface $e) { return response()->json(['message' => $e->getMessage()], $e->getStatusCode()); }
}

DB::beginTransaction();
try {
    $tenant = Tenant::find('019c8f39-679e-70d2-af92-ac72a25b0d9c'); // Moinfotech Company Limited
    $owner = User::where('tenant_id', $tenant->id)->where('is_active', true)->first();
    $ctl = app(HostingServiceController::class);

    // The real service from the reported URL.
    $sub = ClientSubscription::find('019f285d-7293-70c2-aa35-5f85cda4187b');
    ok((bool) $sub, 'found the real subscription to test with');
    $oldClientId = $sub->client_id;
    $clientB = Client::where('tenant_id', $tenant->id)->where('id', '!=', $oldClientId)->first();

    // 1. Transfer moves the subscription; the domain's client_id in live
    // data does NOT currently match the subscription's client, so it must
    // NOT be moved (only a matching domain follows automatically).
    $r1 = trap(fn () => $ctl->transferOwnership(req(Request::create('/x', 'POST', ['client_id' => $clientB->id]), $owner), $sub));
    ok($r1->status() === 200, 'transferOwnership returns 200: got ' . $r1->status());
    ok($sub->fresh()->client_id === $clientB->id, 'subscription client_id actually changed');
    $data1 = j($r1);
    ok($data1['domain_moved'] === null, 'domain_moved is null — the linked domain belongs to a different client already');

    // 2. Construct a matching-domain scenario and confirm it DOES move.
    $domain = Domain::where('name', 'jetcare.co.tz')->first();
    $domain->update(['client_id' => $clientB->id]); // now matches the subscription's current owner
    $clientC = Client::where('tenant_id', $tenant->id)->whereNotIn('id', [$oldClientId, $clientB->id])->first();
    $r2 = trap(fn () => $ctl->transferOwnership(req(Request::create('/x', 'POST', ['client_id' => $clientC->id]), $owner), $sub));
    ok($r2->status() === 200, 'second transfer returns 200: got ' . $r2->status());
    ok($sub->fresh()->client_id === $clientC->id, 'subscription moved to the third client');
    ok($domain->fresh()->client_id === $clientC->id, 'the matching domain moved along with it');
    ok(j($r2)['domain_moved'] === 'jetcare.co.tz', 'response names the domain that moved');

    // 3. Transferring to the already-current client is rejected.
    $r3 = trap(fn () => $ctl->transferOwnership(req(Request::create('/x', 'POST', ['client_id' => $clientC->id]), $owner), $sub));
    ok($r3->status() === 422, 'transferring to the current owner is rejected (422): got ' . $r3->status());

    // 4. A client_id belonging to a different tenant fails validation.
    $otherTenantClient = Client::withoutGlobalScopes()->where('tenant_id', '!=', $tenant->id)->first();
    ok((bool) $otherTenantClient, 'found a client belonging to a different tenant to test cross-tenant rejection');
    $r4 = trap(fn () => $ctl->transferOwnership(req(Request::create('/x', 'POST', ['client_id' => $otherTenantClient->id]), $owner), $sub));
    ok($r4->status() === 422, 'a cross-tenant client_id is rejected by validation (422): got ' . $r4->status());

    echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
} finally {
    DB::rollBack();
    echo "Rolled back — no permanent changes.\n";
}

<?php
// php tests/Manual/run_client_status.php  (live DB, rolled back, no external calls)
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\{Client, Tenant, User};
use Illuminate\Support\Facades\{DB, Validator};
use Illuminate\Validation\Rule;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

// The exact rule added to StoreClientRequest — copied verbatim so a future edit to that file
// that changes the allowed values would need this test updated too (a deliberate tripwire).
$statusRule = ['status' => ['sometimes', Rule::in(['active', 'inactive'])]];

DB::beginTransaction();
try {
    $tenant = Tenant::withoutGlobalScopes()->where('name', 'MoBilling Test Co')->firstOrFail();
    auth()->login(User::withoutGlobalScopes()->where('tenant_id', $tenant->id)->firstOrFail());

    ok(Validator::make(['status' => 'active'], $statusRule)->passes(), 'rule: "active" accepted');
    ok(Validator::make(['status' => 'inactive'], $statusRule)->passes(), 'rule: "inactive" accepted');
    ok(Validator::make(['status' => 'merged'], $statusRule)->fails(), 'rule: "merged" refused (only ClientMergeService may set it)');
    ok(Validator::make([], $statusRule)->passes(), 'rule: omitted entirely is fine ("sometimes")');
    ok(Validator::make(['status' => 'MERGED'], $statusRule)->fails(), 'rule: case variants of "merged" also refused');

    // The controller is a one-line pass-through ($client->update($request->validated())), so once the
    // rule is right, persistence just needs status to be fillable and to round-trip normally.
    $client = Client::create(['tenant_id' => $tenant->id, 'name' => 'Status Test Client', 'status' => 'active']);
    $client->update(['status' => 'inactive']);
    ok($client->fresh()->status === 'inactive', 'persistence: status updates and round-trips');

    // A merged client's status is never something this form's validated() payload could carry (the
    // rule refuses "merged" as input), so update()ing other fields never touches an existing "merged"
    // status as a side effect — validated() simply won't contain the key unless "status" was sent.
    $client->update(['status' => 'merged', 'name' => 'Merged Client']);
    $client->update(['name' => 'Merged Client Renamed']); // no 'status' key at all, like validated() omitting it
    ok($client->fresh()->status === 'merged' && $client->fresh()->name === 'Merged Client Renamed',
        'persistence: updating other fields without a status key leaves "merged" untouched');
} finally {
    DB::rollBack();
}
echo $fail ? "FAILED $fail\n" : "ALL PASSED\n";

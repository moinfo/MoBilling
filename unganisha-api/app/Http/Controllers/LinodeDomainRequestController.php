<?php

namespace App\Http\Controllers;

use App\Models\Client;
use App\Models\LinodeAccount;
use App\Models\LinodeAuditLog;
use App\Models\LinodeDomainRequest;
use App\Models\LinodeResource;
use App\Models\Tenant;
use App\Notifications\LinodeDomainRequestNotification;
use App\Services\Linode\LinodeDomainProvisioner;
use App\Services\Linode\LinodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Staff side of client domain requests. Routes sit in the linode.manage group; every model is tenant-scoped. */
class LinodeDomainRequestController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $status = in_array($request->query('status'), ['pending', 'approved', 'rejected'], true) ? $request->query('status') : 'pending';
        $rows = LinodeDomainRequest::where('status', $status)->orderByDesc('created_at')->limit(200)->get();
        $clients = Client::whereIn('id', $rows->pluck('client_id'))->pluck('name', 'id');
        $servers = LinodeResource::whereIn('id', $rows->pluck('linode_resource_id'))->get()->keyBy('id');

        return response()->json(['data' => $rows->map(fn ($r) => [
            'id' => $r->id, 'domain' => $r->domain, 'status' => $r->status, 'note' => $r->note,
            'client_id' => $r->client_id, 'client_name' => $clients[$r->client_id] ?? null,
            'server_id' => $r->linode_resource_id, 'server_label' => $servers[$r->linode_resource_id]?->label,
            'server_ip' => $servers[$r->linode_resource_id]?->ipv4[0] ?? null,
            'decided_at' => $r->decided_at, 'created_at' => $r->created_at,
        ])->values()]);
    }

    public function approve(Request $request, LinodeDomainRequest $domainRequest): JsonResponse
    {
        return DB::transaction(function () use ($domainRequest) {
            $row = LinodeDomainRequest::whereKey($domainRequest->id)->lockForUpdate()->first();
            if (!$row || $row->status !== 'pending') {
                return response()->json(['message' => 'This request was already decided.'], 409);
            }
            $server = LinodeResource::where('id', $row->linode_resource_id)->where('type', 'instance')->where('client_id', $row->client_id)->first();
            if (!$server || $server->status === 'gone' || empty($server->ipv4[0])) {
                return response()->json(['message' => 'The server is gone or has no IPv4 address. Reject the request or fix the server first.'], 422);
            }
            $account = LinodeAccount::find($server->linode_account_id);
            if (!$account || $account->status !== 'active') {
                return response()->json(['message' => 'The Linode account token is not valid. Fix it on the Accounts tab first.'], 422);
            }
            try {
                $domain = LinodeService::validateDomainName($row->domain);
                $out = app(LinodeDomainProvisioner::class)->add($account, $domain, $account->soa_email ?? auth()->user()->email, null, $server, $row->client_id);
            } catch (\InvalidArgumentException $e) {
                return response()->json(['message' => $e->getMessage()], 422);
            }

            $row->update(['status' => 'approved', 'decided_by' => auth()->id(), 'decided_at' => now()]);
            $this->audit($account, 'domain_request.approve', $domain, ['request_id' => $row->id, 'client_id' => $row->client_id, 'server_id' => $server->id, 'records_created' => $out['records_created']]);
            $this->notifyClient($row, 'approved', $server);

            return response()->json(['message' => $out['warning'] ?? "Domain $domain added to Linode and mapped to the client.", 'data' => ['id' => $row->id, 'status' => 'approved']]);
        });
    }

    public function reject(Request $request, LinodeDomainRequest $domainRequest): JsonResponse
    {
        $data = $request->validate(['note' => 'nullable|string|max:500']);

        return DB::transaction(function () use ($domainRequest, $data) {
            $row = LinodeDomainRequest::whereKey($domainRequest->id)->lockForUpdate()->first();
            if (!$row || $row->status !== 'pending') {
                return response()->json(['message' => 'This request was already decided.'], 409);
            }
            $row->update(['status' => 'rejected', 'decided_by' => auth()->id(), 'decided_at' => now(), 'note' => $data['note'] ?? null]);
            $server = LinodeResource::find($row->linode_resource_id);
            if ($server && ($account = LinodeAccount::find($server->linode_account_id))) {
                $this->audit($account, 'domain_request.reject', $row->domain, ['request_id' => $row->id, 'client_id' => $row->client_id]);
            }
            $this->notifyClient($row, 'rejected', $server);

            return response()->json(['message' => 'Request rejected.', 'data' => ['id' => $row->id, 'status' => 'rejected']]);
        });
    }

    private function notifyClient(LinodeDomainRequest $row, string $event, ?LinodeResource $server): void
    {
        try {
            $client = Client::find($row->client_id);
            if ($client) {
                $client->notify(new LinodeDomainRequestNotification($row, $event, Tenant::find($row->tenant_id), $server?->label));
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    private function audit(LinodeAccount $account, string $action, ?string $target, array $extra): void
    {
        LinodeAuditLog::create([
            'tenant_id' => $account->tenant_id, 'user_id' => auth()->id(), 'linode_account_id' => $account->id,
            'action' => $action, 'target' => $target, 'request' => $extra, 'response_status' => 200,
        ]);
    }
}

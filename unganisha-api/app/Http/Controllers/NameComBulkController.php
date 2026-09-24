<?php

namespace App\Http\Controllers;

use App\Models\Domain;
use App\Services\Registrar\DomainRegistrarLookup;
use App\Services\Registrar\NameComBulkSync;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Staff-only bulk actions on the /domains list. Each call handles one small chunk and returns a
 * cursor, so the browser drives progress and no request runs long. Name.com calls are read-only.
 */
class NameComBulkController extends Controller
{
    private const LOOKUP_CHUNK = 10;

    public function __construct(private NameComBulkSync $bulk, private DomainRegistrarLookup $lookup) {}

    public function bulkSync(Request $request): JsonResponse
    {
        $data = $request->validate(['after' => 'nullable|string|max:64']);
        $r = $this->bulk->runChunk(auth()->user()->tenant_id, $data['after'] ?? null);
        return response()->json(['data' => $r]);
    }

    /** Public RDAP lookup for a chunk of unlinked non-.tz domains (skips ones checked within the last 7 days). */
    public function registrarLookup(Request $request): JsonResponse
    {
        $data = $request->validate(['after' => 'nullable|string|max:64']);
        $tenant = auth()->user()->tenant_id;
        $base = fn () => DomainRegistrarLookup::scopeUnlinked(Domain::withoutGlobalScopes()->where('tenant_id', $tenant));
        $q = $base()->orderBy('id');
        if (!empty($data['after'])) $q->where('id', '>', $data['after']);
        $rows = $q->limit(self::LOOKUP_CHUNK)->get();

        $out = ['processed' => 0, 'checked' => 0, 'skipped_fresh' => 0, 'at_namecom' => 0, 'other' => 0, 'unknown' => 0, 'next' => null, 'total' => $base()->count()];
        foreach ($rows as $d) {
            $out['processed']++;
            $out['next'] = $d->id;
            if (DomainRegistrarLookup::isFresh($d)) { $out['skipped_fresh']++; $res = $d->meta['registrar_lookup']; }
            else {
                if ($out['checked'] > 0 && DomainRegistrarLookup::$gapMs > 0) usleep(DomainRegistrarLookup::$gapMs * 1000);
                $res = $this->lookup->lookup($d);
                $out['checked']++;
            }
            match ($res['kind'] ?? 'unknown') { 'namecom' => $out['at_namecom']++, 'other' => $out['other']++, default => $out['unknown']++ };
        }
        if ($rows->count() < self::LOOKUP_CHUNK) $out['next'] = null;
        return response()->json(['data' => $out]);
    }

    public function lookupOne(Domain $domain): JsonResponse
    {
        abort_unless(DomainRegistrarLookup::scopeUnlinked(Domain::query()->whereKey($domain->id))->exists(), 422, 'Registrar lookup only applies to .com/.net/.org domains that are not linked to Name.com.');
        $res = $this->lookup->lookup($domain);
        return response()->json(['data' => $res, 'message' => 'Registrar checked.']);
    }
}

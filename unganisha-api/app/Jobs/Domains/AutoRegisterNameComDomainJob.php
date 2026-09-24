<?php

namespace App\Jobs\Domains;

use App\Models\Domain;
use App\Services\Registrar\NameComRegistrationService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

/** Auto-register a paid Name.com order (tenant setting, off by default). Never blind-retried: it spends money. */
class AutoRegisterNameComDomainJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 1;

    public function __construct(public Domain $domain) {}

    public function handle(): void
    {
        $d = Domain::withoutGlobalScopes()->find($this->domain->id);
        if ($d) app(NameComRegistrationService::class)->autoRegister($d);
    }
}

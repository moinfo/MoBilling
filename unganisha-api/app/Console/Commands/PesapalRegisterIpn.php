<?php

namespace App\Console\Commands;

use App\Services\PesapalService;
use Illuminate\Console\Command;

class PesapalRegisterIpn extends Command
{
    protected $signature = 'pesapal:register-ipn';
    protected $description = 'Register the IPN URL with Pesapal and get the IPN ID';

    public function handle(): int
    {
        $url = config('pesapal.ipn_url');

        if (!$url) {
            $this->error('PESAPAL_IPN_URL is not set in .env');
            return 1;
        }

        $this->info("Registering IPN URL: {$url}");

        try {
            $pesapal = new PesapalService();
            $result = $pesapal->registerIpn($url);

            $ipnId = $result['ipn_id'] ?? null;

            if ($ipnId) {
                $this->newLine();
                $this->info('IPN registered successfully!');
                $this->warn("Add this to your .env:");
                $this->newLine();
                $this->line("PESAPAL_IPN_ID={$ipnId}");
                $this->newLine();
            } else {
                $this->warn('Response received but no ipn_id found:');
                $this->line(json_encode($result, JSON_PRETTY_PRINT));
            }

            return 0;
        } catch (\Throwable $e) {
            $this->error('Failed: ' . $e->getMessage());
            return 1;
        }
    }
}

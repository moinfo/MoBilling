<?php

namespace App\Console\Commands;

use App\Models\Tenant;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Process;

/**
 * Turns a tenant's already-saved `custom_domain` (set via Settings > Company,
 * SettingsController::updateCompany — unchanged, still the only place that
 * value is written) into a working nginx vhost + Let's Encrypt cert, so a
 * white-label reseller's own domain actually resolves without a human
 * hand-writing an nginx block from memory every time.
 *
 * Deliberately NOT exposed via any HTTP route — this only ever runs from a
 * human typing it at a root shell on this box (same privilege model a human
 * already has when they SSH in to hand-edit nginx). Mirrors the working
 * mobilling.co.tz vhost (/etc/nginx/sites-available/mobilling.co.tz) as the
 * template, and lets certbot's own --nginx plugin add the SSL block/redirect
 * the same way every other domain on this server was provisioned — this
 * command never writes SSL directives itself.
 */
class ProvisionTenantDomain extends Command
{
    protected $signature = 'tenant:provision-domain {tenant} {--email=} {--force} {--dry-run}';
    protected $description = "Write an nginx vhost + issue a Let's Encrypt cert for a tenant's custom_domain";

    private const SITES_AVAILABLE = '/etc/nginx/sites-available';
    private const SITES_ENABLED = '/etc/nginx/sites-enabled';

    public function handle(): int
    {
        $tenant = Tenant::withoutGlobalScopes()->find($this->argument('tenant'));
        if (!$tenant) {
            $this->error('No tenant found with id: ' . $this->argument('tenant'));
            return self::FAILURE;
        }

        $domain = $tenant->custom_domain;
        if (!$domain) {
            $this->error("Tenant \"{$tenant->name}\" has no custom_domain set — set it first via Settings > Company for that tenant.");
            return self::FAILURE;
        }

        if (!preg_match('/^(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$/i', $domain)) {
            $this->error("custom_domain \"{$domain}\" does not look like a valid hostname — refusing to proceed.");
            return self::FAILURE;
        }

        $dryRun = (bool) $this->option('dry-run');
        $force = (bool) $this->option('force');
        $email = $this->option('email') ?: $tenant->email;

        $this->info("Provisioning \"{$domain}\" for tenant \"{$tenant->name}\"" . ($dryRun ? ' (dry run)' : '') . '.');

        if (!$this->checkDns($domain) && !$force) {
            $this->error("\"{$domain}\" does not appear to resolve to this server yet. Point its DNS here first, or pass --force to proceed anyway (a certbot attempt will likely fail and may burn into Let's Encrypt's rate limit).");
            return self::FAILURE;
        }

        $availablePath = self::SITES_AVAILABLE . "/{$domain}";
        $enabledPath = self::SITES_ENABLED . "/{$domain}";

        if (file_exists($availablePath) && !$force) {
            $this->error("{$availablePath} already exists — refusing to overwrite. Pass --force if you're sure.");
            return self::FAILURE;
        }

        $vhost = $this->buildVhost($domain);

        if ($dryRun) {
            $this->line("--- would write {$availablePath} ---");
            $this->line($vhost);
            $this->line('--- would then run ---');
            $this->line("ln -sf {$availablePath} {$enabledPath}");
            $this->line('nginx -t && systemctl reload nginx');
            $this->line(implode(' ', $this->certbotCommand($domain, $email)));
            return self::SUCCESS;
        }

        file_put_contents($availablePath, $vhost);
        if (!file_exists($enabledPath)) {
            symlink($availablePath, $enabledPath);
        }

        $test = Process::run(['nginx', '-t']);
        if (!$test->successful()) {
            $this->error('nginx -t failed — rolling back, nginx was NOT reloaded:');
            $this->line($test->errorOutput());
            @unlink($enabledPath);
            @unlink($availablePath);
            return self::FAILURE;
        }

        $reload = Process::run(['systemctl', 'reload', 'nginx']);
        if (!$reload->successful()) {
            $this->error('nginx config is valid but reload failed:');
            $this->line($reload->errorOutput());
            return self::FAILURE;
        }

        $this->info("nginx vhost live for \"{$domain}\" over HTTP. Requesting SSL cert via certbot...");

        $certbot = Process::timeout(120)->run($this->certbotCommand($domain, $email));
        if (!$certbot->successful()) {
            $this->error("certbot failed — \"{$domain}\" is still live over plain HTTP (nginx is fine, nothing was rolled back). Fix DNS/whatever certbot is complaining about and re-run this same command:");
            $this->line($certbot->errorOutput() ?: $certbot->output());
            return self::FAILURE;
        }

        $this->info("Done — https://{$domain} is live.");
        return self::SUCCESS;
    }

    private function checkDns(string $domain): bool
    {
        $target = Process::run(['dig', '+short', $domain])->output();
        $reference = Process::run(['dig', '+short', 'mobilling.co.tz'])->output();

        $targetIps = array_filter(array_map('trim', explode("\n", $target)));
        $referenceIps = array_filter(array_map('trim', explode("\n", $reference)));

        return $targetIps && $referenceIps && array_intersect($targetIps, $referenceIps);
    }

    private function certbotCommand(string $domain, string $email): array
    {
        return [
            'certbot', '--nginx', '-d', $domain,
            '--non-interactive', '--agree-tos', '--redirect',
            '-m', $email,
        ];
    }

    private function buildVhost(string $domain): string
    {
        return <<<NGINX
        server {
            listen 80;
            listen [::]:80;
            server_name {$domain};

            root /var/www/html/MoBilling/unganisha-api/public;
            index index.php index.html;

            client_max_body_size 20M;

            location /api {
                try_files \$uri \$uri/ /index.php?\$query_string;
            }

            location /sanctum {
                try_files \$uri \$uri/ /index.php?\$query_string;
            }

            location /pesapal {
                try_files \$uri \$uri/ /index.php?\$query_string;
            }

            location /storage {
                alias /var/www/html/MoBilling/unganisha-api/storage/app/public;
                try_files \$uri \$uri/ =404;
            }

            location ~ \.php\$ {
                fastcgi_pass unix:/run/php/php8.2-fpm.sock;
                fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
                include fastcgi_params;
                fastcgi_hide_header X-Powered-By;
            }

            location /assets/ {
                root /var/www/html/MoBilling/mobilling-ui/dist;
                add_header Cache-Control "public, max-age=31536000, immutable";
                try_files \$uri =404;
            }

            location / {
                root /var/www/html/MoBilling/mobilling-ui/dist;
                add_header Cache-Control "no-cache";
                try_files \$uri \$uri/ /index.html;
            }

            location ~ /\.(?!well-known) {
                deny all;
            }
        }

        NGINX;
    }
}

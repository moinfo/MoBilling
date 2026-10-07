<?php
// php tests/Manual/run_mail_tenant_branding.php  (no DB writes — pure view rendering)
//
// Verifies the actual rendered mail HTML/text — not just that applyBranding()
// sets viewData. Laravel's markdown mail components (<x-mail::message>,
// <x-mail::layout>, the vendor/notifications/email view) do NOT automatically
// inherit the parent view's variables; $tenantBranding had to be explicitly
// forwarded as a prop at each nesting level, or every "branded" notification
// silently rendered with MoBilling's own name/logo/link regardless of which
// tenant it was for.
require __DIR__ . '/../../vendor/autoload.php';
$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\Tenant;
use App\Notifications\Concerns\HasTenantBranding;
use Illuminate\Mail\Markdown;
use Illuminate\Notifications\Messages\MailMessage;

$fail = 0;
function ok($c, $m) { global $fail; if (!$c) { $fail++; echo "FAIL $m\n"; } else echo "PASS $m\n"; }

$tenant = Tenant::find('01a0f22f-45f9-733f-a519-1d5a47cbe6e7'); // Lucham Cloud — has its own logo configured
ok((bool) $tenant, 'Lucham Cloud tenant found');
ok((bool) $tenant->logo_url, 'tenant has a logo_url configured');

$brander = new class { use HasTenantBranding; public function apply($m, $t) { return $this->applyBranding($m, $t); } };

$mail = (new MailMessage())->subject('Test')->greeting('Hello,')->line('Body line.');
$brander->apply($mail, $tenant);

$md = app(Markdown::class);
$html = $md->render($mail->markdown, $mail->data());
$text = $md->renderText($mail->markdown, $mail->data());

ok(str_contains($html, $tenant->logo_url), 'HTML header shows the TENANT\'s own logo <img>');
ok(str_contains($html, "<title>{$tenant->name}</title>"), 'HTML <title> is the tenant name, not the platform name');
ok(str_contains($html, "https://{$tenant->custom_domain}"), 'header link points at the tenant\'s own custom domain');
ok(!str_contains($html, 'MoBilling'), 'HTML has NO leftover "MoBilling" anywhere (header/footer/salutation/title)');
ok(!str_contains($text, 'MoBilling'), 'the plain-text part is branded the same way as HTML');
ok(substr_count($html, $tenant->name) >= 3, 'tenant name appears in header, title and footer');

// A platform-level notification (no tenant branding applied at all) must be unaffected —
// this is the default Laravel markdown mail used everywhere else in the app.
$plain = (new MailMessage())->subject('Test')->greeting('Hello,')->line('Body line.');
$plainHtml = $md->render($plain->markdown, $plain->data());
ok(substr_count($plainHtml, 'MoBilling') >= 3, 'an un-branded (platform) notification still shows MoBilling as before — no regression');

echo $fail === 0 ? "\nALL PASS\n" : "\n{$fail} FAILURE(S)\n";
echo "No database writes were made by this script.\n";

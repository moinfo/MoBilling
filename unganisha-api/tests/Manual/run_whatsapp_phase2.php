<?php
// php tests/Manual/run_whatsapp_phase2.php  (live DB, every test rolled back; ALL external calls faked/blocked)
require __DIR__ . '/../../vendor/autoload.php';
require __DIR__ . '/WhatsappMoreServicesTest.php'; // Fw / FakeRegistrar fakes
require __DIR__ . '/WhatsappPhase2Test.php';

$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$only = $argv[1] ?? null;
$fail = 0;
foreach (get_class_methods(Tests\Manual\WhatsappPhase2Test::class) as $m) {
    if (!str_starts_with($m, 'test_') || ($only && !str_contains($m, $only))) continue;
    $t = new Tests\Manual\WhatsappPhase2Test();
    try {
        $t->setUp();
        $t->$m();
        $t->checkNeutral();
        echo "PASS $m\n";
    } catch (\Throwable $e) {
        $fail++;
        echo "FAIL $m: " . $e->getMessage() . ' @' . basename($e->getFile()) . ':' . $e->getLine() . "\n";
    } finally {
        try { $t->tearDown(); } catch (\Throwable $e) {}
        auth()->logout();
    }
}
exit($fail ? 1 : 0);

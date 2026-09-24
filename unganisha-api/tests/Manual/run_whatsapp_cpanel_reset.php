<?php
// php tests/Manual/run_whatsapp_cpanel_reset.php  (live DB, every test rolled back; ALL external calls faked/blocked)
require __DIR__ . '/../../vendor/autoload.php';
require __DIR__ . '/WhatsappCpanelResetTest.php';

$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$fail = 0;
foreach (get_class_methods(Tests\Manual\WhatsappCpanelResetTest::class) as $m) {
    if (!str_starts_with($m, 'test_')) continue;
    $t = new Tests\Manual\WhatsappCpanelResetTest();
    try {
        $t->setUp();
        $t->$m();
        $t->checkNeutral(); // every reply of every test is scanned for supplier names / USD
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

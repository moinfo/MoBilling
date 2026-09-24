<?php
// php tests/Manual/run_whatsapp_hosting_manage.php  (live DB, every test rolled back)
require __DIR__ . '/../../vendor/autoload.php';
require __DIR__ . '/WhatsappHostingManageTest.php';

$app = require __DIR__ . '/../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$fail = 0;
foreach (get_class_methods(Tests\Manual\WhatsappHostingManageTest::class) as $m) {
    if (!str_starts_with($m, 'test_')) continue;
    $t = new Tests\Manual\WhatsappHostingManageTest();
    try {
        $t->setUp();
        $t->$m();
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

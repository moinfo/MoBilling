<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Payslip — {{ $employee->name }} — {{ $payslip->payrollRun->month_key }}</title>
    <style>
        body { font-family: Arial, sans-serif; font-size: 12px; color: #333; margin: 0; padding: 20px; }
        .header { display: table; width: 100%; margin-bottom: 20px; }
        .header-left, .header-right { display: table-cell; vertical-align: top; }
        .header-right { text-align: right; }
        h1 { font-size: 20px; margin: 0 0 5px; color: #2563eb; text-transform: uppercase; }
        .company-name { font-size: 16px; font-weight: bold; margin: 0 0 5px; }
        .company-logo { max-height: 50px; max-width: 180px; margin-bottom: 8px; }
        .status-label { display: inline-block; padding: 3px 10px; border-radius: 4px; font-size: 10px; font-weight: bold; text-transform: uppercase; color: white; margin-top: 4px; }
        .status-label.draft { background: #6b7280; }
        .status-label.finalized { background: #22c55e; }
        .info-table { display: table; width: 100%; margin: 16px 0; }
        .info-box { background: #f8f9fa; padding: 10px 14px; border-radius: 4px; }
        .info-box h3 { margin: 0 0 6px; font-size: 10px; text-transform: uppercase; color: #666; }
        .info-box p { margin: 2px 0; }
        table.lines { width: 100%; border-collapse: collapse; margin: 14px 0; }
        table.lines th { background: #2563eb; color: white; padding: 6px 10px; text-align: left; font-size: 10px; }
        table.lines td { padding: 6px 10px; border-bottom: 1px solid #eee; }
        table.lines td.amount { text-align: right; }
        .totals { width: 100%; margin-top: 8px; }
        .totals table { width: 100%; }
        .totals td { padding: 4px 10px; }
        .totals .label { text-align: right; color: #666; }
        .totals .amount { text-align: right; width: 140px; }
        .totals .net-pay { font-size: 15px; font-weight: bold; border-top: 2px solid #333; }
        .employer-costs { margin-top: 20px; padding: 10px 14px; background: #f8f9fa; border-radius: 4px; border-left: 3px solid #999; }
        .employer-costs h3 { margin: 0 0 6px; font-size: 10px; text-transform: uppercase; color: #666; }
        .footer { margin-top: 30px; text-align: center; font-size: 9px; color: #999; border-top: 1px solid #eee; padding-top: 8px; }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            @if($tenant?->logo_path)
                <img class="company-logo" src="{{ storage_path('app/public/' . $tenant->logo_path) }}" alt="{{ $tenant->name }}">
                <br>
            @endif
            <p class="company-name">{{ $tenant?->name }}</p>
            @if($tenant?->address)<p>{{ $tenant->address }}</p>@endif
        </div>
        <div class="header-right">
            <h1>Payslip</h1>
            <p>{{ \Carbon\Carbon::createFromFormat('Y-m', $payslip->payrollRun->month_key)->format('F Y') }}</p>
            <span class="status-label {{ $payslip->payrollRun->status }}">{{ $payslip->payrollRun->status }}</span>
        </div>
    </div>

    <div class="info-table">
        <div class="info-box">
            <h3>Employee</h3>
            <p><strong>{{ $employee->name }}</strong></p>
            @if($employee->email)<p>{{ $employee->email }}</p>@endif
        </div>
    </div>

    <table class="lines">
        <thead><tr><th>Earnings</th><th class="amount" style="text-align:right">Amount ({{ $tenant?->currency }})</th></tr></thead>
        <tbody>
            <tr><td>Basic Salary</td><td class="amount">{{ number_format($payslip->basic_salary, 2) }}</td></tr>
            @foreach($payslip->allowances_breakdown ?? [] as $line)
                <tr><td>{{ $line['name'] }}</td><td class="amount">{{ number_format($line['amount'], 2) }}</td></tr>
            @endforeach
            <tr><td><strong>Gross Pay</strong></td><td class="amount"><strong>{{ number_format($payslip->gross_pay, 2) }}</strong></td></tr>
        </tbody>
    </table>

    <table class="lines">
        <thead><tr><th>Deductions</th><th class="amount" style="text-align:right">Amount ({{ $tenant?->currency }})</th></tr></thead>
        <tbody>
            @foreach($payslip->statutory_employee_breakdown ?? [] as $line)
                <tr><td>{{ $line['name'] }}</td><td class="amount">{{ number_format($line['amount'], 2) }}</td></tr>
            @endforeach
            <tr><td>PAYE</td><td class="amount">{{ number_format($payslip->paye_amount, 2) }}</td></tr>
            @foreach($payslip->deductions_breakdown ?? [] as $line)
                <tr><td>{{ $line['name'] }}</td><td class="amount">{{ number_format($line['amount'], 2) }}</td></tr>
            @endforeach
        </tbody>
    </table>

    <div class="totals">
        <table>
            <tr class="net-pay"><td class="label">Net Pay</td><td class="amount">{{ $tenant?->currency }} {{ number_format($payslip->net_pay, 2) }}</td></tr>
        </table>
    </div>

    @if(!empty($payslip->statutory_employer_breakdown))
        <div class="employer-costs">
            <h3>Employer Contributions (not deducted from employee)</h3>
            @foreach($payslip->statutory_employer_breakdown as $line)
                <p>{{ $line['name'] }}: {{ number_format($line['amount'], 2) }}</p>
            @endforeach
        </div>
    @endif

    <div class="footer">
        Generated {{ now()->format('d M Y H:i') }} · {{ config('app.name') }}
    </div>
</body>
</html>

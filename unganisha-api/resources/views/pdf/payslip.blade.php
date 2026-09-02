<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Payslip — {{ $employee->name }} — {{ $payslip->payrollRun->month_key }}</title>
    <style>
        body { font-family: Arial, sans-serif; font-size: 12px; color: #333; margin: 0; padding: 20px; }
        .header { display: table; width: 100%; margin-bottom: 20px; padding-bottom: 16px; border-bottom: 2px solid #2563eb; }
        .header-left, .header-right { display: table-cell; vertical-align: top; }
        .header-right { text-align: right; }
        h1 { font-size: 22px; margin: 0 0 5px; color: #2563eb; text-transform: uppercase; letter-spacing: 1px; }
        .period { font-size: 14px; color: #555; margin: 0 0 6px; }
        .company-name { font-size: 17px; font-weight: bold; margin: 0 0 4px; color: #111; }
        .company-logo { max-height: 60px; max-width: 200px; margin-bottom: 8px; }
        .company-meta p { margin: 1px 0; color: #666; font-size: 11px; }
        .status-label { display: inline-block; padding: 3px 12px; border-radius: 4px; font-size: 10px; font-weight: bold; text-transform: uppercase; color: white; margin-top: 4px; }
        .status-label.draft { background: #6b7280; }
        .status-label.finalized { background: #22c55e; }

        .info-table { display: table; width: 100%; margin: 16px 0; }
        .info-left, .info-right { display: table-cell; width: 50%; vertical-align: top; }
        .info-left { padding-right: 8px; }
        .info-right { padding-left: 8px; }
        .info-box { background: #f8f9fa; padding: 10px 14px; border-radius: 4px; }
        .info-box h3 { margin: 0 0 6px; font-size: 10px; text-transform: uppercase; color: #666; letter-spacing: .5px; }
        .info-box p { margin: 2px 0; }
        .info-box .employee-name { font-size: 13px; font-weight: bold; color: #111; }

        .columns { display: table; width: 100%; margin: 14px 0; }
        .col { display: table-cell; width: 50%; vertical-align: top; }
        .col-left { padding-right: 6px; }
        .col-right { padding-left: 6px; }

        table.lines { width: 100%; border-collapse: collapse; }
        table.lines th { background: #2563eb; color: white; padding: 6px 10px; text-align: left; font-size: 10px; text-transform: uppercase; letter-spacing: .3px; }
        table.lines td { padding: 6px 10px; border-bottom: 1px solid #eee; }
        table.lines tr:nth-child(even) td { background: #f8f9fa; }
        table.lines td.amount, table.lines th.amount { text-align: right; }
        table.lines tr.subtotal td { border-top: 1.5px solid #333; font-weight: bold; background: #fff; }

        .net-pay-box { margin-top: 16px; background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 14px 18px; display: table; width: 100%; }
        .net-pay-box .label { display: table-cell; font-size: 13px; color: #1e3a8a; vertical-align: middle; }
        .net-pay-box .amount { display: table-cell; text-align: right; font-size: 20px; font-weight: bold; color: #1e3a8a; vertical-align: middle; }

        .bank-details { margin-top: 16px; padding: 10px 14px; background: #f8f9fa; border-radius: 4px; border-left: 3px solid #2563eb; }
        .bank-details h3 { margin: 0 0 6px; font-size: 10px; text-transform: uppercase; color: #2563eb; letter-spacing: .5px; }
        .bank-details p { margin: 2px 0; }

        .employer-costs { margin-top: 14px; padding: 10px 14px; background: #f8f9fa; border-radius: 4px; border-left: 3px solid #999; }
        .employer-costs h3 { margin: 0 0 6px; font-size: 10px; text-transform: uppercase; color: #666; letter-spacing: .5px; }
        .employer-costs p { margin: 2px 0; }

        .footer { margin-top: 30px; text-align: center; font-size: 9px; color: #999; border-top: 1px solid #eee; padding-top: 8px; }
        .confidential { text-align: center; font-size: 9px; color: #aaa; margin-top: 4px; text-transform: uppercase; letter-spacing: .5px; }
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
            <div class="company-meta">
                @if($tenant?->address)<p>{{ $tenant->address }}</p>@endif
                @if($tenant?->email)<p>{{ $tenant->email }}</p>@endif
                @if($tenant?->phone)<p>{{ $tenant->phone }}</p>@endif
            </div>
        </div>
        <div class="header-right">
            <h1>Payslip</h1>
            <p class="period">{{ \Carbon\Carbon::createFromFormat('Y-m', $payslip->payrollRun->month_key)->format('F Y') }}</p>
            <span class="status-label {{ $payslip->payrollRun->status }}">{{ $payslip->payrollRun->status }}</span>
        </div>
    </div>

    <div class="info-table">
        <div class="info-left">
            <div class="info-box">
                <h3>Employee</h3>
                <p class="employee-name">{{ $employee->name }}</p>
                @if($employeeProfile?->position)<p>{{ $employeeProfile->position }}@if($employeeProfile->department) &middot; {{ $employeeProfile->department }}@endif</p>@endif
                @if($employee->email)<p>{{ $employee->email }}</p>@endif
            </div>
        </div>
        <div class="info-right">
            <div class="info-box">
                <h3>Pay Details</h3>
                @if($employeeProfile?->employee_number)<p>Employee No: {{ $employeeProfile->employee_number }}</p>@endif
                <p>Pay Period: {{ \Carbon\Carbon::createFromFormat('Y-m', $payslip->payrollRun->month_key)->format('F Y') }}</p>
                <p>Currency: {{ $tenant?->currency }}</p>
            </div>
        </div>
    </div>

    <div class="columns">
        <div class="col col-left">
            <table class="lines">
                <thead><tr><th>Earnings</th><th class="amount">Amount</th></tr></thead>
                <tbody>
                    <tr><td>Basic Salary</td><td class="amount">{{ number_format($payslip->basic_salary, 2) }}</td></tr>
                    @foreach($payslip->allowances_breakdown ?? [] as $line)
                        <tr><td>{{ $line['name'] }}</td><td class="amount">{{ number_format($line['amount'], 2) }}</td></tr>
                    @endforeach
                    <tr class="subtotal"><td>Gross Pay</td><td class="amount">{{ number_format($payslip->gross_pay, 2) }}</td></tr>
                </tbody>
            </table>
        </div>
        <div class="col col-right">
            <table class="lines">
                <thead><tr><th>Deductions</th><th class="amount">Amount</th></tr></thead>
                <tbody>
                    @foreach($payslip->statutory_employee_breakdown ?? [] as $line)
                        <tr><td>{{ $line['name'] }}</td><td class="amount">{{ number_format($line['amount'], 2) }}</td></tr>
                    @endforeach
                    @if($payslip->paye_amount > 0)
                        <tr><td>PAYE</td><td class="amount">{{ number_format($payslip->paye_amount, 2) }}</td></tr>
                    @endif
                    @foreach($payslip->deductions_breakdown ?? [] as $line)
                        <tr><td>{{ $line['name'] }}</td><td class="amount">{{ number_format($line['amount'], 2) }}</td></tr>
                    @endforeach
                    <tr class="subtotal">
                        <td>Total Deductions</td>
                        <td class="amount">{{ number_format($payslip->gross_pay - $payslip->net_pay, 2) }}</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>

    <div class="net-pay-box">
        <div class="label">Net Pay</div>
        <div class="amount">{{ $tenant?->currency }} {{ number_format($payslip->net_pay, 2) }}</div>
    </div>

    @if($employeeProfile?->bank_name || $employeeProfile?->bank_account_number)
        <div class="bank-details">
            <h3>Payment Details</h3>
            @if($employeeProfile->bank_name)<p><strong>Bank:</strong> {{ $employeeProfile->bank_name }}</p>@endif
            @if($employeeProfile->bank_account_name)<p><strong>Account Name:</strong> {{ $employeeProfile->bank_account_name }}</p>@endif
            @if($employeeProfile->bank_account_number)<p><strong>Account Number:</strong> {{ $employeeProfile->bank_account_number }}</p>@endif
        </div>
    @endif

    @if(!empty($payslip->statutory_employer_breakdown))
        <div class="employer-costs">
            <h3>Employer Contributions (not deducted from employee)</h3>
            @foreach($payslip->statutory_employer_breakdown as $line)
                <p>{{ $line['name'] }}: {{ number_format($line['amount'], 2) }}</p>
            @endforeach
        </div>
    @endif

    <div class="footer">
        <p>Generated by {{ config('app.name') }} &mdash; {{ now()->format('d M Y H:i') }}</p>
        <p class="confidential">Confidential &mdash; for the named employee only</p>
    </div>
</body>
</html>

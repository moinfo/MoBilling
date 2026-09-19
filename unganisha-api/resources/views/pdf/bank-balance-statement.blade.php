<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Bank Balance Statement — {{ $report['bank_account']['bank_name'] }}</title>
<style>
    * { font-family: Arial, sans-serif; }
    body { font-size: 11px; color: #333; margin: 0; padding: 24px; }
    .header { display: table; width: 100%; margin-bottom: 18px; }
    .header-left, .header-right { display: table-cell; vertical-align: top; }
    .header-right { text-align: right; }
    .company-logo { max-height: 55px; max-width: 190px; margin-bottom: 6px; }
    .company-name { font-size: 16px; font-weight: bold; margin: 0 0 4px; }
    .company-name + p { margin: 1px 0; color: #666; }
    h1 { font-size: 20px; margin: 0 0 4px; color: #2563eb; text-transform: uppercase; }
    .period { font-size: 11px; color: #666; }

    .account-box { background: #f0f7ff; border-left: 3px solid #2563eb; border-radius: 4px; padding: 10px 14px; margin-bottom: 16px; }
    .account-box .bank-name { font-size: 13px; font-weight: bold; margin: 0 0 2px; }
    .account-box .account-number { color: #555; }

    .summary { width: 100%; border-collapse: collapse; margin-bottom: 18px; }
    .summary td { width: 20%; padding: 0 4px; }
    .summary .card { border: 1px solid #e5e7eb; border-radius: 4px; padding: 8px 10px; }
    .summary .label { font-size: 9px; text-transform: uppercase; color: #888; margin: 0 0 3px; }
    .summary .value { font-size: 13px; font-weight: bold; margin: 0; }
    .c-gray .value { color: #495057; }
    .c-green .value { color: #2f9e44; }
    .c-red .value { color: #e03131; }
    .c-orange .value { color: #e8590c; }
    .c-blue .value { color: #2563eb; }

    table.txns { width: 100%; border-collapse: collapse; }
    table.txns th { background: #2563eb; color: #fff; padding: 6px 8px; text-align: left; font-size: 10px; text-transform: uppercase; }
    table.txns td { padding: 5px 8px; border-bottom: 1px solid #eee; font-size: 10px; }
    table.txns tr:nth-child(even) td { background: #f8f9fa; }
    .text-right { text-align: right; }
    .balance-row td { background: #f1f3f5 !important; font-weight: bold; border-top: 1px solid #ccc; border-bottom: 1px solid #ccc; }
    .closing-row td { background: #eaf2ff !important; font-weight: bold; color: #2563eb; border-top: 2px solid #2563eb; }
    .badge { display: inline-block; padding: 1px 7px; border-radius: 3px; font-size: 9px; text-transform: capitalize; color: #fff; }
    .badge-deposit { background: #2f9e44; }
    .badge-withdraw { background: #e03131; }
    .badge-charge { background: #e8590c; }
    .neg { color: #e03131; }

    .footer { margin-top: 24px; text-align: center; font-size: 9px; color: #999; border-top: 1px solid #eee; padding-top: 8px; }
</style>
</head>
<body>

    <div class="header">
        <div class="header-left">
            @if($tenant->logo_path)
                <img class="company-logo" src="{{ storage_path('app/public/' . $tenant->logo_path) }}" alt="{{ $tenant->name }}">
                <br>
            @endif
            <p class="company-name">{{ $tenant->name }}</p>
            @if($tenant->address)<p>{{ $tenant->address }}</p>@endif
            @if($tenant->email)<p>{{ $tenant->email }}</p>@endif
            @if($tenant->phone)<p>{{ $tenant->phone }}</p>@endif
        </div>
        <div class="header-right">
            <h1>Bank Statement</h1>
            <p class="period">
                {{ \Carbon\Carbon::parse($report['period_start'])->format('d M Y') }}
                &mdash;
                {{ \Carbon\Carbon::parse($report['period_end'])->format('d M Y') }}
            </p>
            <p class="period">Generated {{ now()->format('d M Y, H:i') }}</p>
        </div>
    </div>

    <div class="account-box">
        <p class="bank-name">{{ $report['bank_account']['bank_name'] }}</p>
        <p class="account-number">Account No: {{ $report['bank_account']['account_number'] }}</p>
    </div>

    <table class="summary">
        <tr>
            <td>
                <div class="card c-gray">
                    <p class="label">Opening Balance</p>
                    <p class="value">{{ $tenant->currency }} {{ number_format($report['opening_balance'], 2) }}</p>
                </div>
            </td>
            <td>
                <div class="card c-green">
                    <p class="label">Deposits</p>
                    <p class="value">{{ $tenant->currency }} {{ number_format($report['total_deposits'], 2) }}</p>
                </div>
            </td>
            <td>
                <div class="card c-red">
                    <p class="label">Withdrawals</p>
                    <p class="value">{{ $tenant->currency }} {{ number_format($report['total_withdrawals'], 2) }}</p>
                </div>
            </td>
            <td>
                <div class="card c-orange">
                    <p class="label">Charges</p>
                    <p class="value">{{ $tenant->currency }} {{ number_format($report['total_charges'], 2) }}</p>
                </div>
            </td>
            <td>
                <div class="card c-blue">
                    <p class="label">Closing Balance</p>
                    <p class="value">{{ $tenant->currency }} {{ number_format($report['closing_balance'], 2) }}</p>
                </div>
            </td>
        </tr>
    </table>

    <table class="txns">
        <thead>
            <tr>
                <th>Date</th>
                <th>Type</th>
                <th>System</th>
                <th>Property</th>
                <th class="text-right">Amount</th>
                <th class="text-right">Balance</th>
            </tr>
        </thead>
        <tbody>
            <tr class="balance-row">
                <td colspan="5">Opening balance{{ $report['opening_balance_date'] ? ' (as of ' . \Carbon\Carbon::parse($report['opening_balance_date'])->format('d M Y') . ')' : '' }}</td>
                <td class="text-right">{{ $tenant->currency }} {{ number_format($report['opening_balance'], 2) }}</td>
            </tr>
            @forelse ($report['rows'] as $row)
                <tr>
                    <td>{{ \Carbon\Carbon::parse($row['record_date'])->format('d M Y') }}</td>
                    <td><span class="badge badge-{{ $row['type'] }}">{{ $row['type'] }}</span></td>
                    <td>{{ $row['system_name'] }}</td>
                    <td>{{ $row['system_property_name'] }}</td>
                    <td class="text-right {{ $row['signed_amount'] < 0 ? 'neg' : '' }}">
                        {{ $row['signed_amount'] < 0 ? '−' : '+' }}{{ $tenant->currency }} {{ number_format(abs($row['signed_amount']), 2) }}
                    </td>
                    <td class="text-right">{{ $tenant->currency }} {{ number_format($row['running_balance'], 2) }}</td>
                </tr>
            @empty
                <tr><td colspan="6" style="text-align:center; color:#999; padding: 14px;">No transactions in this period.</td></tr>
            @endforelse
            <tr class="closing-row">
                <td colspan="5">Closing balance</td>
                <td class="text-right">{{ $tenant->currency }} {{ number_format($report['closing_balance'], 2) }}</td>
            </tr>
        </tbody>
    </table>

    <div class="footer">Generated by {{ config('app.name', 'MoBilling') }} on {{ now()->format('d M Y H:i') }}</div>

</body>
</html>

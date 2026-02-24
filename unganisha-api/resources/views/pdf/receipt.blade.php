<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Receipt — {{ $document->document_number }}</title>
    <style>
        body { font-family: Arial, sans-serif; font-size: 12px; color: #333; margin: 0; padding: 20px; }
        .header { display: table; width: 100%; margin-bottom: 30px; }
        .header-left, .header-right { display: table-cell; vertical-align: top; }
        .header-right { text-align: right; }
        h1 { font-size: 24px; margin: 0 0 5px; color: #16a34a; text-transform: uppercase; }
        .receipt-number { font-size: 14px; color: #666; }
        .company-name { font-size: 18px; font-weight: bold; margin: 0 0 5px; }
        .company-logo { max-height: 60px; max-width: 200px; margin-bottom: 8px; }
        .info-table { display: table; width: 100%; margin-bottom: 20px; }
        .info-left, .info-right { display: table-cell; width: 50%; vertical-align: top; }
        .info-box { background: #f0fdf4; padding: 12px; border-radius: 4px; border-left: 3px solid #16a34a; }
        .info-box h3 { margin: 0 0 8px; font-size: 11px; text-transform: uppercase; color: #666; }
        .info-box p { margin: 2px 0; }
        .details { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .details th { background: #16a34a; color: white; padding: 8px 12px; text-align: left; font-size: 11px; }
        .details td { padding: 8px 12px; border-bottom: 1px solid #eee; }
        .amount-box { background: #f0fdf4; border: 2px solid #16a34a; border-radius: 8px; padding: 20px; text-align: center; margin: 20px 0; }
        .amount-box .label { font-size: 12px; color: #666; text-transform: uppercase; margin-bottom: 5px; }
        .amount-box .amount { font-size: 28px; font-weight: bold; color: #16a34a; }
        .status-badge { display: inline-block; padding: 4px 12px; border-radius: 4px; font-size: 12px; font-weight: bold; color: white; background: #16a34a; }
        .text-right { text-align: right; }
        .footer { margin-top: 40px; text-align: center; font-size: 10px; color: #999; border-top: 1px solid #eee; padding-top: 10px; }
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
            @if($tenant->tax_id)<p>KRA PIN: {{ $tenant->tax_id }}</p>@endif
        </div>
        <div class="header-right">
            <h1>Payment Receipt</h1>
            <p class="receipt-number">{{ $document->document_number }}</p>
            <p>Receipt Date: {{ $payment->payment_date->format('d M Y') }}</p>
            <p><span class="status-badge">PAID</span></p>
        </div>
    </div>

    <div class="info-table">
        <div class="info-left">
            <div class="info-box">
                <h3>Received From</h3>
                <p><strong>{{ $client->name }}</strong></p>
                @if($client->address)<p>{{ $client->address }}</p>@endif
                @if($client->email)<p>{{ $client->email }}</p>@endif
                @if($client->phone)<p>{{ $client->phone }}</p>@endif
            </div>
        </div>
        <div class="info-right"></div>
    </div>

    <div class="amount-box">
        <div class="label">Amount Received</div>
        <div class="amount">{{ $tenant->currency }} {{ number_format($payment->amount, 2) }}</div>
    </div>

    <table class="details">
        <thead>
            <tr>
                <th>Detail</th>
                <th>Info</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Invoice Number</td>
                <td><strong>{{ $document->document_number }}</strong></td>
            </tr>
            <tr>
                <td>Invoice Amount</td>
                <td>{{ $tenant->currency }} {{ number_format($document->total, 2) }}</td>
            </tr>
            <tr>
                <td>Amount Paid (this payment)</td>
                <td><strong>{{ $tenant->currency }} {{ number_format($payment->amount, 2) }}</strong></td>
            </tr>
            <tr>
                <td>Total Paid to Date</td>
                <td>{{ $tenant->currency }} {{ number_format($totalPaid, 2) }}</td>
            </tr>
            <tr>
                <td>Balance Due</td>
                <td>{{ $tenant->currency }} {{ number_format($balanceDue, 2) }}</td>
            </tr>
            <tr>
                <td>Payment Method</td>
                <td>{{ ucfirst(str_replace('_', ' ', $payment->payment_method)) }}</td>
            </tr>
            @if($payment->reference)
            <tr>
                <td>Reference</td>
                <td>{{ $payment->reference }}</td>
            </tr>
            @endif
            @if($payment->notes)
            <tr>
                <td>Notes</td>
                <td>{{ $payment->notes }}</td>
            </tr>
            @endif
        </tbody>
    </table>

    <div class="footer">
        <p>Thank you for your payment. &mdash; Generated by MoBilling {{ now()->format('d M Y H:i') }}</p>
    </div>
</body>
</html>

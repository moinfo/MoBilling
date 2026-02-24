<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>SMS Receipt {{ $purchase->receipt_number }}</title>
    <style>
        body { font-family: Arial, sans-serif; font-size: 12px; color: #333; margin: 0; padding: 20px; }
        .header { display: table; width: 100%; margin-bottom: 30px; }
        .header-left, .header-right { display: table-cell; vertical-align: top; }
        .header-right { text-align: right; }
        h1 { font-size: 24px; margin: 0 0 5px; color: #2563eb; text-transform: uppercase; }
        .doc-number { font-size: 14px; color: #666; }
        .company-name { font-size: 18px; font-weight: bold; margin: 0 0 5px; }
        .info-table { display: table; width: 100%; margin-bottom: 20px; }
        .info-left, .info-right { display: table-cell; width: 50%; vertical-align: top; }
        .info-box { background: #f8f9fa; padding: 12px; border-radius: 4px; }
        .info-box h3 { margin: 0 0 8px; font-size: 11px; text-transform: uppercase; color: #666; }
        .info-box p { margin: 2px 0; }
        table.items { width: 100%; border-collapse: collapse; margin: 20px 0; }
        table.items th { background: #2563eb; color: white; padding: 8px 12px; text-align: left; font-size: 11px; }
        table.items td { padding: 8px 12px; border-bottom: 1px solid #eee; }
        .totals { float: right; width: 250px; margin-top: 10px; }
        .totals table { width: 100%; }
        .totals td { padding: 4px 8px; }
        .totals .grand-total { font-size: 16px; font-weight: bold; border-top: 2px solid #333; }
        .payment-details { clear: both; margin-top: 30px; padding: 12px; background: #f0fdf4; border-radius: 4px; border-left: 3px solid #16a34a; }
        .payment-details h3 { margin: 0 0 8px; font-size: 12px; text-transform: uppercase; color: #16a34a; }
        .payment-details p { margin: 2px 0; }
        .footer { margin-top: 40px; text-align: center; font-size: 10px; color: #999; border-top: 1px solid #eee; padding-top: 10px; }
        .text-right { text-align: right; }
        .status-badge { display: inline-block; padding: 3px 10px; border-radius: 3px; font-size: 11px; font-weight: bold; }
        .status-paid { background: #d1fae5; color: #065f46; }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            <p class="company-name">MoBilling</p>
            <p>Moinfotech Company Ltd</p>
            <p>Dar es Salaam, Tanzania</p>
        </div>
        <div class="header-right">
            <h1>SMS Purchase Receipt</h1>
            <p class="doc-number">{{ $purchase->receipt_number }}</p>
            <p>Date: {{ $purchase->completed_at ? $purchase->completed_at->format('d M Y') : $purchase->created_at->format('d M Y') }}</p>
            <p>
                Status:
                <span class="status-badge status-paid">PAID</span>
            </p>
        </div>
    </div>

    <div class="info-table">
        <div class="info-left">
            <div class="info-box">
                <h3>Bill To</h3>
                <p><strong>{{ $tenant->name }}</strong></p>
                @if($tenant->email)<p>{{ $tenant->email }}</p>@endif
                @if($tenant->phone)<p>{{ $tenant->phone }}</p>@endif
                @if($tenant->address)<p>{{ $tenant->address }}</p>@endif
            </div>
        </div>
        <div class="info-right"></div>
    </div>

    <table class="items">
        <thead>
            <tr>
                <th>#</th>
                <th>Description</th>
                <th>Quantity</th>
                <th class="text-right">Unit Price (TZS)</th>
                <th class="text-right">Amount (TZS)</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>1</td>
                <td>{{ $purchase->package_name }} — SMS Credits</td>
                <td>{{ number_format($purchase->sms_quantity) }}</td>
                <td class="text-right">{{ number_format($purchase->price_per_sms, 2) }}</td>
                <td class="text-right">{{ number_format($purchase->total_amount, 2) }}</td>
            </tr>
        </tbody>
    </table>

    <div class="totals">
        <table>
            <tr class="grand-total">
                <td><strong>Total:</strong></td>
                <td class="text-right"><strong>TZS {{ number_format($purchase->total_amount, 2) }}</strong></td>
            </tr>
        </table>
    </div>

    <div class="payment-details">
        <h3>Payment Details</h3>
        @if($purchase->payment_method_used)
            <p><strong>Method:</strong> {{ $purchase->payment_method_used }}</p>
        @endif
        @if($purchase->confirmation_code)
            <p><strong>Confirmation Code:</strong> {{ $purchase->confirmation_code }}</p>
        @endif
        @if($purchase->completed_at)
            <p><strong>Paid At:</strong> {{ $purchase->completed_at->format('d M Y, H:i') }}</p>
        @endif
    </div>

    <div class="footer">
        <p>Thank you for choosing MoBilling</p>
        <p>Generated by MoBilling &mdash; {{ now()->format('d M Y H:i') }}</p>
    </div>
</body>
</html>

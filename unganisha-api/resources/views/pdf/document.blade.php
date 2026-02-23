<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ $document->document_number }}</title>
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
        table.items tr:nth-child(even) { background: #f8f9fa; }
        .totals { float: right; width: 250px; }
        .totals table { width: 100%; }
        .totals td { padding: 4px 8px; }
        .totals .grand-total { font-size: 16px; font-weight: bold; border-top: 2px solid #333; }
        .notes { clear: both; margin-top: 30px; padding: 12px; background: #f8f9fa; border-radius: 4px; }
        .footer { margin-top: 40px; text-align: center; font-size: 10px; color: #999; border-top: 1px solid #eee; padding-top: 10px; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 3px; font-size: 10px; color: white; }
        .badge-product { background: #3b82f6; }
        .badge-service { background: #22c55e; }
        .text-right { text-align: right; }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            <p class="company-name">{{ $tenant->name }}</p>
            @if($tenant->address)<p>{{ $tenant->address }}</p>@endif
            @if($tenant->email)<p>{{ $tenant->email }}</p>@endif
            @if($tenant->phone)<p>{{ $tenant->phone }}</p>@endif
            @if($tenant->tax_id)<p>KRA PIN: {{ $tenant->tax_id }}</p>@endif
        </div>
        <div class="header-right">
            <h1>{{ ucfirst($document->type) }}</h1>
            <p class="doc-number">{{ $document->document_number }}</p>
            <p>Date: {{ $document->date->format('d M Y') }}</p>
            @if($document->due_date)
                <p>Due: {{ $document->due_date->format('d M Y') }}</p>
            @endif
            <p>Status: {{ ucfirst($document->status) }}</p>
        </div>
    </div>

    <div class="info-table">
        <div class="info-left">
            <div class="info-box">
                <h3>Bill To</h3>
                <p><strong>{{ $client->name }}</strong></p>
                @if($client->address)<p>{{ $client->address }}</p>@endif
                @if($client->email)<p>{{ $client->email }}</p>@endif
                @if($client->phone)<p>{{ $client->phone }}</p>@endif
                @if($client->tax_id)<p>KRA PIN: {{ $client->tax_id }}</p>@endif
            </div>
        </div>
        <div class="info-right"></div>
    </div>

    <table class="items">
        <thead>
            <tr>
                <th>#</th>
                <th>Description</th>
                <th>Type</th>
                <th>Qty</th>
                <th>Unit</th>
                <th class="text-right">Price</th>
                <th class="text-right">Tax</th>
                <th class="text-right">Total</th>
            </tr>
        </thead>
        <tbody>
            @foreach($items as $i => $item)
            <tr>
                <td>{{ $i + 1 }}</td>
                <td>{{ $item->description }}</td>
                <td><span class="badge badge-{{ $item->item_type }}">{{ ucfirst($item->item_type) }}</span></td>
                <td>{{ number_format($item->quantity, 2) }}</td>
                <td>{{ $item->unit }}</td>
                <td class="text-right">{{ number_format($item->price, 2) }}</td>
                <td class="text-right">{{ number_format($item->tax_amount, 2) }}</td>
                <td class="text-right">{{ number_format($item->total, 2) }}</td>
            </tr>
            @endforeach
        </tbody>
    </table>

    <div class="totals">
        <table>
            <tr>
                <td>Subtotal:</td>
                <td class="text-right">{{ $tenant->currency }} {{ number_format($document->subtotal, 2) }}</td>
            </tr>
            <tr>
                <td>Tax:</td>
                <td class="text-right">{{ $tenant->currency }} {{ number_format($document->tax_amount, 2) }}</td>
            </tr>
            <tr class="grand-total">
                <td><strong>Total:</strong></td>
                <td class="text-right"><strong>{{ $tenant->currency }} {{ number_format($document->total, 2) }}</strong></td>
            </tr>
        </table>
    </div>

    @if($document->notes)
    <div class="notes">
        <strong>Notes:</strong><br>
        {{ $document->notes }}
    </div>
    @endif

    <div class="footer">
        <p>Generated by MoBilling &mdash; {{ now()->format('d M Y H:i') }}</p>
    </div>
</body>
</html>

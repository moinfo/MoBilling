<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ $voucher['voucher_number'] }}</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: DejaVu Sans, sans-serif; font-size: 11px; color: #1f2937; margin: 0; padding: 18px; }

        /* Watermark behind everything — gives the document its identity at a glance */
        .watermark {
            position: fixed; top: 38%; left: 12%;
            font-size: 78px; font-weight: bold;
            color: #2563eb; opacity: 0.05;
            transform: rotate(-32deg);
            letter-spacing: 8px;
            pointer-events: none;
            z-index: 0;
        }

        /* Header: logo + company on the left, voucher number on the right */
        .header { display: table; width: 100%; margin-bottom: 12px; padding-bottom: 12px; border-bottom: 2px solid #2563eb; }
        .header-left, .header-right { display: table-cell; vertical-align: top; }
        .header-right { text-align: right; }
        .company-logo { max-height: 50px; max-width: 160px; margin-bottom: 4px; }
        .company-name { font-size: 13px; font-weight: bold; margin: 0; color: #1f2937; }
        .company-meta { color: #6b7280; font-size: 9px; margin-top: 2px; line-height: 1.5; }
        .voucher-no .label { color: #6b7280; font-size: 9px; text-transform: uppercase; letter-spacing: 0.5px; }
        .voucher-no .num { font-size: 13px; font-weight: bold; color: #2563eb; margin-top: 2px; }

        /* Title bar */
        .title {
            text-align: center; font-size: 15px; font-weight: bold;
            letter-spacing: 3px; margin: 12px 0 14px;
            text-transform: uppercase; color: #2563eb;
        }

        .date-row { margin-bottom: 10px; }
        .date-row .label { color: #6b7280; font-size: 10px; }
        .date-row .value { font-weight: bold; }

        /* Amount block — the headline number, with a soft brand-colored frame */
        .amount-box {
            border: 2px solid #2563eb;
            background: #eff6ff;
            padding: 14px;
            text-align: center;
            margin: 10px 0 14px;
            border-radius: 4px;
        }
        .amount-box .label { color: #6b7280; font-size: 10px; text-transform: uppercase; letter-spacing: 1px; }
        .amount-box .value { font-size: 22px; font-weight: bold; margin-top: 4px; color: #1e40af; }

        /* Field rows */
        .field { margin: 7px 0; padding-bottom: 5px; border-bottom: 1px dotted #d1d5db; }
        .field .label { color: #6b7280; font-size: 9px; text-transform: uppercase; letter-spacing: 0.5px; }
        .field .value { font-size: 12px; min-height: 16px; margin-top: 2px; }

        /* Signature block */
        .signatures { margin-top: 24px; width: 100%; }
        .signatures td { width: 50%; vertical-align: top; padding: 0 12px; }
        .sig-line { border-bottom: 1.5px solid #1f2937; height: 30px; margin-bottom: 4px; }
        .sig-label { color: #6b7280; font-size: 9px; text-transform: uppercase; letter-spacing: 0.5px; text-align: center; }
        .sig-name { text-align: center; font-weight: bold; font-size: 11px; margin-top: 2px; }

        .footer { margin-top: 18px; padding-top: 8px; border-top: 1px solid #e5e7eb; text-align: center; color: #9ca3af; font-size: 9px; font-style: italic; }
    </style>
</head>
<body>
    <div class="watermark">PETTY CASH</div>

    <div class="header">
        <div class="header-left">
            @if(!empty($tenant->logo_path))
                <img class="company-logo" src="{{ storage_path('app/public/' . $tenant->logo_path) }}" alt="{{ $tenant->name }}">
                <br>
            @endif
            <p class="company-name">{{ $tenant->name ?? '—' }}</p>
            <div class="company-meta">
                @if(!empty($tenant->address)){{ $tenant->address }}@endif
                @if(!empty($tenant->phone)) · {{ $tenant->phone }}@endif
                @if(!empty($tenant->email))<br>{{ $tenant->email }}@endif
                @if(!empty($tenant->tax_id)) · TIN: {{ $tenant->tax_id }}@endif
            </div>
        </div>
        <div class="header-right voucher-no">
            <div class="label">Voucher No.</div>
            <div class="num">{{ $voucher['voucher_number'] }}</div>
        </div>
    </div>

    <div class="title">{{ $voucher['title'] }}</div>

    <div class="date-row">
        <span class="label">Date:</span>
        <span class="value">{{ optional($voucher['date'])->format('d M Y') }}</span>
    </div>

    <div class="amount-box">
        <div class="label">Amount</div>
        <div class="value">{{ $tenant->currency ?? '' }} {{ number_format($voucher['amount'], 2) }}</div>
    </div>

    <div class="field">
        <div class="label">Purpose / Particulars</div>
        <div class="value">{{ $voucher['purpose'] ?? '—' }}</div>
    </div>

    @if(!empty($voucher['category']) || !empty($voucher['sub_category']))
        <div class="field">
            <div class="label">Category</div>
            <div class="value">
                {{ $voucher['category'] ?? '' }}
                @if(!empty($voucher['sub_category'])) — {{ $voucher['sub_category'] }} @endif
            </div>
        </div>
    @endif

    @if(!empty($voucher['reference']))
        <div class="field">
            <div class="label">Reference</div>
            <div class="value">{{ $voucher['reference'] }}</div>
        </div>
    @endif

    @if(!empty($voucher['notes']) && $voucher['notes'] !== $voucher['purpose'])
        <div class="field">
            <div class="label">Notes</div>
            <div class="value">{{ $voucher['notes'] }}</div>
        </div>
    @endif

    <table class="signatures" cellpadding="0" cellspacing="0">
        <tr>
            <td>
                <div class="sig-line"></div>
                <div class="sig-label">Given By (Signature &amp; Date)</div>
                <div class="sig-name">{{ $voucher['given_by_name'] ?? '' }}</div>
            </td>
            <td>
                <div class="sig-line"></div>
                <div class="sig-label">Received By (Signature &amp; Date)</div>
                <div class="sig-name">{{ $voucher['received_by_name'] ?? '' }}</div>
            </td>
        </tr>
    </table>

    <div class="footer">
        {{ $tenant->name ?? 'MoBilling' }} · Petty Cash Voucher · Generated {{ now()->format('d M Y, H:i') }}
    </div>
</body>
</html>

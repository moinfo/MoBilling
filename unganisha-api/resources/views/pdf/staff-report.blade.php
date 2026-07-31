<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { font-family: DejaVu Sans, sans-serif; font-size: 11px; color: #222; }
  h1 { font-size: 16px; margin: 0 0 2px; }
  h2 { font-size: 12px; margin: 14px 0 5px; text-transform: uppercase; color: #555; }
  .muted { color: #777; }
  .head { margin-bottom: 12px; border-bottom: 2px solid #0ca678; padding-bottom: 8px; }
  .totals span { display: inline-block; border: 1px solid #ddd; border-radius: 4px; padding: 4px 10px; margin-right: 6px; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #f1f3f5; text-align: left; padding: 5px 7px; border-bottom: 2px solid #ccc; }
  td { padding: 4px 7px; border-bottom: 1px solid #eee; }
  .bad { color: #c92a2a; } .warn { color: #e8590c; } .ok { color: #0ca678; }
  .right { text-align: right; }
  .foot { margin-top: 14px; font-size: 9px; color: #999; }
</style>
</head>
<body>
  <div class="head">
    <h1>Staff Report Summary — {{ $matrix['user']['name'] }}</h1>
    <div class="muted">{{ $matrix['month_label'] }} · {{ $tenant->name }}</div>
  </div>

  @php $t = $matrix['totals']; @endphp
  <div class="totals">
    <span>Daily: <b>{{ $t['daily_written'] }}/{{ $t['daily_expected'] }}</b></span>
    <span>Missing daily: <b>{{ $t['daily_missing'] }}</b></span>
    <span>Weekly: <b>{{ $t['weekly_covered'] }}/{{ $t['weekly_expected'] }}</b></span>
    <span>Late: <b>{{ $t['late'] }}</b></span>
    <span>Deductions: <b>TZS {{ number_format($t['deduction_total']) }}</b></span>
  </div>

  <h2>Daily Reports</h2>
  <table>
    <thead><tr><th>Date</th><th>Day</th><th>Status</th><th>Submitted</th><th class="right">Deduction</th></tr></thead>
    <tbody>
      @foreach ($matrix['daily'] as $d)
        <tr>
          <td>{{ \Carbon\Carbon::parse($d['date'])->format('d M Y') }}</td>
          <td>{{ $d['weekday'] }}</td>
          <td>
            @if ($d['status'] === 'submitted') <span class="ok">Submitted</span>
            @elseif ($d['status'] === 'late') <span class="warn">Late</span>
            @else <span class="bad">Missing</span>
            @endif
          </td>
          <td>{{ $d['submitted_at'] ?? '—' }}</td>
          <td class="right">{{ $d['deduction'] > 0 ? '−' . number_format($d['deduction']) : '—' }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  <h2>Weekly Reports</h2>
  <table>
    <thead><tr><th>Week</th><th>Status</th><th>Submitted</th><th class="right">Deduction</th></tr></thead>
    <tbody>
      @foreach ($matrix['weekly'] as $w)
        <tr>
          <td>{{ $w['week_label'] }}</td>
          <td>
            @if ($w['status'] === 'submitted') <span class="ok">Submitted</span>
            @elseif ($w['status'] === 'late') <span class="warn">Late</span>
            @elseif ($w['status'] === 'pending') Pending
            @else <span class="bad">Missing</span>
            @endif
          </td>
          <td>{{ $w['submitted_at'] ?? '—' }}</td>
          <td class="right">{{ $w['deduction'] > 0 ? '−' . number_format($w['deduction']) : '—' }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  <h2>Monthly Report</h2>
  <table>
    <thead><tr><th>Period</th><th>Status</th><th>Submitted</th><th class="right">Deduction</th></tr></thead>
    <tbody>
      <tr>
        <td>{{ $matrix['monthly']['label'] }}</td>
        <td>
          @if ($matrix['monthly']['status'] === 'submitted') <span class="ok">Submitted</span>
          @elseif ($matrix['monthly']['status'] === 'late') <span class="warn">Late</span>
          @elseif ($matrix['monthly']['status'] === 'pending') Pending
          @else <span class="bad">Missing</span>
          @endif
        </td>
        <td>{{ $matrix['monthly']['submitted_at'] ?? '—' }}</td>
        <td class="right">{{ $matrix['monthly']['deduction'] > 0 ? '−' . number_format($matrix['monthly']['deduction']) : '—' }}</td>
      </tr>
    </tbody>
  </table>

  <div class="foot">Generated {{ now()->format('d M Y H:i') }} · {{ config('app.name', 'MoBilling') }}</div>
</body>
</html>

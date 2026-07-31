<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { font-family: DejaVu Sans, sans-serif; font-size: 11px; color: #222; }
  h1 { font-size: 16px; margin: 0 0 2px; }
  .muted { color: #777; }
  .head { margin-bottom: 14px; border-bottom: 2px solid #0ca678; padding-bottom: 8px; }
  .totals { margin: 10px 0 14px; }
  .totals span { display: inline-block; border: 1px solid #ddd; border-radius: 4px; padding: 4px 10px; margin-right: 6px; }
  table.days { width: 100%; border-collapse: collapse; }
  table.days th { background: #f1f3f5; text-align: left; padding: 5px 7px; border-bottom: 2px solid #ccc; }
  table.days td { padding: 4px 7px; border-bottom: 1px solid #eee; }
  tr.off td { color: #aaa; }
  .bad { color: #c92a2a; }
  .warn { color: #e8590c; }
  .ok { color: #0ca678; }
  .right { text-align: right; }
  .foot { margin-top: 14px; font-size: 9px; color: #999; }
</style>
</head>
<body>
  <div class="head">
    <h1>Attendance Report — {{ $report['user']['name'] }}</h1>
    <div class="muted">{{ $report['month_label'] }} · Targets: in by {{ $report['check_in_time'] }}, out by {{ $report['check_out_time'] }} · {{ $tenant->name }}</div>
  </div>

  <div class="totals">
    <span>Present: <b>{{ $report['totals']['present'] }}</b></span>
    <span>Late: <b>{{ $report['totals']['late'] }}</b></span>
    <span>Left early: <b>{{ $report['totals']['left_early'] }}</b></span>
    <span>No check-out: <b>{{ $report['totals']['no_checkout'] }}</b></span>
    <span>Absent: <b>{{ $report['totals']['absent'] }}</b></span>
    <span>Excused: <b>{{ $report['totals']['excused'] }}</b></span>
    <span>Deductions: <b>TZS {{ number_format($report['totals']['deduction_total']) }}</b></span>
  </div>

  <table class="days">
    <thead>
      <tr><th>Date</th><th>Day</th><th>Check-in</th><th>Check-out</th><th>Status</th><th class="right">Deduction</th></tr>
    </thead>
    <tbody>
      @foreach ($report['days'] as $d)
        <tr class="{{ $d['working'] ? '' : 'off' }}">
          <td>{{ \Carbon\Carbon::parse($d['date'])->format('d M Y') }}</td>
          <td>{{ $d['weekday'] }}</td>
          <td>{{ $d['check_in_at'] ?? '—' }}</td>
          <td>{{ $d['check_out_at'] ?? '—' }}</td>
          <td>
            @if ($d['holiday']) Holiday
            @elseif (!$d['working']) Off day
            @elseif ($d['status']) {{ ['leave' => 'Ruhusa', 'sick' => 'Mgonjwa', 'field' => 'Kazi za nje'][$d['status']] ?? $d['status'] }}
            @elseif ($d['absent']) <span class="bad">Absent</span>
            @else
              @if ($d['late']) <span class="warn">Late</span> @endif
              @if ($d['left_early']) <span class="warn">Left early</span> @endif
              @if ($d['no_checkout']) <span class="warn">No check-out</span> @endif
              @if (!$d['late'] && !$d['left_early'] && !$d['no_checkout']) <span class="ok">Present</span> @endif
            @endif
          </td>
          <td class="right">{{ $d['deduction'] > 0 ? '−' . number_format($d['deduction']) : '—' }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  <div class="foot">Generated {{ now()->format('d M Y H:i') }} · {{ config('app.name', 'MoBilling') }}</div>
</body>
</html>

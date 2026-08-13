<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { font-family: DejaVu Sans, sans-serif; font-size: 11px; color: #222; }
  h1 { font-size: 16px; margin: 0 0 2px; }
  h2 { font-size: 12px; margin: 14px 0 5px; text-transform: uppercase; color: #555; }
  .muted { color: #777; }
  .head { margin-bottom: 12px; border-bottom: 2px solid #4263eb; padding-bottom: 8px; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #f1f3f5; text-align: left; padding: 5px 7px; border-bottom: 2px solid #ccc; }
  td { padding: 4px 7px; border-bottom: 1px solid #eee; }
  .badge { display: inline-block; border-radius: 3px; padding: 1px 6px; font-size: 9px; color: #fff; }
  .foot { margin-top: 14px; font-size: 9px; color: #999; }
  .disclaimer { margin: 10px 0; padding: 6px 8px; background: #fff9db; border: 1px solid #ffe066; font-size: 9px; }
</style>
</head>
<body>
  <div class="head">
    <h1>Upcoming Reminders — Next {{ $days }} Days</h1>
    <div class="muted">{{ $tenant->name }} · Generated {{ $generatedAt->format('d M Y H:i') }}</div>
  </div>

  <div class="disclaimer">
    Projected from current data — not a guarantee. A payment, cancellation, or setting change before the
    date arrives will change the outcome.
  </div>

  @if (count($events) === 0)
    <p class="muted">No reminders projected in this window.</p>
  @else
    @foreach (collect($events)->groupBy('date') as $date => $dayEvents)
      <h2>{{ \Carbon\Carbon::parse($date)->format('l, d M Y') }} ({{ count($dayEvents) }})</h2>
      <table>
        <thead><tr><th>Client</th><th>Type</th><th>Detail</th><th>Channels</th><th>Email</th><th>Phone</th></tr></thead>
        <tbody>
          @foreach ($dayEvents as $e)
            <tr>
              <td>{{ $e['client_name'] }}</td>
              <td>{{ str_replace('_', ' ', $e['category']) }}</td>
              <td>{{ $e['label'] }}</td>
              <td>{{ implode(', ', $e['channels']) ?: '—' }}</td>
              <td>{{ $e['recipient_email'] ?? '—' }}</td>
              <td>{{ $e['recipient_phone'] ?? '—' }}</td>
            </tr>
          @endforeach
        </tbody>
      </table>
    @endforeach
  @endif

  <div class="foot">Generated {{ $generatedAt->format('d M Y H:i') }} · {{ config('app.name', 'MoBilling') }}</div>
</body>
</html>

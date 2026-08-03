import classes from './DiskBar.module.css';

/**
 * cPanel disk-usage bar.
 *
 * Thresholds are the design's: green under 65%, amber 65–84%, red at 85%+.
 * The point is that a customer running out of space sees it before their site
 * breaks, so the colour has to change before it is urgent.
 */

/** cPanel reports "13486M" / "102400M"; "unlimited" and 0 mean no cap. */
function toMegabytes(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;

  const raw = String(value).trim().toLowerCase();
  if (!raw || raw === 'unlimited' || raw === 'null') return null;

  const match = raw.match(/^([\d.]+)\s*([kmgt])?/);
  if (!match) return null;

  const amount = parseFloat(match[1]);
  if (!Number.isFinite(amount)) return null;

  const scale: Record<string, number> = { k: 1 / 1024, m: 1, g: 1024, t: 1024 * 1024 };
  return amount * (scale[match[2] ?? 'm'] ?? 1);
}

const formatGb = (mb: number) =>
  mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : `${Math.round(mb)} MB`;

interface Props {
  used: string | number | null | undefined;
  limit: string | number | null | undefined;
}

export function DiskBar({ used, limit }: Props) {
  const usedMb = toMegabytes(used);
  const limitMb = toMegabytes(limit);

  // No figures yet, or an uncapped account — say so rather than drawing an
  // empty bar, which reads as "almost no usage".
  if (usedMb === null) {
    return <span className={classes.none}>Usage not synced</span>;
  }
  if (limitMb === null || limitMb <= 0) {
    return (
      <span className={classes.none}>
        <span className={classes.value}>{formatGb(usedMb)}</span> used · unlimited
      </span>
    );
  }

  const pct = Math.min(100, Math.round((usedMb / limitMb) * 100));
  const level = pct >= 85 ? classes.red : pct >= 65 ? classes.amber : classes.green;

  return (
    <div className={classes.wrap}>
      <div className={classes.figures}>
        <span className={classes.value}>
          {formatGb(usedMb)} / {formatGb(limitMb)}
        </span>
        <span className={`${classes.pct} ${level}`}>{pct}%</span>
      </div>
      <div
        className={classes.track}
        role="progressbar"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label="Disk usage"
      >
        <div className={`${classes.fill} ${level}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

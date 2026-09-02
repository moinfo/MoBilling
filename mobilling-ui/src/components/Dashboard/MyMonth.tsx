import { useState } from 'react';
import { Text, Badge, Button, Group, Box } from '@mantine/core';
import { IconReportAnalytics } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getMyAttendance } from '../../api/attendance';
import type { StaffPenaltiesSummary } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';
import { MyAttendanceChart, MyReportModal } from './MyAttendance';
import ReportDeductionsModal from './ReportDeductions';
import classes from './Dashboard.module.css';

const statusLabel: Record<string, string> = {
  leave: 'Ruhusa (leave)', sick: 'Mgonjwa (sick)', field: 'Kazi za nje (field)',
};

const dtypeLabel: Record<string, string> = {
  absent: 'Absent days', late: 'Late arrivals', left_early: 'Left early', no_checkout: 'No check-out',
};

/** One ledger line. `tone` is the only place colour is allowed in here. */
function Line(
  { label, value, tone, total }:
  { label: string; value: string; tone?: 'keep' | 'lost' | 'muted'; total?: boolean },
) {
  const c = tone === 'keep' ? 'teal.7' : tone === 'lost' ? 'red.7' : tone === 'muted' ? 'dimmed' : undefined;
  return (
    <dl className={`${classes.ledgerRow} ${total ? classes.ledgerTotal : ''}`}>
      <dt>{label}</dt>
      <dd><Text span inherit c={c}>{value}</Text></dd>
    </dl>
  );
}

/**
 * The logged-in staff member's current month, as one band instead of four
 * separate stat cards.
 *
 * The four cards this replaces (attendance / payroll / total deductions /
 * report deductions) had two problems beyond looking noisy. "Total deductions"
 * *contained* "report deductions", so the same money was presented twice as two
 * peer figures; and the payroll card showed the last finalized payslip (a past
 * month) directly beside deduction figures for the current month, with nothing
 * saying the periods differed. Here every pane states its own period, and the
 * last payslip is a separate card entirely (see MyPayroll) because it describes
 * a closed period, not this one.
 */
export default function MyMonth(
  { showAttendance, showDeductions, penalties }:
  { showAttendance: boolean; showDeductions: boolean; penalties?: StaffPenaltiesSummary | null },
) {
  const { data } = useQuery({ queryKey: ['my-attendance'], queryFn: getMyAttendance });
  const [reportOpen, setReportOpen] = useState(false);
  const [penaltiesOpen, setPenaltiesOpen] = useState(false);

  const a = data?.data?.data;
  if (!a && !penalties) return null;

  const t = a?.today;
  const s = a?.settings;

  const attendanceLost = Number(a?.deduction_total ?? 0);
  const reportsLost = Number(penalties?.month_total ?? 0);
  const lost = attendanceLost + reportsLost;
  const monthLabel = a?.month_label ?? penalties?.month_label ?? dayjs().format('MMM YYYY');

  const marked = !!t?.check_in_at;
  const statusText = t?.status
    ? (statusLabel[t.status] ?? t.status)
    : !marked ? 'Not marked yet'
    : t.late ? 'Present, late' : 'Present';
  const statusColor = t?.status ? 'grape' : !marked ? 'gray' : t.late ? 'orange' : 'teal';

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>Your month</Text>
      </div>

      <div className={classes.monthBand}>
        {/* ── Today: the only pane holding something to act on ────────────── */}
        {a && s && (
          <div className={classes.pane}>
            <div className={classes.paneLabel}>
              <span>Today</span>
              <span>{dayjs().format('ddd, D MMM')}</span>
            </div>

            <div className={classes.clockRow}>
              <div>
                <div className={classes.clockTime} style={{ color: t?.late ? 'var(--mantine-color-orange-7)' : undefined }}>
                  {t?.check_in_at ?? '—'}
                </div>
                <div className={classes.clockTarget}>in · by {s.check_in_time}</div>
              </div>
              <div>
                <div className={classes.clockTime} style={{ color: t?.left_early ? 'var(--mantine-color-orange-7)' : undefined }}>
                  {t?.check_out_at ?? '—'}
                </div>
                <div className={classes.clockTarget}>out · by {s.check_out_time}</div>
              </div>
            </div>

            {marked || t?.status ? (
              <Badge mt="sm" size="sm" variant="light" color={statusColor}>{statusText}</Badge>
            ) : (
              <div className={classes.unmarked}>
                You haven’t checked in yet. No check-in counts as absent
                {s.penalties_enabled ? ` (−${Number(s.penalty_absent).toLocaleString()})` : ''}.
              </div>
            )}

            {s.penalties_enabled && (
              <div className={classes.rules}>
                Missing a day costs {Number(s.penalty_absent).toLocaleString()} · late{' '}
                {Number(s.penalty_late).toLocaleString()} · leaving early{' '}
                {Number(s.penalty_left_early).toLocaleString()} · no check-out{' '}
                {Number(s.penalty_no_checkout).toLocaleString()}
              </div>
            )}
          </div>
        )}

        {/* ── The month's pattern ─────────────────────────────────────────── */}
        {showAttendance && a && (
          <div className={`${classes.pane} ${classes.paneWide}`}>
            <div className={classes.paneLabel}>
              <span>This month</span>
              <span>{monthLabel}</span>
            </div>

            <Group gap="lg" align="baseline">
              <div>
                <Text fw={500} ff="monospace" style={{ fontSize: 21, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>
                  {a.present_days}
                </Text>
                <Text size="xs" c="dimmed">day{a.present_days === 1 ? '' : 's'} present</Text>
              </div>
              {attendanceLost > 0 && (
                <div>
                  <Text fw={500} ff="monospace" c="red.7" style={{ fontSize: 21, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>
                    −{attendanceLost.toLocaleString()}
                  </Text>
                  <Text size="xs" c="dimmed">deducted so far</Text>
                </div>
              )}
            </Group>

            <MyAttendanceChart />

            <Button mt="sm" size="compact-xs" variant="default"
              leftSection={<IconReportAnalytics size={14} />} onClick={() => setReportOpen(true)}>
              Day-by-day report
            </Button>
          </div>
        )}

        {/* ── What it has cost, this month, still running ──────────────────── */}
        {showDeductions && (
          <div className={classes.pane}>
            <div className={classes.paneLabel}>
              <span>Deducted this month</span>
              <span>{monthLabel}</span>
            </div>

            <div className={classes.ledger}>
              <Line label="Attendance" value={attendanceLost > 0 ? `−${formatCurrency(attendanceLost)}` : '—'}
                tone={attendanceLost > 0 ? 'lost' : 'muted'} />
              <Line label="Reports" value={reportsLost > 0 ? `−${formatCurrency(reportsLost)}` : '—'}
                tone={reportsLost > 0 ? 'lost' : 'muted'} />

              <div className={classes.ledgerRule}>
                <Line total label="Total" value={lost > 0 ? `−${formatCurrency(lost)}` : formatCurrency(0)}
                  tone={lost > 0 ? 'lost' : 'keep'} />
              </div>
            </div>

            {lost > 0 ? (
              <>
                <p className={classes.ledgerNote}>Comes off your next payslip.</p>
                {penalties && penalties.items.length > 0 && (
                  <Button mt={4} size="compact-xs" variant="default"
                    onClick={() => setPenaltiesOpen(true)}>What was charged</Button>
                )}
              </>
            ) : (
              <p className={classes.ledgerNote}>
                Nothing lost so far this month. Check in on time and file each report before its
                deadline to keep it that way.
              </p>
            )}

            {/* Cause breakdown, only when there is something to explain. */}
            {attendanceLost > 0 && a?.deduction_by_type && (
              <Group gap={6} mt="sm">
                {(['absent', 'late', 'left_early', 'no_checkout'] as const).map((tp) =>
                  a.deduction_by_type![tp] > 0 ? (
                    <Badge key={tp} size="xs" variant="light" radius="sm"
                      color={tp === 'absent' ? 'red' : 'orange'}>
                      {dtypeLabel[tp]}: {a.deduction_by_type![tp]}
                    </Badge>
                  ) : null,
                )}
              </Group>
            )}
          </div>
        )}
      </div>

      <MyReportModal opened={reportOpen} onClose={() => setReportOpen(false)} />
      {penalties && (
        <ReportDeductionsModal data={penalties} opened={penaltiesOpen} onClose={() => setPenaltiesOpen(false)} />
      )}
    </Box>
  );
}

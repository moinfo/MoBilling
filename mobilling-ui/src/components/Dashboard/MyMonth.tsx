import { useState } from 'react';
import { Text, Badge, Button, Group, Box, Loader } from '@mantine/core';
import { MonthPickerInput } from '@mantine/dates';
import { IconReportAnalytics } from '@tabler/icons-react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getMyAttendance, getMyAttendanceReport } from '../../api/attendance';
import { getMyPenalties, type StaffPenaltiesSummary } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';
import { ChartSvg, MyReportModal } from './MyAttendance';
import ReportDeductionsModal from './ReportDeductions';
import classes from './Dashboard.module.css';

const statusLabel: Record<string, string> = {
  leave: 'Ruhusa (leave)', sick: 'Mgonjwa (sick)', field: 'Kazi za nje (field)',
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
 * The logged-in staff member's month, as one band instead of four peer cards.
 *
 * The four cards this replaces (attendance / payroll / total deductions /
 * report deductions) had two problems beyond looking noisy. "Total deductions"
 * *contained* "report deductions", so the same money appeared twice as two
 * equal figures; and the payroll card showed the last finalized payslip — a
 * closed month — beside deduction figures for the running one, with nothing
 * marking that the periods differed. Here the whole band is one period, every
 * pane names it, and the payslip is a separate card (MyPayroll) because it
 * describes a closed one.
 *
 * The month picker is carried over from the report-deductions card, where it
 * drove that one figure. Since this band sums attendance and report deductions
 * into a single total, the picker has to move both halves together — re-fetching
 * only one of them would produce a total belonging to no month at all.
 */
export default function MyMonth(
  { showAttendance, showDeductions, penalties }:
  { showAttendance: boolean; showDeductions: boolean; penalties?: StaffPenaltiesSummary | null },
) {
  const [reportOpen, setReportOpen] = useState(false);
  const [penaltiesOpen, setPenaltiesOpen] = useState(false);
  const [selectedMonth, setSelectedMonth] = useState<Date>(new Date());

  const safeDate = selectedMonth instanceof Date && !isNaN(selectedMonth.getTime()) ? selectedMonth : new Date();
  const month = safeDate.getMonth() + 1;
  const year = safeDate.getFullYear();
  const now = new Date();
  const isCurrentMonth = month === now.getMonth() + 1 && year === now.getFullYear();

  // Today's mark is today's, whichever month is being browsed.
  const { data: todayResp } = useQuery({ queryKey: ['my-attendance'], queryFn: getMyAttendance });
  const a = todayResp?.data?.data;

  // The selected month: attendance totals and the day-by-day strip.
  const { data: reportResp, isFetching: loadingReport } = useQuery({
    queryKey: ['my-attendance-report', month, year],
    queryFn: () => getMyAttendanceReport(month, year),
    placeholderData: keepPreviousData,
  });
  const r = reportResp?.data?.data;

  const { data: penResp } = useQuery({
    queryKey: ['my-penalties', month, year],
    queryFn: () => getMyPenalties(month, year),
    placeholderData: keepPreviousData,
  });
  // The dashboard's own payload already carries the current month, so it paints
  // instantly rather than waiting on this band's fetch.
  const pen = penResp?.data ?? (isCurrentMonth ? penalties ?? undefined : undefined);

  if (!a && !r && !pen) return null;

  const t = a?.today;
  const s = a?.settings;

  const attendanceLost = Number(r?.totals.deduction_total ?? 0);
  const reportsLost = Number(pen?.month_total ?? 0);
  const lost = attendanceLost + reportsLost;
  const monthLabel = r?.month_label ?? dayjs(safeDate).format('MMM YYYY');

  const marked = !!t?.check_in_at;
  const statusText = t?.status
    ? (statusLabel[t.status] ?? t.status)
    : !marked ? 'Not marked yet'
    : t.late ? 'Present, late' : 'Present';
  const statusColor = t?.status ? 'grape' : !marked ? 'gray' : t.late ? 'orange' : 'teal';

  const counts: [string, number][] = r ? [
    ['Absent', r.totals.absent],
    ['Late', r.totals.late],
    ['Left early', r.totals.left_early],
    ['No check-out', r.totals.no_checkout],
  ] : [];

  return (
    <Box>
      <Group justify="space-between" align="center" mb={12} wrap="nowrap">
        <div className={classes.sectionLabel} style={{ flex: 1 }}>
          <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>Your month</Text>
        </div>
        <MonthPickerInput
          value={selectedMonth}
          onChange={(val) => {
            if (!val) return;
            try {
              const d = new Date(val as any);
              if (!isNaN(d.getTime())) setSelectedMonth(d);
            } catch { /* ignore */ }
          }}
          maxDate={now}
          maxLevel="decade"
          w={150}
          size="xs"
          aria-label="Month to show"
        />
      </Group>

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

        {/* ── The selected month's pattern ─────────────────────────────────── */}
        {showAttendance && (
          <div className={`${classes.pane} ${classes.paneWide}`}>
            <div className={classes.paneLabel}>
              <span>Attendance</span>
              <span>{monthLabel}</span>
            </div>

            {r ? (
              <>
                <Group gap="lg" align="baseline">
                  <div>
                    <Text fw={500} ff="monospace" style={{ fontSize: 21, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>
                      {r.totals.present}
                    </Text>
                    <Text size="xs" c="dimmed">day{r.totals.present === 1 ? '' : 's'} present</Text>
                  </div>
                  {attendanceLost > 0 && (
                    <div>
                      <Text fw={500} ff="monospace" c="red.7" style={{ fontSize: 21, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>
                        −{attendanceLost.toLocaleString()}
                      </Text>
                      <Text size="xs" c="dimmed">deducted</Text>
                    </div>
                  )}
                </Group>

                <ChartSvg r={r} />

                {counts.some(([, n]) => n > 0) && (
                  <Group gap={6} mt="xs">
                    {counts.map(([label, n]) => n > 0 ? (
                      <Badge key={label} size="xs" variant="light" radius="sm"
                        color={label === 'Absent' ? 'red' : 'orange'}>
                        {label}: {n}
                      </Badge>
                    ) : null)}
                  </Group>
                )}

                <Button mt="sm" size="compact-xs" variant="default"
                  leftSection={<IconReportAnalytics size={14} />} onClick={() => setReportOpen(true)}>
                  Day-by-day report
                </Button>
              </>
            ) : loadingReport ? (
              <Loader size="sm" mt="sm" />
            ) : (
              <Text size="sm" c="dimmed" mt="sm">No attendance recorded for {monthLabel}.</Text>
            )}
          </div>
        )}

        {/* ── What the month has cost ─────────────────────────────────────── */}
        {showDeductions && (
          <div className={classes.pane}>
            <div className={classes.paneLabel}>
              <span>Deducted</span>
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
                <p className={classes.ledgerNote}>
                  {isCurrentMonth ? 'Comes off your next payslip.' : `Came off your ${monthLabel} pay.`}
                </p>
                {pen && pen.items.length > 0 && (
                  <Button mt={4} size="compact-xs" variant="default"
                    onClick={() => setPenaltiesOpen(true)}>What was charged</Button>
                )}
              </>
            ) : (
              <p className={classes.ledgerNote}>
                {isCurrentMonth
                  ? 'Nothing lost so far this month. Check in on time and file each report before its deadline to keep it that way.'
                  : `Nothing was deducted in ${monthLabel}.`}
              </p>
            )}
          </div>
        )}
      </div>

      <MyReportModal opened={reportOpen} onClose={() => setReportOpen(false)} />
      {pen && (
        <ReportDeductionsModal data={pen} opened={penaltiesOpen} onClose={() => setPenaltiesOpen(false)} />
      )}
    </Box>
  );
}

import { useState } from 'react';
import { Card, Group, Text, Badge, ThemeIcon, Box, Stack, Button, Modal, Table, Center, Loader } from '@mantine/core';
import { MonthPickerInput } from '@mantine/dates';
import { IconLogin2, IconLogout2, IconClockHour4, IconReceiptOff, IconReportAnalytics } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getMyAttendance, getMyAttendanceReport, AttendanceReport } from '../../api/attendance';
import classes from './Dashboard.module.css';

const statusLabelFull: Record<string, string> = {
  leave: 'Ruhusa', sick: 'Mgonjwa', field: 'Kazi za nje',
};

function MyReportModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const [month, setMonth] = useState<Date>(new Date());
  const m = month.getMonth() + 1;
  const y = month.getFullYear();
  const { data, isLoading } = useQuery({
    queryKey: ['my-attendance-report', m, y],
    queryFn: () => getMyAttendanceReport(m, y),
    enabled: opened,
  });
  const r: AttendanceReport | undefined = data?.data?.data;

  return (
    <Modal opened={opened} onClose={onClose} size="lg" title="My Attendance Report">
      <Stack gap="sm">
        <Group justify="space-between" wrap="wrap">
          <MonthPickerInput value={month} maxDate={new Date()} w={160} size="sm"
            onChange={(v) => v && setMonth(new Date(v as unknown as string))} />
          {r && (
            <Badge size="lg" variant="filled" color={r.totals.deduction_total > 0 ? 'red' : 'gray'}>
              Deductions: TZS {r.totals.deduction_total.toLocaleString()}
            </Badge>
          )}
        </Group>
        {r && (
          <Group gap={6} wrap="wrap">
            <Badge variant="light" color="teal">Present: {r.totals.present}</Badge>
            <Badge variant="light" color="orange">Late: {r.totals.late}</Badge>
            <Badge variant="light" color="yellow">No check-out: {r.totals.no_checkout}</Badge>
            <Badge variant="light" color="red">Absent: {r.totals.absent}</Badge>
            {r.totals.excused > 0 && <Badge variant="light" color="grape">Excused: {r.totals.excused}</Badge>}
          </Group>
        )}
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : r && (
          <Table.ScrollContainer minWidth={480}>
            <Table highlightOnHover verticalSpacing={4} fz="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th ta="center">In</Table.Th>
                  <Table.Th ta="center">Out</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th ta="right">Deduction</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {r.days.map((d) => (
                  <Table.Tr key={d.date} style={{ opacity: d.working ? 1 : 0.5 }}>
                    <Table.Td fw={500}>{dayjs(d.date).format('DD MMM')} <Text span size="xs" c="dimmed">{d.weekday}</Text></Table.Td>
                    <Table.Td ta="center" fw={600} c={d.check_in_at ? (d.late ? 'orange' : undefined) : 'dimmed'}>{d.check_in_at ?? '—'}</Table.Td>
                    <Table.Td ta="center" fw={600} c={d.check_out_at ? (d.left_early ? 'orange' : undefined) : 'dimmed'}>{d.check_out_at ?? '—'}</Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        {!d.working && !d.holiday && <Badge size="xs" variant="light" color="gray">off</Badge>}
                        {d.holiday && <Badge size="xs" variant="light" color="cyan">holiday</Badge>}
                        {d.status && <Badge size="xs" variant="light" color="grape">{statusLabelFull[d.status] ?? d.status}</Badge>}
                        {d.absent && <Badge size="xs" variant="light" color="red">absent</Badge>}
                        {d.late && <Badge size="xs" variant="light" color="orange">late</Badge>}
                        {d.left_early && <Badge size="xs" variant="light" color="orange">early</Badge>}
                        {d.no_checkout && <Badge size="xs" variant="light" color="yellow">no out</Badge>}
                        {d.check_in_at && !d.late && !d.left_early && !d.no_checkout && !d.status && (
                          <Badge size="xs" variant="light" color="teal">present</Badge>
                        )}
                      </Group>
                    </Table.Td>
                    <Table.Td ta="right" fw={600} c={d.deduction > 0 ? 'red' : 'dimmed'}>
                      {d.deduction > 0 ? `−${d.deduction.toLocaleString()}` : '—'}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Stack>
    </Modal>
  );
}


/** Month chart: one thin bar per day from check-in to check-out (time of day,
 *  morning at top), dashed target lines, ✖ = absent, violet band = excused. */
const CHART = {
  ok: '#099268', warn: '#e8590c', excused: '#6741d9', absent: '#c92a2a',
};

function MyAttendanceChart() {
  const now = new Date();
  const m = now.getMonth() + 1;
  const y = now.getFullYear();
  const { data } = useQuery({
    queryKey: ['my-attendance-report', m, y],
    queryFn: () => getMyAttendanceReport(m, y),
  });
  const [hover, setHover] = useState<number | null>(null);
  const r: AttendanceReport | undefined = data?.data?.data;
  if (!r || r.days.length === 0) return null;

  const toMin = (t: string | null) => {
    if (!t) return null;
    const [h, mm] = t.split(':').map(Number);
    return h * 60 + mm;
  };
  const DOM_MIN = 6 * 60, DOM_MAX = 22 * 60;           // 06:00 → 22:00
  const ML = 36, MR = 6, MT = 6, MB = 16, H = 84;
  const dayW = 14, barW = 7;
  const W = ML + MR + r.days.length * dayW;
  const yPos = (min: number) => MT + ((Math.min(Math.max(min, DOM_MIN), DOM_MAX) - DOM_MIN) / (DOM_MAX - DOM_MIN)) * H;
  const inTarget = yPos(toMin(r.check_in_time) ?? 450);
  const outTarget = yPos(toMin(r.check_out_time) ?? 1020);
  const hovered = hover !== null ? r.days[hover] : null;

  return (
    <div style={{ position: 'relative', marginTop: 10, maxWidth: 520 }}>
      <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={4}>Check-in / check-out · {r.month_label}</Text>
      <svg viewBox={`0 0 ${W} ${MT + H + MB}`} style={{ width: '100%', display: 'block' }} role="img"
        aria-label={`Daily check-in and check-out times for ${r.month_label}`}>
        {/* target lines */}
        {[[inTarget, r.check_in_time], [outTarget, r.check_out_time]].map(([yy, label]) => (
          <g key={String(label)}>
            <line x1={ML} x2={W - MR} y1={yy as number} y2={yy as number}
              stroke="var(--mantine-color-default-border)" strokeDasharray="3 3" strokeWidth={1} />
            <text x={ML - 4} y={(yy as number) + 3} textAnchor="end" fontSize={8}
              fill="var(--mantine-color-dimmed)">{label}</text>
          </g>
        ))}
        {r.days.map((d, i) => {
          const cx = ML + i * dayW + dayW / 2;
          const inM = toMin(d.check_in_at);
          const outM = toMin(d.check_out_at);
          const violation = d.late || d.left_early || d.no_checkout;
          const color = violation ? CHART.warn : CHART.ok;
          return (
            <g key={d.date} opacity={d.working || inM !== null ? 1 : 0.35}>
              {/* excused band */}
              {d.status && (
                <rect x={cx - barW / 2} y={inTarget} width={barW} height={outTarget - inTarget}
                  rx={3.5} fill={CHART.excused} opacity={0.45} />
              )}
              {/* presence bar: check-in → check-out (or short stub if no out) */}
              {inM !== null && (
                <rect x={cx - barW / 2} y={yPos(inM)} width={barW}
                  height={Math.max((outM !== null ? yPos(outM) : yPos(inM) + 10) - yPos(inM), 6)}
                  rx={3.5} fill={color}
                  stroke={d.no_checkout ? color : 'none'} strokeDasharray={d.no_checkout ? '2 2' : undefined}
                  fillOpacity={d.no_checkout ? 0.45 : 1} />
              )}
              {/* absent marker */}
              {d.absent && (
                <text x={cx} y={inTarget + 3.5} textAnchor="middle" fontSize={9} fontWeight={700}
                  fill={CHART.absent}>✕</text>
              )}
              {/* day label every other day */}
              {i % 2 === 0 && (
                <text x={cx} y={MT + H + 11} textAnchor="middle" fontSize={7}
                  fill="var(--mantine-color-dimmed)">{dayjs(d.date).format('D')}</text>
              )}
              {/* hover hit target (full column) */}
              <rect x={ML + i * dayW} y={0} width={dayW} height={MT + H + MB} fill="transparent"
                onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)} />
              {hover === i && (
                <rect x={ML + i * dayW} y={MT} width={dayW} height={H} fill="var(--mantine-color-dimmed)" opacity={0.08} />
              )}
            </g>
          );
        })}
      </svg>

      {hovered && (
        <div style={{
          position: 'absolute', top: 18, left: `${((ML + (hover ?? 0) * dayW) / W) * 100}%`,
          transform: (hover ?? 0) > r.days.length / 2 ? 'translateX(-100%)' : undefined,
          background: 'var(--mantine-color-body)', border: '1px solid var(--mantine-color-default-border)',
          borderRadius: 6, padding: '6px 8px', pointerEvents: 'none', zIndex: 5, boxShadow: '0 2px 8px rgba(0,0,0,.12)',
        }}>
          <Text size="xs" fw={700}>{dayjs(hovered.date).format('ddd, D MMM')}</Text>
          <Text size="xs">In: {hovered.check_in_at ?? '—'} · Out: {hovered.check_out_at ?? '—'}</Text>
          <Text size="xs" c="dimmed">
            {hovered.status ? (statusLabelFull[hovered.status] ?? hovered.status)
              : hovered.absent ? 'Absent' : hovered.holiday ? 'Holiday' : !hovered.working ? 'Off day'
              : [hovered.late && 'Late', hovered.left_early && 'Left early', hovered.no_checkout && 'No check-out'].filter(Boolean).join(' · ') || 'Present'}
            {hovered.deduction > 0 ? ` · −TZS ${hovered.deduction.toLocaleString()}` : ''}
          </Text>
        </div>
      )}

      <Group gap={10} mt={2} wrap="wrap">
        {[[CHART.ok, 'On time'], [CHART.warn, 'Late / early / no out'], [CHART.excused, 'Excused'], [CHART.absent, '✕ Absent']].map(([c, l]) => (
          <Group key={l} gap={4} wrap="nowrap">
            <span style={{ width: 8, height: 8, borderRadius: 2, background: l === '✕ Absent' ? 'transparent' : c, color: c, fontSize: 9, fontWeight: 700, lineHeight: '8px' }}>
              {l === '✕ Absent' ? '✕' : ''}
            </span>
            <Text size="xs" c="dimmed">{l}</Text>
          </Group>
        ))}
      </Group>
    </div>
  );
}

const dtypeLabel: Record<string, string> = {
  absent: 'Absent', late: 'Late', left_early: 'Left early', no_checkout: 'No check-out',
};

const statusLabel: Record<string, string> = {
  leave: 'Ruhusa (leave)', sick: 'Mgonjwa (sick)', field: 'Kazi za nje (field)',
};

export default function MyAttendance() {
  const { data } = useQuery({ queryKey: ['my-attendance'], queryFn: getMyAttendance });
  const [reportOpen, setReportOpen] = useState(false);
  const a = data?.data?.data;

  if (!a) return null;
  const t = a.today;
  const s = a.settings;

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>My Attendance</Text>
      </div>

      <Card withBorder radius="md" p="md" shadow="xs" className={classes.statCard}
        style={{ ['--stat-accent' as string]: 'var(--mantine-color-blue-6)' }}>
        <Group justify="space-between" wrap="wrap" gap="md">
          <Group gap="lg" wrap="wrap">
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={700}>Today · {dayjs().format('ddd, D MMM')}</Text>
              <Group gap="lg" mt={4}>
                <Group gap={6}>
                  <ThemeIcon size={30} radius="md" variant="light" color={t?.check_in_at ? (t.late ? 'orange' : 'teal') : 'gray'}>
                    <IconLogin2 size={16} />
                  </ThemeIcon>
                  <div>
                    <Text size="sm" fw={700}>{t?.check_in_at ?? '—'}</Text>
                    <Text size="xs" c="dimmed">in · target {s.check_in_time}</Text>
                  </div>
                  {t?.late && <Badge size="xs" color="orange" variant="light">late</Badge>}
                </Group>
                <Group gap={6}>
                  <ThemeIcon size={30} radius="md" variant="light" color={t?.check_out_at ? (t.left_early ? 'orange' : 'teal') : 'gray'}>
                    <IconLogout2 size={16} />
                  </ThemeIcon>
                  <div>
                    <Text size="sm" fw={700}>{t?.check_out_at ?? '—'}</Text>
                    <Text size="xs" c="dimmed">out · target {s.check_out_time}</Text>
                  </div>
                  {t?.left_early && <Badge size="xs" color="orange" variant="light">early</Badge>}
                </Group>
              </Group>
            </div>

            <Badge size="lg" variant="light"
              color={t?.status ? 'grape' : !t?.check_in_at ? 'gray' : t.late ? 'orange' : 'teal'}>
              {t?.status ? (statusLabel[t.status] ?? t.status) : !t?.check_in_at ? 'Not marked yet' : t.late ? 'Present (late)' : 'Present'}
            </Badge>
          </Group>

          <Stack gap={2} align="flex-end">
            <Button size="compact-xs" variant="light" leftSection={<IconReportAnalytics size={14} />}
              onClick={() => setReportOpen(true)}>
              Full report
            </Button>
            <Group gap={6}>
              <IconClockHour4 size={14} />
              <Text size="sm">{a.present_days} day{a.present_days === 1 ? '' : 's'} present · {a.month_label}</Text>
            </Group>
            {s.penalties_enabled && a.deduction_total > 0 && (
              <Group gap={6}>
                <IconReceiptOff size={14} color="var(--mantine-color-red-6)" />
                <Text size="sm" c="red" fw={600}>−TZS {a.deduction_total.toLocaleString()} deducted</Text>
              </Group>
            )}
          </Stack>
        </Group>

        {s.penalties_enabled && a.deduction_total > 0 && a.deduction_by_type && (
          <Group gap={6} mt="sm">
            {(['absent', 'late', 'left_early', 'no_checkout'] as const).map((tp) =>
              a.deduction_by_type![tp] > 0 ? (
                <Badge key={tp} variant="light" color={tp === 'absent' ? 'red' : 'orange'} radius="sm">
                  {dtypeLabel[tp]}: {a.deduction_by_type![tp]}
                </Badge>
              ) : null,
            )}
          </Group>
        )}

        <MyAttendanceChart />

        {/* Rules & deduction amounts — so staff know what applies */}
        <Stack gap={4} mt="sm" pt="sm" style={{ borderTop: '1px solid var(--mantine-color-default-border)' }}>
          <Text size="xs" c="dimmed">
            <b>Rules:</b> check in by <b>{s.check_in_time}</b>, check out by <b>{s.check_out_time}</b>. A missing check-in counts as absent even if you check out.
          </Text>
          {s.penalties_enabled && (
            <Group gap={6}>
              {([['absent', s.penalty_absent], ['late', s.penalty_late], ['left_early', s.penalty_left_early], ['no_checkout', s.penalty_no_checkout]] as const).map(([tp, amt]) => (
                <Badge key={tp} variant="outline" color="gray" radius="sm" size="sm">
                  {dtypeLabel[tp]} −TZS {Number(amt).toLocaleString()}
                </Badge>
              ))}
            </Group>
          )}
        </Stack>
      </Card>

      <MyReportModal opened={reportOpen} onClose={() => setReportOpen(false)} />
    </Box>
  );
}

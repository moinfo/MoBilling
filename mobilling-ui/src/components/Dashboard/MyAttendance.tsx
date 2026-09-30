import { useState } from 'react';
import { Group, Text, Badge, Stack, Modal, Table, Center, Loader, ActionIcon, Tooltip, Select, Textarea, Button } from '@mantine/core';
import { MonthPickerInput } from '@mantine/dates';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconMessageCircle } from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getMyAttendanceReport, AttendanceReport, ReportDay,
  getAttendanceExceptions, submitAttendanceException, AttendanceExceptionRequest,
} from '../../api/attendance';
import { useAuth } from '../../context/AuthContext';

const statusLabelFull: Record<string, string> = {
  leave: 'Ruhusa', sick: 'Mgonjwa', field: 'Kazi za nje',
};
const exceptionTypeLabel: Record<string, string> = { leave: 'Ruhusa', field: 'Kazi za nje', other: 'Nyingine' };
const exceptionIconColor: Record<string, string> = { pending: 'yellow', approved: 'teal', rejected: 'red' };

export function MyReportModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const { user } = useAuth();
  const [month, setMonth] = useState<Date>(new Date());
  const [explainDay, setExplainDay] = useState<ReportDay | null>(null);
  const m = month.getMonth() + 1;
  const y = month.getFullYear();
  const { data, isLoading } = useQuery({
    queryKey: ['my-attendance-report', m, y],
    queryFn: () => getMyAttendanceReport(m, y),
    enabled: opened,
  });
  const r: AttendanceReport | undefined = data?.data?.data;

  const { data: excRes } = useQuery({
    queryKey: ['my-attendance-exceptions', user?.id],
    queryFn: () => getAttendanceExceptions({ user_id: user!.id }),
    enabled: opened && !!user,
  });
  const exceptionsByDate = new Map<string, AttendanceExceptionRequest>(
    (excRes?.data?.data ?? []).map((e) => [e.date, e])
  );

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
          <>
          <ChartSvg r={r} full />
          <Table.ScrollContainer minWidth={480}>
            <Table highlightOnHover verticalSpacing={4} fz="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th ta="center">In</Table.Th>
                  <Table.Th ta="center">Out</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th ta="right">Deduction</Table.Th>
                  <Table.Th w={36} />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {r.days.map((d) => {
                  const flagged = d.working && !d.status && (d.absent || d.late || d.no_checkout || d.left_early);
                  const exception = exceptionsByDate.get(d.date);
                  return (
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
                    <Table.Td>
                      {exception ? (
                        <Tooltip multiline w={240} label={
                          `${exceptionTypeLabel[exception.type] ?? exception.type}: "${exception.comment}" — `
                          + (exception.status === 'pending' ? 'inasubiri idhini (pending)'
                            : exception.status === 'approved' ? 'imeidhinishwa (approved)'
                            : `imekataliwa (rejected)${exception.review_note ? ' — ' + exception.review_note : ''}`)
                        }>
                          <ActionIcon variant="subtle" color={exceptionIconColor[exception.status]} size="sm">
                            <IconMessageCircle size={14} />
                          </ActionIcon>
                        </Tooltip>
                      ) : flagged && d.explainable ? (
                        <Tooltip label="Explain this day — request approval">
                          <ActionIcon variant="subtle" color="gray" size="sm" onClick={() => setExplainDay(d)}>
                            <IconMessageCircle size={14} />
                          </ActionIcon>
                        </Tooltip>
                      ) : flagged ? (
                        <Tooltip label="Dirisha la kueleza siku hii limefungwa au bado halijafunguka">
                          <ActionIcon variant="subtle" color="gray" size="sm" style={{ cursor: 'default' }}>
                            <IconMessageCircle size={14} style={{ opacity: 0.35 }} />
                          </ActionIcon>
                        </Tooltip>
                      ) : null}
                    </Table.Td>
                  </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
          </>
        )}
      </Stack>
      <ExplainDayModal day={explainDay} onClose={() => setExplainDay(null)} />
    </Modal>
  );
}

function ExplainDayModal({ day, onClose }: { day: ReportDay | null; onClose: () => void }) {
  const qc = useQueryClient();
  const [type, setType] = useState<'leave' | 'field' | 'other' | null>(null);
  const [comment, setComment] = useState('');

  const submitMut = useMutation({
    mutationFn: () => submitAttendanceException({ date: day!.date, type: type!, comment: comment.trim() }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['my-attendance-exceptions'] });
      notifications.show({ message: 'Sent — waiting for approval.', color: 'green' });
      setType(null); setComment(''); onClose();
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Failed to send.', color: 'red' }),
  });

  return (
    <Modal opened={!!day} onClose={onClose} title={day ? `Explain ${dayjs(day.date).format('ddd, D MMM YYYY')}` : ''} size="sm">
      <Stack gap="sm">
        <Select label="What happened" placeholder="Chagua" data={[
          { value: 'leave', label: 'Nilikuwa na ruhusa (I had permission)' },
          { value: 'field', label: 'Nilikuwa nje ya kazi (I was out of office)' },
          { value: 'other', label: 'Nyingine (eleza mwenyewe)' },
        ]} value={type} onChange={(v) => setType(v as 'leave' | 'field' | 'other' | null)} />
        <Textarea label="Comment" placeholder="Eleza kwa ufupi..." minRows={3} required
          value={comment} onChange={(e) => setComment(e.currentTarget.value)} />
        {type === 'other' && (
          <Text size="xs" c="dimmed">Msimamizi wako ndiye ataamua kama siku hii itakatwa au la, baada ya kusoma maelezo yako.</Text>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button disabled={!type || !comment.trim()} loading={submitMut.isPending} onClick={() => submitMut.mutate()}>
            Send for approval
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}


/** Month chart: one thin bar per day from check-in to check-out (time of day,
 *  morning at top), dashed target lines, ✖ = absent, violet band = excused. */
const CHART = {
  ok: '#099268', warn: '#e8590c', excused: '#6741d9', absent: '#c92a2a',
};

export function ChartSvg({ r, full = false }: { r: AttendanceReport; full?: boolean }) {
  const [hover, setHover] = useState<number | null>(null);
  if (r.days.length === 0) return null;

  const toMin = (t: string | null) => {
    if (!t) return null;
    const [h, mm] = t.split(':').map(Number);
    return h * 60 + mm;
  };
  const DOM_MIN = 6 * 60, DOM_MAX = 22 * 60;           // 06:00 → 22:00
  // Compact (dashboard): a slim colour strip with no axis text at all — the
  // time/day labels are what made the card tall. Full (report modal): labelled.
  const ML = full ? 32 : 4, MR = 4, MT = full ? 4 : 2, MB = full ? 13 : 3, H = full ? 64 : 26;
  const dayW = full ? 12 : 8, barW = full ? 6 : 4.5;
  const xr = full ? 2.2 : 1.4;                          // absent-cross half-size
  // Always lay the grid out over the WHOLE month, not just the days reported so
  // far. The API stops at today (attendance report: "don't report days that
  // haven't happened"), so on the 2nd of a month days.length is 2 — and since
  // the svg scales to its width by viewBox ratio, a 24x31 box stretched to
  // 340px rendered ~440px tall: a near-empty card the height of a chart. Padding
  // the column count to the full month keeps the aspect ratio (and so the
  // rendered height) stable all month, and reads correctly: the remaining days
  // are simply blank, with the target lines running on across them.
  const cols = Math.max(r.days.length, dayjs(r.days[0].date).daysInMonth());
  const W = ML + MR + cols * dayW;
  const yPos = (min: number) => MT + ((Math.min(Math.max(min, DOM_MIN), DOM_MAX) - DOM_MIN) / (DOM_MAX - DOM_MIN)) * H;
  const inTarget = yPos(toMin(r.check_in_time) ?? 450);
  const outTarget = yPos(toMin(r.check_out_time) ?? 1020);
  const hovered = hover !== null ? r.days[hover] : null;

  return (
    <div style={{ position: 'relative', marginTop: full ? 4 : 8, maxWidth: full ? 560 : undefined }}>
      {!full && (
        <Text size="xs" c="dimmed" mb={4}>Check-in to check-out, each day of {r.month_label}</Text>
      )}
      <svg viewBox={`0 0 ${W} ${MT + H + MB}`} style={{ width: '100%', display: 'block' }} role="img"
        aria-label={`Daily check-in and check-out times for ${r.month_label}`}>
        {/* target lines */}
        {[[inTarget, r.check_in_time], [outTarget, r.check_out_time]].map(([yy, label]) => (
          <g key={String(label)}>
            <line x1={ML} x2={W - MR} y1={yy as number} y2={yy as number}
              stroke="var(--mantine-color-default-border)" strokeDasharray="3 3" strokeWidth={1} />
            {full && (
              <text x={ML - 4} y={(yy as number) + 2.5} textAnchor="end" fontSize={7}
                fill="var(--mantine-color-dimmed)">{label}</text>
            )}
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
              {/* absent marker: drawn cross (a text glyph renders inconsistently) */}
              {d.absent && (
                <g stroke={CHART.absent} strokeWidth={full ? 1.3 : 0.9} strokeLinecap="round">
                  <line x1={cx - xr} y1={inTarget - xr} x2={cx + xr} y2={inTarget + xr} />
                  <line x1={cx - xr} y1={inTarget + xr} x2={cx + xr} y2={inTarget - xr} />
                </g>
              )}
              {/* day label every 5th day (full chart only) */}
              {full && (i % 5 === 0 || i === r.days.length - 1) && (
                <text x={cx} y={MT + H + 9} textAnchor="middle" fontSize={6}
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
        {[[CHART.ok, 'On time'], [CHART.warn, 'Late / early / no out'], [CHART.excused, 'Excused']].map(([c, l]) => (
          <Group key={l} gap={4} wrap="nowrap">
            <span style={{ width: 8, height: 8, borderRadius: 2, background: c, flexShrink: 0 }} />
            <Text size="xs" c="dimmed">{l}</Text>
          </Group>
        ))}
        <Group gap={4} wrap="nowrap">
          <svg width={7} height={7} style={{ flexShrink: 0 }}>
            <g stroke={CHART.absent} strokeWidth={1.2} strokeLinecap="round">
              <line x1={1.5} y1={1.5} x2={5.5} y2={5.5} />
              <line x1={1.5} y1={5.5} x2={5.5} y2={1.5} />
            </g>
          </svg>
          <Text size="xs" c="dimmed">Absent</Text>
        </Group>
      </Group>
    </div>
  );
}

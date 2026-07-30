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

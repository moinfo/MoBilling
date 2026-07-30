import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Text, Paper, Table, Badge, Button, ActionIcon,
  Loader, Center, ThemeIcon, NumberInput, Switch, Chip, SimpleGrid, Divider, Alert, Select, Menu,
} from '@mantine/core';
import { DatePickerInput, TimeInput, MonthPickerInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconClipboardCheck, IconSettings, IconDeviceFloppy, IconClock, IconAlertTriangle, IconReceiptOff, IconChartBar, IconUserCheck, IconUserOff, IconLogout2, IconDeviceDesktop, IconCopy, IconCheck, IconRefresh, IconCalendarOff, IconDotsVertical } from '@tabler/icons-react';
import { Drawer, Text as MText, Card, SimpleGrid as MGrid, Code, CopyButton, Tooltip, Collapse, TextInput, FileButton, SegmentedControl } from '@mantine/core';
import { IconUpload, IconFileSpreadsheet } from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getAttendanceDay, recordAttendance, getAttendanceSettings, updateAttendanceSettings,
  getAttendancePenalties, waiveAttendancePenalty, unwaiveAttendancePenalty, getAttendanceDashboard,
  getDeviceConfig, getDeviceEvents, regenerateDeviceToken,
  getDeviceMappings, saveDeviceMapping, importDeviceEvents,
  previewAttendanceSheet, commitAttendanceSheet, getAttendanceReport,
  AttendanceSettings, ExcusedStatus, DeviceMappingStaff, SheetMapping, SheetPreview, SheetImportResult, AttendanceReport,
} from '../api/attendance';

export default function Attendance() {
  return (
    <Stack>
      <Title order={2}>Attendance</Title>
      <Tabs defaultValue="dashboard" keepMounted={false}>
        <Tabs.List>
          <Tabs.Tab value="dashboard" leftSection={<IconChartBar size={15} />}>Dashboard</Tabs.Tab>
          <Tabs.Tab value="record" leftSection={<IconClipboardCheck size={15} />}>Record</Tabs.Tab>
          <Tabs.Tab value="deductions" leftSection={<IconReceiptOff size={15} />}>Deductions</Tabs.Tab>
          <Tabs.Tab value="report" leftSection={<IconClipboardCheck size={15} />}>Report</Tabs.Tab>
          <Tabs.Tab value="import" leftSection={<IconFileSpreadsheet size={15} />}>Import (iVMS)</Tabs.Tab>
          <Tabs.Tab value="device" leftSection={<IconDeviceDesktop size={15} />}>Device</Tabs.Tab>
          <Tabs.Tab value="settings" leftSection={<IconSettings size={15} />}>Settings</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="dashboard" pt="md"><DashboardTab /></Tabs.Panel>
        <Tabs.Panel value="record" pt="md"><RecordTab /></Tabs.Panel>
        <Tabs.Panel value="deductions" pt="md"><DeductionsTab /></Tabs.Panel>
        <Tabs.Panel value="report" pt="md"><ReportTab /></Tabs.Panel>
        <Tabs.Panel value="import" pt="md"><ImportTab /></Tabs.Panel>
        <Tabs.Panel value="device" pt="md"><DeviceTab /></Tabs.Panel>
        <Tabs.Panel value="settings" pt="md"><SettingsTab /></Tabs.Panel>
      </Tabs>
    </Stack>
  );
}

function apiErr(e: unknown, fallback: string): string {
  return (e as { response?: { data?: { message?: string } } })?.response?.data?.message ?? fallback;
}

function StatCard({ label, value, sub, color, icon }: { label: string; value: number | string; sub?: string; color: string; icon: React.ReactNode }) {
  return (
    <Card withBorder radius="md" p="sm">
      <Group gap="sm" wrap="nowrap">
        <ThemeIcon variant="light" color={color} size={40} radius="md">{icon}</ThemeIcon>
        <div style={{ minWidth: 0 }}>
          <Text size="xl" fw={800} lh={1.1}>{value}</Text>
          <Text size="xs" c="dimmed" truncate>{label}</Text>
          {sub && <Text size="xs" c={color}>{sub}</Text>}
        </div>
      </Group>
    </Card>
  );
}

function DashboardTab() {
  const { data, isLoading } = useQuery({ queryKey: ['attendance-dashboard'], queryFn: getAttendanceDashboard });
  const d = data?.data?.data;
  if (isLoading) return <Center py="xl"><Loader /></Center>;
  if (!d) return null;

  return (
    <Stack gap="lg">
      <div>
        <Text size="sm" fw={700} tt="uppercase" c="dimmed" mb="xs">Today · {dayjs().format('ddd, D MMM')}</Text>
        <MGrid cols={{ base: 2, sm: 5 }} spacing="sm">
          <StatCard label="Present" value={`${d.today.present}/${d.today.total}`} color="teal" icon={<IconUserCheck size={20} />} />
          <StatCard label="Late" value={d.today.late} color="orange" icon={<IconClock size={20} />} />
          <StatCard label="Left early" value={d.today.left_early} color="orange" icon={<IconLogout2 size={20} />} />
          <StatCard label="Excused" value={d.today.excused} sub="ruhusa/mgonjwa/nje" color={d.today.excused ? 'grape' : 'gray'} icon={<IconCalendarOff size={20} />} />
          <StatCard label="Not recorded" value={d.today.not_recorded} color={d.today.not_recorded ? 'red' : 'gray'} icon={<IconUserOff size={20} />} />
        </MGrid>
      </div>

      <div>
        <Text size="sm" fw={700} tt="uppercase" c="dimmed" mb="xs">{d.month_label} · deductions</Text>
        <Group gap="sm" wrap="wrap" mb="sm">
          <Badge size="lg" color="red" variant="light">Total: TZS {d.deduction_total.toLocaleString()}</Badge>
          <Text size="sm" c="dimmed">{d.working_days_so_far} working days so far</Text>
        </Group>
        <Group gap="xs">
          {(['absent', 'late', 'left_early', 'no_checkout'] as const).map((t) => (
            <Badge key={t} variant="light" color={t === 'absent' ? 'red' : 'orange'} radius="sm">
              {penLabel[t]}: {d.by_type[t]}
            </Badge>
          ))}
        </Group>
      </div>

      <Paper withBorder radius="md">
        <Table.ScrollContainer minWidth={480}>
          <Table highlightOnHover verticalSpacing="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Staff</Table.Th>
                <Table.Th ta="center">Present ({d.working_days_so_far})</Table.Th>
                <Table.Th ta="right">Deductions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {d.staff.map((s) => (
                <Table.Tr key={s.user.id}>
                  <Table.Td fw={500}>{s.user.name}</Table.Td>
                  <Table.Td ta="center">
                    <Badge variant="light" color={s.present_days >= d.working_days_so_far ? 'teal' : 'gray'}>
                      {s.present_days}/{d.working_days_so_far}
                    </Badge>
                  </Table.Td>
                  <Table.Td ta="right" fw={600} c={s.deductions > 0 ? 'red' : 'dimmed'}>
                    {s.deductions > 0 ? `TZS ${s.deductions.toLocaleString()}` : '—'}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}

type RowEdit = { status: string; check_in: string; check_out: string };

function RecordTab() {
  const qc = useQueryClient();
  const [date, setDate] = useState<Date>(new Date());
  const ds = dayjs(date).format('YYYY-MM-DD');
  const [edits, setEdits] = useState<Record<string, RowEdit>>({});

  const { data, isLoading } = useQuery({ queryKey: ['attendance-day', ds], queryFn: () => getAttendanceDay(ds) });
  const resp = data?.data?.data;

  useEffect(() => {
    if (resp) {
      const m: Record<string, RowEdit> = {};
      resp.staff.forEach((r) => { m[r.user.id] = { status: r.status ?? '', check_in: r.check_in_at ?? '', check_out: r.check_out_at ?? '' }; });
      setEdits(m);
    }
  }, [resp]);

  const recordMut = useMutation({
    mutationFn: recordAttendance,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['attendance-day', ds] }); notifications.show({ message: 'Saved.', color: 'green' }); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Save failed.', color: 'red' }),
  });

  const set = (uid: string, field: keyof RowEdit, v: string) =>
    setEdits((s) => ({ ...s, [uid]: { ...s[uid], [field]: v } }));

  return (
    <Stack>
      <Group>
        <DatePickerInput label="Date" value={date} onChange={(v) => v && setDate(new Date(v as any))}
          valueFormat="DD/MM/YYYY" maxDate={new Date()} w={180} size="sm" />
        {resp && <Text size="sm" c="dimmed" mt={22}>Targets: in by {resp.check_in_time} · out by {resp.check_out_time}</Text>}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : !resp || resp.staff.length === 0 ? (
        <Paper withBorder p="xl" radius="md"><Text c="dimmed" ta="center">No staff.</Text></Paper>
      ) : (
        <Paper withBorder radius="md">
          <Table.ScrollContainer minWidth={760}>
            <Table verticalSpacing="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Staff</Table.Th>
                  <Table.Th>Day</Table.Th>
                  <Table.Th>Check-in</Table.Th>
                  <Table.Th>Check-out</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {resp.staff.map((r) => {
                  const e = edits[r.user.id] ?? { status: '', check_in: '', check_out: '' };
                  const excused = !!e.status;
                  return (
                    <Table.Tr key={r.user.id}>
                      <Table.Td fw={500}>{r.user.name}</Table.Td>
                      <Table.Td>
                        <Select data={statusOptions} value={e.status} w={150} allowDeselect={false} comboboxProps={{ withinPortal: true }}
                          onChange={(v) => set(r.user.id, 'status', v ?? '')} />
                      </Table.Td>
                      <Table.Td>
                        <TimeInput value={e.check_in} disabled={excused} onChange={(ev) => set(r.user.id, 'check_in', ev.currentTarget.value)} w={110} />
                      </Table.Td>
                      <Table.Td>
                        <TimeInput value={e.check_out} disabled={excused} onChange={(ev) => set(r.user.id, 'check_out', ev.currentTarget.value)} w={110} />
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4}>
                          {r.status && <Badge size="xs" color="grape" variant="light">{statusLabel[r.status] ?? r.status}</Badge>}
                          {!r.status && r.absent && <Badge size="xs" color="red" variant="light">absent</Badge>}
                          {!r.status && r.late && <Badge size="xs" color="orange" variant="light">late</Badge>}
                          {!r.status && r.left_early && <Badge size="xs" color="orange" variant="light">early</Badge>}
                          {!r.status && r.no_checkout && <Badge size="xs" color="yellow" variant="light">no out</Badge>}
                          {!r.status && !r.absent && !r.late && !r.left_early && !r.no_checkout && r.check_in_at && (
                            <Badge size="xs" color="teal" variant="light">present</Badge>
                          )}
                        </Group>
                      </Table.Td>
                      <Table.Td>
                        <ActionIcon variant="light" loading={recordMut.isPending && recordMut.variables?.user_id === r.user.id}
                          onClick={() => recordMut.mutate({
                            user_id: r.user.id, date: ds,
                            status: (e.status || null) as ExcusedStatus | null,
                            check_in: excused ? null : (e.check_in || null),
                            check_out: excused ? null : (e.check_out || null),
                          })}>
                          <IconDeviceFloppy size={16} />
                        </ActionIcon>
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
      <Text size="xs" c="dimmed">A missing check-in counts as absent (even if a check-out is entered). Set <b>Day</b> to Ruhusa / Mgonjwa / Kazi za nje for an excused day — no absence mark, no deduction. Clear a field and save to undo a mark.</Text>
    </Stack>
  );
}

const penLabel: Record<string, string> = {
  absent: 'Absent', late: 'Late', left_early: 'Left early', no_checkout: 'No check-out',
};

// Excused-day statuses (a free day — no absence/late marks, no deductions).
const statusLabel: Record<string, string> = {
  leave: 'Ruhusa', sick: 'Mgonjwa', field: 'Kazi za nje',
};
const statusOptions = [
  { value: '', label: 'Present (kazini)' },
  { value: 'leave', label: 'Ruhusa (leave)' },
  { value: 'sick', label: 'Mgonjwa (sick)' },
  { value: 'field', label: 'Kazi za nje (field)' },
];

function DeductionsTab() {
  const qc = useQueryClient();
  const [month, setMonth] = useState<Date>(new Date());
  const [detailId, setDetailId] = useState<string | null>(null);
  const m = month.getMonth() + 1;
  const y = month.getFullYear();

  const { data, isLoading } = useQuery({ queryKey: ['attendance-penalties', m, y], queryFn: () => getAttendancePenalties(m, y) });
  const res = data?.data?.data;
  const detail = res?.staff.find((s) => s.user.id === detailId) ?? null;

  const invalidate = () => qc.invalidateQueries({ queryKey: ['attendance-penalties'] });
  const waiveMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason?: string }) => waiveAttendancePenalty(id, reason),
    onSuccess: () => { invalidate(); notifications.show({ message: 'Deduction waived.', color: 'green' }); },
  });
  const unwaiveMut = useMutation({
    mutationFn: (id: string) => unwaiveAttendancePenalty(id),
    onSuccess: () => { invalidate(); notifications.show({ message: 'Reinstated.', color: 'gray' }); },
  });

  return (
    <Stack>
      <Group justify="space-between" wrap="wrap">
        <MonthPickerInput value={month} onChange={(v) => v && setMonth(new Date(v as any))}
          maxDate={new Date()} maxLevel="decade" w={160} size="sm" />
        {res && <Badge size="lg" color="red" variant="light">Total: TZS {res.grand_total.toLocaleString()}</Badge>}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : !res || res.staff.length === 0 ? (
        <Paper withBorder p="xl" radius="md"><Text c="dimmed" ta="center">No attendance deductions for {res?.month_label ?? 'this month'}.</Text></Paper>
      ) : (
        <Paper withBorder radius="md">
          <Table.ScrollContainer minWidth={640}>
            <Table highlightOnHover verticalSpacing="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Staff</Table.Th>
                  <Table.Th ta="center">Absent</Table.Th>
                  <Table.Th ta="center">Late</Table.Th>
                  <Table.Th ta="center">Early</Table.Th>
                  <Table.Th ta="center">No-out</Table.Th>
                  <Table.Th ta="right">Total</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {res.staff.map((s) => (
                  <Table.Tr key={s.user.id}>
                    <Table.Td fw={500}>{s.user.name}</Table.Td>
                    <Table.Td ta="center">{s.by_type.absent || '—'}</Table.Td>
                    <Table.Td ta="center">{s.by_type.late || '—'}</Table.Td>
                    <Table.Td ta="center">{s.by_type.left_early || '—'}</Table.Td>
                    <Table.Td ta="center">{s.by_type.no_checkout || '—'}</Table.Td>
                    <Table.Td ta="right" fw={700} c="red">TZS {s.total.toLocaleString()}</Table.Td>
                    <Table.Td ta="right">
                      <Button size="compact-xs" variant="light" onClick={() => setDetailId(s.user.id)}>View / waive</Button>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Drawer opened={!!detailId} onClose={() => setDetailId(null)} position="right" size="lg"
        title={detail ? `${detail.user.name} — ${res?.month_label}` : ''}>
        {detail && (
          <Stack gap="xs">
            {detail.items.map((it) => (
              <Paper key={it.id} withBorder p="xs" radius="sm" style={{ opacity: it.waived ? 0.55 : 1 }}>
                <Group justify="space-between" wrap="nowrap" align="flex-start">
                  <div style={{ minWidth: 0 }}>
                    <Group gap={6} wrap="nowrap">
                      <Badge size="xs" variant="light" color={it.penalty_type === 'absent' ? 'red' : 'orange'}>{penLabel[it.penalty_type] ?? it.penalty_type}</Badge>
                      <MText size="sm" truncate>{it.notes}</MText>
                    </Group>
                    <MText size="xs" c="dimmed">
                      {dayjs(it.date).format('ddd, D MMM YYYY')}
                      {it.waived && it.waive_reason ? ` · waived: ${it.waive_reason}` : it.waived ? ' · waived' : ''}
                    </MText>
                  </div>
                  <Group gap="xs" wrap="nowrap">
                    <MText size="sm" fw={600} c={it.waived ? 'dimmed' : 'red'} td={it.waived ? 'line-through' : undefined}>−TZS {it.amount.toLocaleString()}</MText>
                    {it.waived ? (
                      <Button size="compact-xs" variant="subtle" color="gray" loading={unwaiveMut.isPending} onClick={() => unwaiveMut.mutate(it.id)}>Reinstate</Button>
                    ) : (
                      <Button size="compact-xs" variant="light" color="teal" loading={waiveMut.isPending}
                        onClick={() => {
                          const reason = window.prompt('Reason for waiving (optional):') ?? undefined;
                          waiveMut.mutate({ id: it.id, reason: reason || undefined });
                        }}>Waive</Button>
                    )}
                  </Group>
                </Group>
              </Paper>
            ))}
          </Stack>
        )}
      </Drawer>
    </Stack>
  );
}


function ReportTab() {
  const qc = useQueryClient();
  const [month, setMonth] = useState<Date>(new Date());
  const [userId, setUserId] = useState<string | null>(null);
  const m = month.getMonth() + 1;
  const y = month.getFullYear();

  const { data: mapRes } = useQuery({ queryKey: ['device-mappings'], queryFn: getDeviceMappings });
  const staff = mapRes?.data?.data?.staff ?? [];

  const { data, isLoading } = useQuery({
    queryKey: ['attendance-report', userId, m, y],
    queryFn: () => getAttendanceReport(userId!, m, y),
    enabled: !!userId,
  });
  const r: AttendanceReport | undefined = data?.data?.data;

  const markMut = useMutation({
    mutationFn: ({ date, status }: { date: string; status: ExcusedStatus | null }) =>
      recordAttendance({ user_id: userId!, date, status }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['attendance-report'] });
      qc.invalidateQueries({ queryKey: ['attendance-dashboard'] });
      qc.invalidateQueries({ queryKey: ['attendance-penalties'] });
      notifications.show({ message: 'Saved — day updated and deductions recalculated.', color: 'green' });
    },
    onError: (e) => notifications.show({ message: apiErr(e, 'Failed to update day.'), color: 'red' }),
  });

  return (
    <Stack>
      <Group wrap="wrap">
        <Select label="Staff" placeholder="Select staff" w={240} searchable
          data={staff.map((s) => ({ value: s.id, label: s.name }))}
          value={userId} onChange={setUserId} />
        <MonthPickerInput label="Month" value={month} maxDate={new Date()}
          onChange={(v) => v && setMonth(new Date(v as unknown as string))} w={160} />
        {r && (
          <Text size="sm" c="dimmed" mt={22}>Targets: in by {r.check_in_time} · out by {r.check_out_time}</Text>
        )}
      </Group>

      {!userId ? (
        <Paper withBorder p="xl" radius="md"><Text c="dimmed" ta="center">Select a staff member to see their check-in / check-out report.</Text></Paper>
      ) : isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : r && (
        <>
          <Group gap="xs" wrap="wrap">
            <Badge size="lg" variant="light" color="teal">Present: {r.totals.present}</Badge>
            <Badge size="lg" variant="light" color="orange">Late: {r.totals.late}</Badge>
            <Badge size="lg" variant="light" color="orange">Left early: {r.totals.left_early}</Badge>
            <Badge size="lg" variant="light" color="yellow">No check-out: {r.totals.no_checkout}</Badge>
            <Badge size="lg" variant="light" color="red">Absent: {r.totals.absent}</Badge>
            {r.totals.excused > 0 && <Badge size="lg" variant="light" color="grape">Excused: {r.totals.excused}</Badge>}
            <Badge size="lg" variant="filled" color={r.totals.deduction_total > 0 ? 'red' : 'gray'}>
              Deductions: TZS {r.totals.deduction_total.toLocaleString()}
            </Badge>
          </Group>

          <Paper withBorder radius="md">
            <Table.ScrollContainer minWidth={560}>
              <Table highlightOnHover verticalSpacing="xs" fz="sm">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th ta="center">Check-in</Table.Th>
                    <Table.Th ta="center">Check-out</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th ta="right">Deduction</Table.Th>
                    <Table.Th w={44} />
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.days.map((d) => (
                    <Table.Tr key={d.date} style={{ opacity: d.working ? 1 : 0.5 }}>
                      <Table.Td fw={500}>{dayjs(d.date).format('DD MMM')} <Text span size="xs" c="dimmed">{d.weekday}</Text></Table.Td>
                      <Table.Td ta="center" fw={600} c={d.check_in_at ? (d.late ? 'orange' : undefined) : 'dimmed'}>
                        {d.check_in_at ?? '—'}
                      </Table.Td>
                      <Table.Td ta="center" fw={600} c={d.check_out_at ? (d.left_early ? 'orange' : undefined) : 'dimmed'}>
                        {d.check_out_at ?? '—'}
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4}>
                          {!d.working && !d.holiday && <Badge size="xs" variant="light" color="gray">off day</Badge>}
                          {d.holiday && <Badge size="xs" variant="light" color="cyan">holiday</Badge>}
                          {d.status && <Badge size="xs" variant="light" color="grape">{statusLabel[d.status] ?? d.status}</Badge>}
                          {d.absent && <Badge size="xs" variant="light" color="red">absent</Badge>}
                          {d.late && <Badge size="xs" variant="light" color="orange">late</Badge>}
                          {d.left_early && <Badge size="xs" variant="light" color="orange">left early</Badge>}
                          {d.no_checkout && <Badge size="xs" variant="light" color="yellow">no check-out</Badge>}
                          {d.check_in_at && !d.late && !d.left_early && !d.no_checkout && !d.status && (
                            <Badge size="xs" variant="light" color="teal">present</Badge>
                          )}
                        </Group>
                      </Table.Td>
                      <Table.Td ta="right" fw={600} c={d.deduction > 0 ? 'red' : 'dimmed'}>
                        {d.deduction > 0 ? `−TZS ${d.deduction.toLocaleString()}` : '—'}
                      </Table.Td>
                      <Table.Td>
                        <Menu withinPortal position="bottom-end" shadow="md">
                          <Menu.Target>
                            <ActionIcon variant="subtle" color="gray" size="sm"
                              loading={markMut.isPending && markMut.variables?.date === d.date}>
                              <IconDotsVertical size={14} />
                            </ActionIcon>
                          </Menu.Target>
                          <Menu.Dropdown>
                            <Menu.Label>Mark {dayjs(d.date).format('D MMM')} as</Menu.Label>
                            <Menu.Item leftSection={<IconCalendarOff size={14} />}
                              onClick={() => markMut.mutate({ date: d.date, status: 'leave' })}>
                              Ruhusa (leave)
                            </Menu.Item>
                            <Menu.Item leftSection={<IconCalendarOff size={14} />}
                              onClick={() => markMut.mutate({ date: d.date, status: 'sick' })}>
                              Mgonjwa (sick)
                            </Menu.Item>
                            <Menu.Item leftSection={<IconCalendarOff size={14} />}
                              onClick={() => markMut.mutate({ date: d.date, status: 'field' })}>
                              Kazi za nje (field)
                            </Menu.Item>
                            {d.status && (
                              <>
                                <Menu.Divider />
                                <Menu.Item color="red"
                                  onClick={() => markMut.mutate({ date: d.date, status: null })}>
                                  Remove excuse
                                </Menu.Item>
                              </>
                            )}
                          </Menu.Dropdown>
                        </Menu>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Paper>
          <Text size="xs" c="dimmed">Punches before 15:00 count as check-in; from 15:00 onwards as check-out. A missing check-out means the person forgot to punch out.</Text>
        </>
      )}
    </Stack>
  );
}

function ImportTab() {
  const qc = useQueryClient();
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<SheetPreview | null>(null);
  const [map, setMap] = useState<SheetMapping | null>(null);
  const [result, setResult] = useState<SheetImportResult | null>(null);

  const colData = (preview?.headers ?? []).map((h, i) => ({ value: String(i), label: h || `Column ${i + 1}` }));
  const setM = (patch: Partial<SheetMapping>) => setMap((m) => (m ? { ...m, ...patch } : m));

  const previewMut = useMutation({
    mutationFn: (f: File) => previewAttendanceSheet(f),
    onSuccess: (res) => { setPreview(res.data.data); setMap(res.data.data.guess); setResult(null); },
    onError: (e) => notifications.show({ message: apiErr(e, 'Could not read the file.'), color: 'red' }),
  });

  const commitMut = useMutation({
    mutationFn: () => commitAttendanceSheet(file!, map!),
    onSuccess: (res) => {
      setResult(res.data.data);
      qc.invalidateQueries({ queryKey: ['attendance-dashboard'] });
      qc.invalidateQueries({ queryKey: ['attendance-day'] });
      notifications.show({ message: `Imported ${res.data.data.days} staff-day(s).`, color: 'green' });
    },
    onError: (e) => notifications.show({ message: apiErr(e, 'Import failed.'), color: 'red' }),
  });

  const pick = (f: File | null) => {
    setFile(f); setPreview(null); setMap(null); setResult(null);
    if (f) previewMut.mutate(f);
  };

  const unmatched = result ? Object.entries(result.unmatched) : [];

  return (
    <Stack gap="lg" maw={860}>
      <Alert color="blue" variant="light" icon={<IconFileSpreadsheet size={18} />} title="Import from iVMS-4200">
        In iVMS-4200 open <b>Time &amp; Attendance → Report</b>, generate the attendance report, and <b>Export as CSV</b>.
        Upload it here — first punch of the day becomes the check-in, last becomes the check-out. Staff are matched by
        name (or employee number). Excused days are never overwritten.
      </Alert>

      <Group>
        <FileButton onChange={pick} accept=".csv,text/csv">
          {(props) => <Button {...props} leftSection={<IconUpload size={16} />} loading={previewMut.isPending}>Choose CSV file</Button>}
        </FileButton>
        {file && <Text size="sm" c="dimmed">{file.name} · {preview ? `${preview.total} rows` : '…'}</Text>}
      </Group>

      {preview && map && (
        <>
          <Paper withBorder radius="md" p="md">
            <Text size="sm" fw={700} mb="sm">Tell us which columns to use</Text>
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
              <div>
                <Text size="xs" fw={600} mb={4}>Match staff by</Text>
                <SegmentedControl fullWidth size="xs" value={map.match_by}
                  onChange={(v) => setM({ match_by: v as SheetMapping['match_by'] })}
                  data={[{ value: 'name', label: 'Name' }, { value: 'employee_no', label: 'Employee no.' }]} />
              </div>
              <Select label={map.match_by === 'name' ? 'Name column' : 'Employee-no column'} data={colData}
                value={String(map.identity_col)} onChange={(v) => setM({ identity_col: Number(v) })} />
              <Select label="Date column" data={colData} clearable
                value={map.date_col === null ? null : String(map.date_col)}
                onChange={(v) => setM({ date_col: v === null ? null : Number(v) })}
                description="Skip if the time column already includes the date" />
              <div>
                <Text size="xs" fw={600} mb={4}>Time columns</Text>
                <SegmentedControl fullWidth size="xs" value={map.time_mode}
                  onChange={(v) => setM({ time_mode: v as SheetMapping['time_mode'] })}
                  data={[{ value: 'inout', label: 'Separate in / out' }, { value: 'single', label: 'One punch column' }]} />
              </div>
              {map.time_mode === 'inout' ? (
                <>
                  <Select label="Check-in column" data={colData} clearable
                    value={map.in_col === null ? null : String(map.in_col)}
                    onChange={(v) => setM({ in_col: v === null ? null : Number(v) })} />
                  <Select label="Check-out column" data={colData} clearable
                    value={map.out_col === null ? null : String(map.out_col)}
                    onChange={(v) => setM({ out_col: v === null ? null : Number(v) })} />
                </>
              ) : (
                <Select label="Punch / time column" data={colData} clearable
                  value={map.time_col === null ? null : String(map.time_col)}
                  onChange={(v) => setM({ time_col: v === null ? null : Number(v) })}
                  description="Each row is one punch; we take earliest & latest per day" />
              )}
            </SimpleGrid>
          </Paper>

          <div>
            <Text size="xs" fw={700} tt="uppercase" c="dimmed" mb="xs">Preview · first {preview.rows.length} of {preview.total} rows</Text>
            <Paper withBorder radius="md">
              <Table.ScrollContainer minWidth={preview.headers.length * 120}>
                <Table striped withColumnBorders verticalSpacing="xs" fz="xs">
                  <Table.Thead>
                    <Table.Tr>{preview.headers.map((h, i) => <Table.Th key={i}>{h || `Col ${i + 1}`}</Table.Th>)}</Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {preview.rows.map((r, ri) => (
                      <Table.Tr key={ri}>{preview.headers.map((_, ci) => <Table.Td key={ci}>{r[ci] ?? ''}</Table.Td>)}</Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            </Paper>
          </div>

          <Group>
            <Button leftSection={<IconDeviceFloppy size={16} />} loading={commitMut.isPending}
              disabled={map.time_mode === 'inout' ? (map.in_col === null && map.out_col === null) : map.time_col === null}
              onClick={() => commitMut.mutate()}>
              Import {preview.total} rows
            </Button>
          </Group>
        </>
      )}

      {result && (
        <Alert color={result.days ? 'teal' : 'orange'} variant="light" title="Import complete">
          <Text size="sm">
            Imported <b>{result.days}</b> staff-day(s) from <b>{result.matched_rows}</b> matched row(s).
            {(result.linked ?? 0) > 0 && <> Linked <b>{result.linked}</b> staff to their device employee numbers.</>}
            {result.skipped > 0 && ` ${result.skipped} row(s) skipped (no usable time).`}
          </Text>
          {unmatched.length > 0 && (
            <>
              <Text size="sm" mt="xs" fw={600}>Not matched to any staff ({unmatched.length}):</Text>
              <Group gap={6} mt={4}>
                {unmatched.map(([name, n]) => (
                  <Badge key={name} color="orange" variant="light" radius="sm">{name} ×{n}</Badge>
                ))}
              </Group>
              <Text size="xs" c="dimmed" mt={6}>
                Fix the staff name in MoBilling (or switch “Match staff by” to Employee no. and set each person's number in the Device tab), then re-upload.
              </Text>
            </>
          )}
        </Alert>
      )}
    </Stack>
  );
}

function StaffMapRow({ staff }: { staff: DeviceMappingStaff }) {
  const qc = useQueryClient();
  // Keyed on the server value by the parent, so a fresh server value remounts this row.
  const [val, setVal] = useState(staff.device_employee_no ?? '');

  const dirty = val.trim() !== (staff.device_employee_no ?? '');
  const saveMut = useMutation({
    mutationFn: () => saveDeviceMapping(staff.id, val.trim() || null),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['device-mappings'] });
      qc.invalidateQueries({ queryKey: ['device-events'] });
      qc.invalidateQueries({ queryKey: ['attendance-dashboard'] });
      const imp = res.data.import;
      notifications.show({ message: imp?.days ? `Linked — imported ${imp.matched} swipe(s).` : 'Saved.', color: 'green' });
    },
    onError: (e) => {
      const msg = (e as { response?: { data?: { message?: string } } })?.response?.data?.message ?? 'Save failed.';
      notifications.show({ message: msg, color: 'red' });
    },
  });

  return (
    <Table.Tr>
      <Table.Td fw={500}>{staff.name}</Table.Td>
      <Table.Td>
        <Group gap={6} wrap="nowrap">
          <TextInput value={val} placeholder="e.g. 5" w={120} size="xs"
            onChange={(e) => setVal(e.currentTarget.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && dirty) saveMut.mutate(); }} />
          <Button size="compact-xs" variant={dirty ? 'filled' : 'light'} disabled={!dirty}
            loading={saveMut.isPending} onClick={() => saveMut.mutate()}>Save</Button>
        </Group>
      </Table.Td>
    </Table.Tr>
  );
}

function DeviceTab() {
  const qc = useQueryClient();
  const [openId, setOpenId] = useState<string | null>(null);
  const { data: cfgRes, isLoading } = useQuery({ queryKey: ['device-config'], queryFn: getDeviceConfig });
  const { data: evRes } = useQuery({ queryKey: ['device-events'], queryFn: getDeviceEvents, refetchInterval: 5000 });
  const { data: mapRes } = useQuery({ queryKey: ['device-mappings'], queryFn: getDeviceMappings, refetchInterval: 10000 });
  const cfg = cfgRes?.data?.data;
  const events = evRes?.data?.data ?? [];
  const mappings = mapRes?.data?.data;

  const regenMut = useMutation({
    mutationFn: regenerateDeviceToken,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['device-config'] }); notifications.show({ message: 'New webhook URL generated.', color: 'green' }); },
  });

  const importMut = useMutation({
    mutationFn: importDeviceEvents,
    onSuccess: (res) => {
      const r = res.data.data;
      qc.invalidateQueries({ queryKey: ['device-events'] });
      qc.invalidateQueries({ queryKey: ['device-mappings'] });
      qc.invalidateQueries({ queryKey: ['attendance-dashboard'] });
      notifications.show({
        message: `Imported ${r.matched} swipe(s) into ${r.days} staff-day(s).${r.unmatched ? ` ${r.unmatched} still unlinked.` : ''}`,
        color: r.matched ? 'green' : 'gray',
      });
    },
  });

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack gap="lg">
      <Alert color="blue" variant="light" icon={<IconDeviceDesktop size={18} />} title="HIKVISION event push">
        Point your device's <b>Notify Surveillance Center</b> / <b>HTTP Listening (Alarm Server)</b> at the URL below.
        Each face/card swipe posts an event here. We're in <b>capture mode</b> — events are logged raw so we can confirm
        the exact format and map each device employee number to a staff member. Nothing is imported into attendance yet.
      </Alert>

      <Paper withBorder radius="md" p="md">
        <Text size="sm" fw={700} mb="xs">Webhook URL</Text>
        <Group gap="xs" wrap="nowrap" align="stretch">
          <Code style={{ flex: 1, wordBreak: 'break-all', padding: '8px 10px', fontSize: 13 }}>{cfg?.webhook_url}</Code>
          <CopyButton value={cfg?.webhook_url ?? ''} timeout={1500}>
            {({ copied, copy }) => (
              <Tooltip label={copied ? 'Copied' : 'Copy'}>
                <Button variant="light" color={copied ? 'teal' : 'blue'} onClick={copy}
                  leftSection={copied ? <IconCheck size={15} /> : <IconCopy size={15} />}>
                  {copied ? 'Copied' : 'Copy'}
                </Button>
              </Tooltip>
            )}
          </CopyButton>
        </Group>
        <Group justify="space-between" mt="sm">
          <Text size="xs" c="dimmed">
            Last event: {cfg?.last_event_at ? dayjs(cfg.last_event_at).format('ddd, D MMM HH:mm:ss') : 'none yet'}
          </Text>
          <Button size="compact-xs" variant="subtle" color="gray" leftSection={<IconRefresh size={13} />}
            loading={regenMut.isPending}
            onClick={() => { if (window.confirm('Generate a new URL? The device must be reconfigured with the new URL.')) regenMut.mutate(); }}>
            Regenerate URL
          </Button>
        </Group>
      </Paper>

      <div>
        <Group justify="space-between" mb="xs">
          <div>
            <Text size="sm" fw={700} tt="uppercase" c="dimmed">Link staff to device IDs</Text>
            <Text size="xs" c="dimmed">Enter each staff member's employee number on the device. Linked swipes fill their check-in/out automatically.</Text>
          </div>
          <Button size="compact-sm" variant="light" leftSection={<IconRefresh size={14} />}
            loading={importMut.isPending} onClick={() => importMut.mutate()}>
            Import now
          </Button>
        </Group>

        {mappings && mappings.unlinked.length > 0 && (
          <Alert color="orange" variant="light" mb="sm" p="xs">
            <Text size="xs">
              Device IDs seen but not linked to anyone yet:{' '}
              {mappings.unlinked.map((n) => <Badge key={n} color="orange" variant="light" radius="sm" mr={4}>#{n}</Badge>)}
              — set the matching number on a staff row below.
            </Text>
          </Alert>
        )}

        <Paper withBorder radius="md" mb="lg">
          <Table.ScrollContainer minWidth={420}>
            <Table verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Staff</Table.Th>
                  <Table.Th w={220}>Device employee no.</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {mappings?.staff.map((s) => <StaffMapRow key={`${s.id}|${s.device_employee_no ?? ''}`} staff={s} />)}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      </div>

      <div>
        <Group justify="space-between" mb="xs">
          <Text size="sm" fw={700} tt="uppercase" c="dimmed">Captured events</Text>
          <Badge variant="light" color={events.length ? 'teal' : 'gray'}>{events.length} recent</Badge>
        </Group>
        {events.length === 0 ? (
          <Paper withBorder p="xl" radius="md">
            <Text c="dimmed" ta="center" size="sm">
              No events captured yet. Configure the device with the URL above, then have one person swipe — it should appear here within seconds.
            </Text>
          </Paper>
        ) : (
          <Stack gap="xs">
            {events.map((e) => (
              <Paper key={e.id} withBorder radius="sm" p="xs">
                <Group justify="space-between" wrap="nowrap" onClick={() => setOpenId(openId === e.id ? null : e.id)} style={{ cursor: 'pointer' }}>
                  <Group gap="sm" wrap="nowrap" style={{ minWidth: 0 }}>
                    <Badge variant="light" color={e.employee_no ? 'blue' : 'gray'} radius="sm">
                      {e.employee_no ? `#${e.employee_no}` : 'no id'}
                    </Badge>
                    <div style={{ minWidth: 0 }}>
                      <Text size="sm" fw={500}>
                        {e.event_time ? dayjs(e.event_time).format('ddd, D MMM HH:mm:ss') : 'no event time'}
                      </Text>
                      <Text size="xs" c="dimmed" truncate>{e.content_type ?? 'unknown type'} · logged {dayjs(e.created_at).format('HH:mm:ss')}</Text>
                    </div>
                  </Group>
                  <Button size="compact-xs" variant="subtle" color="gray">{openId === e.id ? 'Hide' : 'Raw'}</Button>
                </Group>
                <Collapse in={openId === e.id}>
                  <Stack gap={6} mt="xs">
                    {e.parsed && Object.keys(e.parsed).length > 0 && (
                      <div>
                        <Text size="xs" fw={600} c="dimmed" mb={2}>Parsed fields</Text>
                        <Code block style={{ fontSize: 12 }}>{JSON.stringify(e.parsed, null, 2)}</Code>
                      </div>
                    )}
                    <div>
                      <Text size="xs" fw={600} c="dimmed" mb={2}>Raw payload</Text>
                      <Code block style={{ fontSize: 12, maxHeight: 260, overflow: 'auto' }}>{e.payload || '(empty)'}</Code>
                    </div>
                  </Stack>
                </Collapse>
              </Paper>
            ))}
          </Stack>
        )}
      </div>
    </Stack>
  );
}

function SettingsTab() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['attendance-settings'], queryFn: getAttendanceSettings });
  const settings = data?.data?.data;

  const form = useForm<AttendanceSettings>({
    initialValues: {
      check_in_time: '07:30', check_out_time: '17:00', penalties_enabled: true,
      penalty_absent: 5000, penalty_late: 2000, penalty_left_early: 2000, penalty_no_checkout: 2000,
      working_days: [1, 2, 3, 4, 5, 6],
    },
  });

  useEffect(() => { if (settings) form.setValues(settings); /* eslint-disable-next-line */ }, [settings]);

  const mutation = useMutation({
    mutationFn: updateAttendanceSettings,
    onSuccess: (res) => { qc.invalidateQueries({ queryKey: ['attendance-settings'] }); form.setValues(res.data.data); notifications.show({ message: 'Settings saved.', color: 'green' }); },
    onError: () => notifications.show({ message: 'Failed to save.', color: 'red' }),
  });

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <form onSubmit={form.onSubmit((v) => mutation.mutate(v))}>
      <Stack gap="lg" maw={560}>
        <div>
          <Group gap="xs" mb="xs">
            <ThemeIcon size="sm" variant="light" color="blue" radius="xl"><IconClock size={14} /></ThemeIcon>
            <Text size="sm" fw={700}>Work hours</Text>
          </Group>
          <SimpleGrid cols={2} spacing="sm">
            <TimeInput label="Check-in time" {...form.getInputProps('check_in_time')} />
            <TimeInput label="Check-out time" {...form.getInputProps('check_out_time')} />
          </SimpleGrid>
          <Text size="xs" fw={600} mt="sm" mb={4}>Working days</Text>
          <Chip.Group multiple value={(form.values.working_days ?? []).map(String)}
            onChange={(v) => form.setFieldValue('working_days', v.map(Number).sort())}>
            <Group gap={6}>
              {[[1, 'Mon'], [2, 'Tue'], [3, 'Wed'], [4, 'Thu'], [5, 'Fri'], [6, 'Sat'], [7, 'Sun']].map(([n, l]) => (
                <Chip key={n} value={String(n)} size="xs" variant="light">{l as string}</Chip>
              ))}
            </Group>
          </Chip.Group>
        </div>

        <Divider />

        <div>
          <Group gap="xs" mb="xs" justify="space-between">
            <Group gap="xs">
              <ThemeIcon size="sm" variant="light" color="red" radius="xl"><IconAlertTriangle size={14} /></ThemeIcon>
              <Text size="sm" fw={700}>Deductions</Text>
            </Group>
            <Switch label="Enabled" checked={!!form.values.penalties_enabled}
              onChange={(e) => form.setFieldValue('penalties_enabled', e.currentTarget.checked)} />
          </Group>
          <Text size="xs" c="dimmed" mb="sm">Charged after each working day's check-out time. Holidays are excluded.</Text>
          <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="sm">
            <NumberInput label="Absent" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled} {...form.getInputProps('penalty_absent')} />
            <NumberInput label="Late" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled} {...form.getInputProps('penalty_late')} />
            <NumberInput label="Left early" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled} {...form.getInputProps('penalty_left_early')} />
            <NumberInput label="No check-out" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled} {...form.getInputProps('penalty_no_checkout')} />
          </SimpleGrid>
        </div>

        <Alert color="blue" variant="light" p="xs">
          A missing check-in is counted as <b>absent</b> even if a check-out is recorded.
        </Alert>

        <Group>
          <Button type="submit" loading={mutation.isPending}>Save Settings</Button>
        </Group>
      </Stack>
    </form>
  );
}

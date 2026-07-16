import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Text, Paper, Table, Badge, Button, ActionIcon,
  Loader, Center, ThemeIcon, NumberInput, Switch, Chip, SimpleGrid, Divider, Alert,
} from '@mantine/core';
import { DatePickerInput, TimeInput, MonthPickerInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconClipboardCheck, IconSettings, IconDeviceFloppy, IconClock, IconAlertTriangle, IconReceiptOff, IconChartBar, IconUserCheck, IconUserOff, IconLogout2 } from '@tabler/icons-react';
import { Drawer, Text as MText, Card, SimpleGrid as MGrid } from '@mantine/core';
import dayjs from 'dayjs';
import {
  getAttendanceDay, recordAttendance, getAttendanceSettings, updateAttendanceSettings,
  getAttendancePenalties, waiveAttendancePenalty, unwaiveAttendancePenalty, getAttendanceDashboard,
  AttendanceSettings,
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
          <Tabs.Tab value="settings" leftSection={<IconSettings size={15} />}>Settings</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="dashboard" pt="md"><DashboardTab /></Tabs.Panel>
        <Tabs.Panel value="record" pt="md"><RecordTab /></Tabs.Panel>
        <Tabs.Panel value="deductions" pt="md"><DeductionsTab /></Tabs.Panel>
        <Tabs.Panel value="settings" pt="md"><SettingsTab /></Tabs.Panel>
      </Tabs>
    </Stack>
  );
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
        <MGrid cols={{ base: 2, sm: 4 }} spacing="sm">
          <StatCard label="Present" value={`${d.today.present}/${d.today.total}`} color="teal" icon={<IconUserCheck size={20} />} />
          <StatCard label="Late" value={d.today.late} color="orange" icon={<IconClock size={20} />} />
          <StatCard label="Left early" value={d.today.left_early} color="orange" icon={<IconLogout2 size={20} />} />
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

function RecordTab() {
  const qc = useQueryClient();
  const [date, setDate] = useState<Date>(new Date());
  const ds = dayjs(date).format('YYYY-MM-DD');
  const [edits, setEdits] = useState<Record<string, { check_in: string; check_out: string }>>({});

  const { data, isLoading } = useQuery({ queryKey: ['attendance-day', ds], queryFn: () => getAttendanceDay(ds) });
  const resp = data?.data?.data;

  useEffect(() => {
    if (resp) {
      const m: Record<string, { check_in: string; check_out: string }> = {};
      resp.staff.forEach((r) => { m[r.user.id] = { check_in: r.check_in_at ?? '', check_out: r.check_out_at ?? '' }; });
      setEdits(m);
    }
  }, [resp]);

  const recordMut = useMutation({
    mutationFn: recordAttendance,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['attendance-day', ds] }); notifications.show({ message: 'Saved.', color: 'green' }); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Save failed.', color: 'red' }),
  });

  const set = (uid: string, field: 'check_in' | 'check_out', v: string) =>
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
          <Table.ScrollContainer minWidth={620}>
            <Table verticalSpacing="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Staff</Table.Th>
                  <Table.Th>Check-in</Table.Th>
                  <Table.Th>Check-out</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {resp.staff.map((r) => {
                  const e = edits[r.user.id] ?? { check_in: '', check_out: '' };
                  return (
                    <Table.Tr key={r.user.id}>
                      <Table.Td fw={500}>{r.user.name}</Table.Td>
                      <Table.Td>
                        <TimeInput value={e.check_in} onChange={(ev) => set(r.user.id, 'check_in', ev.currentTarget.value)} w={110} />
                      </Table.Td>
                      <Table.Td>
                        <TimeInput value={e.check_out} onChange={(ev) => set(r.user.id, 'check_out', ev.currentTarget.value)} w={110} />
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4}>
                          {r.absent && <Badge size="xs" color="red" variant="light">absent</Badge>}
                          {r.late && <Badge size="xs" color="orange" variant="light">late</Badge>}
                          {r.left_early && <Badge size="xs" color="orange" variant="light">early</Badge>}
                          {r.no_checkout && <Badge size="xs" color="yellow" variant="light">no out</Badge>}
                          {!r.absent && !r.late && !r.left_early && !r.no_checkout && r.check_in_at && (
                            <Badge size="xs" color="teal" variant="light">present</Badge>
                          )}
                        </Group>
                      </Table.Td>
                      <Table.Td>
                        <ActionIcon variant="light" loading={recordMut.isPending && recordMut.variables?.user_id === r.user.id}
                          onClick={() => recordMut.mutate({ user_id: r.user.id, date: ds, check_in: e.check_in || null, check_out: e.check_out || null })}>
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
      <Text size="xs" c="dimmed">A missing check-in counts as absent (even if a check-out is entered). Clear a field and save to undo a mark.</Text>
    </Stack>
  );
}

const penLabel: Record<string, string> = {
  absent: 'Absent', late: 'Late', left_early: 'Left early', no_checkout: 'No check-out',
};

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

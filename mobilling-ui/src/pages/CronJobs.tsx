import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Table, Select, Center, Loader, Alert,
  Button, Modal, TextInput, Textarea, ActionIcon, Badge,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconClock, IconAlertTriangle, IconPlus, IconPencil, IconTrash } from '@tabler/icons-react';
import {
  discoverHostingAccounts, getCronJobs, addCronJob, updateCronJob, deleteCronJob,
  DiscoveredAccount, CronJobRow,
} from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';

const PRESETS: { label: string; value: string; fields: [string, string, string, string, string] }[] = [
  { label: 'Every minute', value: 'every_minute', fields: ['*', '*', '*', '*', '*'] },
  { label: 'Every hour', value: 'hourly', fields: ['0', '*', '*', '*', '*'] },
  { label: 'Every day at midnight', value: 'daily', fields: ['0', '0', '*', '*', '*'] },
  { label: 'Every week (Sunday midnight)', value: 'weekly', fields: ['0', '0', '*', '*', '0'] },
  { label: 'Every month (1st, midnight)', value: 'monthly', fields: ['0', '0', '1', '*', '*'] },
  { label: 'Custom', value: 'custom', fields: ['*', '*', '*', '*', '*'] },
];

const scheduleText = (j: { minute: string; hour: string; day: string; month: string; weekday: string }) =>
  `${j.minute} ${j.hour} ${j.day} ${j.month} ${j.weekday}`;

interface FormValues {
  preset: string;
  minute: string;
  hour: string;
  day: string;
  month: string;
  weekday: string;
  command: string;
}

export default function CronJobs() {
  const { can } = usePermissions();
  const canManage = can('hosting.change_package');
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<CronJobRow | null>(null);

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .slice()
    .sort((a, b) => (a.domain ?? '').localeCompare(b.domain ?? ''))
    .map((a) => ({
      value: `${a.server_id}|${a.cpanel_username}`,
      label: `${a.domain ?? a.cpanel_username}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, cpanelUsername] = selected ? selected.split('|') : [null, null];

  const { data: jobsData, isLoading: jobsLoading, isError } = useQuery({
    queryKey: ['cron-jobs', serverId, cpanelUsername],
    queryFn: () => getCronJobs({ server_id: serverId!, cpanel_username: cpanelUsername! }),
    enabled: !!serverId && !!cpanelUsername,
  });
  const jobs = jobsData?.data?.data ?? [];

  const form = useForm<FormValues>({
    initialValues: { preset: 'daily', minute: '0', hour: '0', day: '*', month: '*', weekday: '*', command: '' },
    validate: {
      command: (v) => (v.trim() ? null : 'Required'),
    },
  });

  const openAdd = () => {
    setEditing(null);
    form.setValues({ preset: 'daily', minute: '0', hour: '0', day: '*', month: '*', weekday: '*', command: '' });
    setModalOpen(true);
  };

  const openEdit = (job: CronJobRow) => {
    setEditing(job);
    form.setValues({
      preset: 'custom', minute: job.minute, hour: job.hour, day: job.day, month: job.month,
      weekday: job.weekday, command: job.command,
    });
    setModalOpen(true);
  };

  const applyPreset = (value: string | null) => {
    const preset = PRESETS.find((p) => p.value === value);
    form.setFieldValue('preset', value ?? 'custom');
    if (preset && preset.value !== 'custom') {
      const [minute, hour, day, month, weekday] = preset.fields;
      form.setValues({ ...form.values, preset: value ?? 'custom', minute, hour, day, month, weekday });
    }
  };

  const saveMutation = useMutation({
    mutationFn: (v: FormValues) => {
      const payload = {
        server_id: serverId!, cpanel_username: cpanelUsername!,
        minute: v.minute.trim(), hour: v.hour.trim(), day: v.day.trim(), month: v.month.trim(), weekday: v.weekday.trim(),
        command: v.command.trim(),
      };
      return editing ? updateCronJob({ ...payload, linekey: editing.linekey }) : addCronJob(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['cron-jobs', serverId, cpanelUsername] });
      notifications.show({ title: editing ? 'Updated' : 'Added', message: `Cron job ${editing ? 'updated' : 'added'}.`, color: 'green' });
      setModalOpen(false);
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to save the cron job.', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (linekey: number) => deleteCronJob({ server_id: serverId!, cpanel_username: cpanelUsername!, linekey }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['cron-jobs', serverId, cpanelUsername] });
      notifications.show({ title: 'Deleted', message: 'Cron job removed.', color: 'green' });
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to delete the cron job.', color: 'red' }),
  });

  const confirmDelete = (job: CronJobRow) => modals.openConfirmModal({
    title: 'Delete cron job',
    children: <Text size="sm">Delete the job running <Text span fw={600}>{job.command}</Text>? This can't be undone.</Text>,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(job.linekey),
  });

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconClock size={22} /> Cron Jobs</Group>
        </Title>
        {canManage && (
          <Button leftSection={<IconPlus size={16} />} onClick={openAdd} disabled={!cpanelUsername}>
            Add Cron Job
          </Button>
        )}
      </Group>

      <Text size="sm" c="dimmed">
        Pick a hosting account to see and manage its scheduled cron jobs directly, without needing to log
        into cPanel.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Hosting account" placeholder="Search domain or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && (
        <Paper withBorder radius="sm">
          {jobsLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load cron jobs for {cpanelUsername}.
            </Alert>
          ) : jobs.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No cron jobs for {cpanelUsername}.</Text></Center>
          ) : (
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Schedule</Table.Th>
                    <Table.Th>Command</Table.Th>
                    {canManage && <Table.Th w={90}></Table.Th>}
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {jobs.map((j) => (
                    <Table.Tr key={j.linekey}>
                      <Table.Td>
                        <Badge size="sm" variant="light" color="grape" style={{ fontFamily: 'monospace' }}>
                          {scheduleText(j)}
                        </Badge>
                      </Table.Td>
                      <Table.Td fz="sm" style={{ wordBreak: 'break-all', fontFamily: 'monospace' }}>{j.command}</Table.Td>
                      {canManage && (
                        <Table.Td>
                          <Group gap={4}>
                            <ActionIcon variant="subtle" onClick={() => openEdit(j)}><IconPencil size={16} /></ActionIcon>
                            <ActionIcon variant="subtle" color="red" onClick={() => confirmDelete(j)}><IconTrash size={16} /></ActionIcon>
                          </Group>
                        </Table.Td>
                      )}
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Paper>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)} title={`${editing ? 'Edit' : 'Add'} Cron Job — ${cpanelUsername ?? ''}`} size="md">
        <form onSubmit={form.onSubmit((v) => saveMutation.mutate(v))}>
          <Stack>
            <Select label="Schedule preset" data={PRESETS.map((p) => ({ value: p.value, label: p.label }))}
              value={form.values.preset} onChange={applyPreset} />
            <Group grow>
              <TextInput label="Minute" {...form.getInputProps('minute')} />
              <TextInput label="Hour" {...form.getInputProps('hour')} />
              <TextInput label="Day" {...form.getInputProps('day')} />
              <TextInput label="Month" {...form.getInputProps('month')} />
              <TextInput label="Weekday" {...form.getInputProps('weekday')} />
            </Group>
            <Textarea label="Command" required autosize minRows={2}
              placeholder="e.g. php -q /home/user/public_html/cron.php"
              {...form.getInputProps('command')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
              <Button type="submit" loading={saveMutation.isPending}>{editing ? 'Save' : 'Add Cron Job'}</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

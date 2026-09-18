import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert,
  Button, Modal, TextInput, NumberInput,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconWorldWww, IconAlertTriangle, IconPlus, IconInfoCircle } from '@tabler/icons-react';
import {
  discoverHostingAccounts, getDnsZone, addDnsRecord, DiscoveredAccount, AddDnsRecordPayload,
} from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';

const typeColors: Record<string, string> = {
  A: 'blue', AAAA: 'blue', CNAME: 'grape', MX: 'orange', TXT: 'teal',
  NS: 'gray', SOA: 'gray', SRV: 'violet',
};

const RECORD_TYPES: AddDnsRecordPayload['type'][] = ['A', 'AAAA', 'CNAME', 'TXT', 'MX'];

interface FormValues {
  type: AddDnsRecordPayload['type'];
  name: string;
  ttl: number;
  value: string;
  priority: number;
}

/**
 * A domain's DNS zone. View is straightforward (WHM's parse_dns_zone).
 * Adding a record is supported (addzonerecord, verified live for
 * A/AAAA/CNAME/TXT/MX). Editing/deleting an existing record is
 * deliberately NOT here: WHM's line-number-based editzonerecord/
 * removezonerecord proved unreliable during verification — the line
 * numbers parse_dns_zone reports don't match what those two calls
 * themselves use for the same zone at the same moment, which corrupted
 * two real records before that was caught and reverted. Until a safer
 * way to target an existing record is found, fixing/removing one means
 * asking staff with direct WHM access to do it there.
 */
export default function DnsZone() {
  const { can } = usePermissions();
  const canAdd = can('hosting.change_package');
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .filter((a) => a.domain)
    .slice()
    .sort((a, b) => (a.domain ?? '').localeCompare(b.domain ?? ''))
    .map((a) => ({
      value: `${a.server_id}|${a.domain}`,
      label: `${a.domain}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, domain] = selected ? selected.split('|') : [null, null];

  const { data: zoneData, isLoading: zoneLoading, isError } = useQuery({
    queryKey: ['dns-zone', serverId, domain],
    queryFn: () => getDnsZone({ server_id: serverId!, domain: domain! }),
    enabled: !!serverId && !!domain,
  });
  const records = zoneData?.data?.data ?? [];

  const form = useForm<FormValues>({
    initialValues: { type: 'A', name: '', ttl: 14400, value: '', priority: 10 },
    validate: {
      name: (v) => (v.trim() ? null : 'Required'),
      value: (v, values) => (values.type !== 'MX' && !v.trim() ? 'Required' : null),
    },
  });

  const openAdd = () => { form.reset(); setAddOpen(true); };

  const addMutation = useMutation({
    mutationFn: (v: FormValues) => addDnsRecord({
      server_id: serverId!, domain: domain!, type: v.type, name: v.name.trim(), ttl: v.ttl,
      value: v.value.trim() || undefined,
      priority: v.type === 'MX' ? v.priority : undefined,
    }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['dns-zone', serverId, domain] });
      notifications.show({ title: 'Added', message: 'DNS record added.', color: 'green' });
      setAddOpen(false);
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to add the record.', color: 'red' }),
  });

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconWorldWww size={22} /> DNS Zone</Group>
        </Title>
        {canAdd && (
          <Button leftSection={<IconPlus size={16} />} onClick={openAdd} disabled={!domain}>
            Add Record
          </Button>
        )}
      </Group>

      <Text size="sm" c="dimmed">
        Pick a domain to see its DNS zone straight from WHM. Adding a record is supported — editing or
        removing an existing one isn't yet (a WHM reliability issue found during testing means that's
        safer to ask a WHM admin to do directly for now).
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Domain" placeholder="Search domain or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && (
        <Paper withBorder radius="sm">
          {zoneLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load the DNS zone for {domain}.
            </Alert>
          ) : records.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No records found for {domain}.</Text></Center>
          ) : (
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={48}>#</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th>Name</Table.Th>
                    <Table.Th>TTL</Table.Th>
                    <Table.Th>Value</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {records.map((r, i) => (
                    <Table.Tr key={i}>
                      <Table.Td c="dimmed">{i + 1}</Table.Td>
                      <Table.Td>
                        <Badge size="sm" variant="light" color={typeColors[r.type] ?? 'dark'}>{r.type}</Badge>
                      </Table.Td>
                      <Table.Td fw={500} fz="sm">{r.name}</Table.Td>
                      <Table.Td fz="sm" c="dimmed">{r.ttl}</Table.Td>
                      <Table.Td fz="sm" style={{ wordBreak: 'break-all' }}>{r.data.join('  ·  ')}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Paper>
      )}

      <Modal opened={addOpen} onClose={() => setAddOpen(false)} title={`Add DNS Record — ${domain ?? ''}`} size="md">
        <form onSubmit={form.onSubmit((v) => addMutation.mutate(v))}>
          <Stack>
            <Select label="Type" required data={RECORD_TYPES} {...form.getInputProps('type')} />
            <TextInput label="Name" required placeholder="e.g. sub.example.com or sub"
              description="Full hostname — if you leave off the domain, it's added automatically."
              {...form.getInputProps('name')}
              onChange={(e) => {
                const v = e.currentTarget.value;
                form.setFieldValue('name', v.includes('.') || !domain ? v : `${v}.${domain}`);
              }} />
            <NumberInput label="TTL (seconds)" required min={60} {...form.getInputProps('ttl')} />
            {form.values.type === 'MX' ? (
              <>
                <NumberInput label="Priority" required min={0} {...form.getInputProps('priority')} />
                <TextInput label="Mail Server" required placeholder="mail.example.com" {...form.getInputProps('value')} />
              </>
            ) : (
              <TextInput
                label="Value" required
                placeholder={form.values.type === 'CNAME' ? 'target.example.com' : form.values.type === 'TXT' ? 'v=spf1 ...' : '1.2.3.4'}
                {...form.getInputProps('value')}
              />
            )}
            <Alert color="blue" variant="light" icon={<IconInfoCircle size={16} />}>
              DNS changes can take a few hours to propagate. Double-check the domain and value before saving.
            </Alert>
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setAddOpen(false)}>Cancel</Button>
              <Button type="submit" loading={addMutation.isPending}>Add Record</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

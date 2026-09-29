import { useState } from 'react';
import {
  Stack, Paper, Text, Group, Badge, Table, Center, Loader, Alert,
  Button, Modal, TextInput, NumberInput, Select,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { IconAlertTriangle, IconPlus, IconInfoCircle } from '@tabler/icons-react';

export interface WhmDnsRecord {
  type: string;
  name: string;
  ttl: number;
  data: string[];
}

export type WhmDnsRecordType = 'A' | 'AAAA' | 'CNAME' | 'TXT' | 'MX';
const RECORD_TYPES: WhmDnsRecordType[] = ['A', 'AAAA', 'CNAME', 'TXT', 'MX'];

const typeColors: Record<string, string> = {
  A: 'blue', AAAA: 'blue', CNAME: 'grape', MX: 'orange', TXT: 'teal',
  NS: 'gray', SOA: 'gray', SRV: 'violet',
};

interface FormValues {
  type: WhmDnsRecordType;
  name: string;
  ttl: number;
  value: string;
  priority: number;
}

export interface WhmAddDnsRecordInput {
  type: WhmDnsRecordType;
  name: string;
  ttl: number;
  value?: string;
  priority?: number;
}

export interface WhmDnsSectionProps {
  /** Bare domain name — used to prefix a relative record name and in the modal title. */
  domain: string;
  records: WhmDnsRecord[];
  isLoading: boolean;
  isError: boolean;
  canAdd: boolean;
  onAddRecord: (values: WhmAddDnsRecordInput) => Promise<unknown>;
  emptyMessage?: string;
}

/**
 * WHM DNS zone: a records table plus an "Add Record" modal. Shared by
 * DnsZone.tsx (the hosting-account-scoped DNS page) and DomainDetails.tsx's
 * own-server DNS section (a domain with no hosting account of its own).
 *
 * Add-only, deliberately, on both call sites: WHM's line-number-based
 * edit/remove calls proved unreliable during live verification — the line
 * numbers WHM reports for a zone don't reliably match what those calls
 * themselves expect for the same zone, which cost two real customer
 * records before it was caught. Fixing or removing an existing record
 * means asking someone with direct WHM access to do it there, for now.
 */
export default function WhmDnsSection({ domain, records, isLoading, isError, canAdd, onAddRecord, emptyMessage }: WhmDnsSectionProps) {
  const [addOpen, setAddOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const form = useForm<FormValues>({
    initialValues: { type: 'A', name: '', ttl: 14400, value: '', priority: 10 },
    validate: {
      name: (v) => (v.trim() ? null : 'Required'),
      value: (v, values) => (values.type !== 'MX' && !v.trim() ? 'Required' : null),
    },
  });

  const openAdd = () => { form.reset(); setAddOpen(true); };

  const submit = async (v: FormValues) => {
    setSubmitting(true);
    try {
      await onAddRecord({
        type: v.type,
        name: v.name.trim(),
        ttl: v.ttl,
        value: v.value.trim() || undefined,
        priority: v.type === 'MX' ? v.priority : undefined,
      });
      notifications.show({ title: 'Added', message: 'DNS record added.', color: 'green' });
      setAddOpen(false);
    } catch (e: any) {
      notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to add the record.', color: 'red' });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack gap="sm">
      <Group justify="space-between" wrap="wrap">
        <Text size="sm" c="dimmed" maw={520}>
          Records straight from WHM. Adding one is supported — editing or removing an existing record isn't
          yet (a WHM reliability issue found during testing means that's safer to ask someone with direct WHM
          access to do for now).
        </Text>
        {canAdd && (
          <Button size="xs" leftSection={<IconPlus size={14} />} onClick={openAdd}>Add Record</Button>
        )}
      </Group>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : isError ? (
          <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
            Could not load the DNS zone for {domain}.
          </Alert>
        ) : records.length === 0 ? (
          <Center py="xl"><Text c="dimmed">{emptyMessage ?? `No records found for ${domain}.`}</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={700}>
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

      <Modal opened={addOpen} onClose={() => setAddOpen(false)} title={`Add DNS Record — ${domain}`} size="md">
        <form onSubmit={form.onSubmit(submit)}>
          <Stack>
            <Select label="Type" required data={RECORD_TYPES} {...form.getInputProps('type')} />
            <TextInput label="Name" required placeholder={`e.g. sub.${domain} or sub`}
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
              <Button type="submit" loading={submitting}>Add Record</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

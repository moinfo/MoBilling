import { useState } from 'react';
import {
  Stack, Paper, Text, Group, Badge, Table, Center, Loader, Alert,
  Button, Modal, TextInput, NumberInput, Select, ActionIcon, Tooltip,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { IconAlertTriangle, IconPlus, IconInfoCircle, IconPencil, IconTrash } from '@tabler/icons-react';

export interface WhmDnsRecord {
  type: string;
  name: string;
  ttl: number;
  data: string[];
}

export type WhmDnsRecordType = 'A' | 'AAAA' | 'CNAME' | 'TXT' | 'MX';
const RECORD_TYPES: WhmDnsRecordType[] = ['A', 'AAAA', 'CNAME', 'TXT', 'MX'];
/** SOA/NS are the zone's own structural records — never editable/removable here, same restriction the backend enforces. */
const EDITABLE_TYPES: string[] = RECORD_TYPES;

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

export interface WhmEditDnsRecordInput {
  old: WhmDnsRecord;
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
  /** Omit to keep add-only (edit/remove buttons hidden). */
  onEditRecord?: (values: WhmEditDnsRecordInput) => Promise<unknown>;
  onRemoveRecord?: (old: WhmDnsRecord) => Promise<unknown>;
  emptyMessage?: string;
}

/**
 * WHM DNS zone: a records table plus Add/Edit/Remove. Shared by DnsZone.tsx
 * (the hosting-account-scoped DNS page), DomainDetails.tsx's own-server DNS
 * section, and the portal's DNS Records tab.
 *
 * Edit/remove target the right record by re-verifying its identity against
 * the LIVE zone immediately before mutating (WhmService::editDnsRecord()/
 * removeDnsRecord()) — never by a cached line number — after an earlier,
 * naive line-number approach cost two real customer records (caught and
 * restored) before this safer mechanism was built and verified live
 * against a disposable test zone. SOA/NS rows have no Edit/Remove — those
 * are the zone's own structural records.
 */
export default function WhmDnsSection({
  domain, records, isLoading, isError, canAdd, onAddRecord, onEditRecord, onRemoveRecord, emptyMessage,
}: WhmDnsSectionProps) {
  const [addOpen, setAddOpen] = useState(false);
  const [editing, setEditing] = useState<WhmDnsRecord | null>(null);
  const [removing, setRemoving] = useState<WhmDnsRecord | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [removeSubmitting, setRemoveSubmitting] = useState(false);

  const form = useForm<FormValues>({
    initialValues: { type: 'A', name: '', ttl: 14400, value: '', priority: 10 },
    validate: {
      name: (v) => (v.trim() ? null : 'Required'),
      value: (v, values) => (values.type !== 'MX' && !v.trim() ? 'Required' : null),
    },
  });

  const openAdd = () => { form.reset(); setAddOpen(true); };

  const openEdit = (r: WhmDnsRecord) => {
    const isMx = r.type === 'MX';
    form.setValues({
      type: r.type as WhmDnsRecordType,
      name: r.name,
      ttl: r.ttl,
      value: isMx ? (r.data[1] ?? '') : (r.data[0] ?? ''),
      priority: isMx ? Number(r.data[0] ?? 10) : 10,
    });
    setEditing(r);
  };

  const submitAdd = async (v: FormValues) => {
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

  const submitEdit = async (v: FormValues) => {
    if (!editing || !onEditRecord) return;
    setSubmitting(true);
    try {
      await onEditRecord({
        old: editing,
        ttl: v.ttl,
        value: v.value.trim() || undefined,
        priority: v.type === 'MX' ? v.priority : undefined,
      });
      notifications.show({ title: 'Updated', message: 'DNS record updated.', color: 'green' });
      setEditing(null);
    } catch (e: any) {
      notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to update the record.', color: 'red' });
    } finally {
      setSubmitting(false);
    }
  };

  const confirmRemove = async () => {
    if (!removing || !onRemoveRecord) return;
    setRemoveSubmitting(true);
    try {
      await onRemoveRecord(removing);
      notifications.show({ title: 'Removed', message: 'DNS record removed.', color: 'green' });
      setRemoving(null);
    } catch (e: any) {
      notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to remove the record.', color: 'red' });
    } finally {
      setRemoveSubmitting(false);
    }
  };

  const canEditOrRemove = canAdd && (onEditRecord || onRemoveRecord);

  return (
    <Stack gap="sm">
      <Group justify="space-between" wrap="wrap">
        <Text size="sm" c="dimmed" maw={520}>
          Records straight from WHM.
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
                  {canEditOrRemove && <Table.Th w={80} />}
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {records.map((r, i) => {
                  const editable = EDITABLE_TYPES.includes(r.type);
                  return (
                    <Table.Tr key={i}>
                      <Table.Td c="dimmed">{i + 1}</Table.Td>
                      <Table.Td>
                        <Badge size="sm" variant="light" color={typeColors[r.type] ?? 'dark'}>{r.type}</Badge>
                      </Table.Td>
                      <Table.Td fw={500} fz="sm">{r.name}</Table.Td>
                      <Table.Td fz="sm" c="dimmed">{r.ttl}</Table.Td>
                      <Table.Td fz="sm" style={{ wordBreak: 'break-all' }}>{r.data.join('  ·  ')}</Table.Td>
                      {canEditOrRemove && (
                        <Table.Td>
                          {editable && (
                            <Group gap={4} wrap="nowrap">
                              {onEditRecord && (
                                <Tooltip label="Edit">
                                  <ActionIcon size="sm" variant="subtle" onClick={() => openEdit(r)}>
                                    <IconPencil size={14} />
                                  </ActionIcon>
                                </Tooltip>
                              )}
                              {onRemoveRecord && (
                                <Tooltip label="Remove">
                                  <ActionIcon size="sm" variant="subtle" color="red" onClick={() => setRemoving(r)}>
                                    <IconTrash size={14} />
                                  </ActionIcon>
                                </Tooltip>
                              )}
                            </Group>
                          )}
                        </Table.Td>
                      )}
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      <Modal opened={addOpen} onClose={() => setAddOpen(false)} title={`Add DNS Record — ${domain}`} size="md">
        <form onSubmit={form.onSubmit(submitAdd)}>
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

      <Modal opened={!!editing} onClose={() => setEditing(null)} title={`Edit ${editing?.type} Record — ${editing?.name}`} size="md">
        <form onSubmit={form.onSubmit(submitEdit)}>
          <Stack>
            <TextInput label="Name" value={form.values.name} disabled
              description="Type and name can't be changed here — remove and re-add instead." />
            <NumberInput label="TTL (seconds)" required min={60} {...form.getInputProps('ttl')} />
            {form.values.type === 'MX' ? (
              <>
                <NumberInput label="Priority" required min={0} {...form.getInputProps('priority')} />
                <TextInput label="Mail Server" required {...form.getInputProps('value')} />
              </>
            ) : (
              <TextInput label="Value" required {...form.getInputProps('value')} />
            )}
            <Alert color="blue" variant="light" icon={<IconInfoCircle size={16} />}>
              DNS changes can take a few hours to propagate. Double-check the value before saving.
            </Alert>
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Changes</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      <Modal opened={!!removing} onClose={() => setRemoving(null)} title="Remove DNS Record?" size="sm">
        <Stack>
          <Text size="sm">
            Remove the <Badge size="sm" variant="light" color={typeColors[removing?.type ?? ''] ?? 'dark'}>{removing?.type}</Badge>{' '}
            record <b>{removing?.name}</b> → <Text span fz="sm" c="dimmed">{removing?.data.join('  ·  ')}</Text>?
          </Text>
          <Alert color="orange" variant="light">This can take a few hours to stop resolving everywhere. It can't be undone from here.</Alert>
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setRemoving(null)}>Cancel</Button>
            <Button color="red" loading={removeSubmitting} onClick={confirmRemove}>Remove</Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}

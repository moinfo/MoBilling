import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, Textarea,
  Select, Button, Group, Text, Loader, Center, Paper, Tooltip, CopyButton, Pagination,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconCopy, IconCheck, IconLockOpen, IconRefresh } from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getLicenses, createLicense, updateLicense, unbindLicenseDomain, deleteLicense,
  License, LicenseBillingPeriod, LicenseCreateFormData, LicenseUpdateFormData,
} from '../../api/admin';

const statusColors: Record<License['status'], string> = {
  active: 'green', suspended: 'red', expired: 'gray',
};

const billingPeriodLabels: Record<LicenseBillingPeriod, string> = {
  perpetual: 'Perpetual (no expiry)',
  monthly: 'Monthly',
  quarterly: 'Quarterly (3 months)',
  semi_annual: 'Semi-Annual (6 months)',
  annual: 'Annual (12 months)',
};

const PERIOD_MONTHS: Partial<Record<LicenseBillingPeriod, number>> = {
  monthly: 1, quarterly: 3, semi_annual: 6, annual: 12,
};

// Mirrors License::calculateExpiry() on the backend — client-side preview only.
function previewExpiry(startsAt: Date | null, period: LicenseBillingPeriod): string {
  if (period === 'perpetual') return 'No expiry';
  if (!startsAt) return '—';
  const months = PERIOD_MONTHS[period];
  return dayjs(startsAt).add(months ?? 0, 'month').format('DD MMM YYYY');
}

export default function Licenses() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [editLicense, setEditLicense] = useState<License | null>(null);
  const [renewLicense, setRenewLicense] = useState<License | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-licenses', page],
    queryFn: () => getLicenses({ page }),
  });

  const licenses: License[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const deleteMut = useMutation({
    mutationFn: deleteLicense,
    onSuccess: () => {
      notifications.show({ title: 'Deleted', message: 'License deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-licenses'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red',
    }),
  });

  const unbindMut = useMutation({
    mutationFn: unbindLicenseDomain,
    onSuccess: () => {
      notifications.show({ title: 'Unbound', message: 'Domain cleared — license can now activate on a new install.', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-licenses'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to unbind', color: 'red',
    }),
  });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>Licenses</Title>
          <Text c="dimmed">Self-hosted install licenses (WHMCS-style) — each key is locked to the domain that first activates it.</Text>
        </div>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>
          Issue License
        </Button>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={900}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Customer</Table.Th>
                  <Table.Th>License Key</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Expires</Table.Th>
                  <Table.Th>Last Check-in</Table.Th>
                  <Table.Th w={180}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {licenses.map((lic) => (
                  <Table.Tr key={lic.id}>
                    <Table.Td>
                      <Text fw={500}>{lic.customer_name}</Text>
                      <Text size="xs" c="dimmed">{lic.customer_email}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4} wrap="nowrap">
                        <Text size="sm" ff="monospace">{lic.license_key}</Text>
                        <CopyButton value={lic.license_key}>
                          {({ copied, copy }) => (
                            <Tooltip label={copied ? 'Copied' : 'Copy key'}>
                              <ActionIcon variant="subtle" size="sm" color={copied ? 'teal' : 'gray'} onClick={copy}>
                                {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                              </ActionIcon>
                            </Tooltip>
                          )}
                        </CopyButton>
                      </Group>
                    </Table.Td>
                    <Table.Td>{lic.domain || <Text c="dimmed" size="sm">Not activated yet</Text>}</Table.Td>
                    <Table.Td><Badge color={statusColors[lic.status]} variant="light">{lic.status}</Badge></Table.Td>
                    <Table.Td>{lic.expires_at ? dayjs(lic.expires_at).format('DD MMM YYYY') : 'Perpetual'}</Table.Td>
                    <Table.Td>{lic.last_validated_at ? dayjs(lic.last_validated_at).format('DD MMM YYYY HH:mm') : 'Never'}</Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        <ActionIcon variant="subtle" onClick={() => setEditLicense(lic)}>
                          <IconEdit size={16} />
                        </ActionIcon>
                        <Tooltip label="Renew (extend expiry)">
                          <ActionIcon variant="subtle" color="teal" onClick={() => setRenewLicense(lic)}>
                            <IconRefresh size={16} />
                          </ActionIcon>
                        </Tooltip>
                        {lic.domain && (
                          <Tooltip label="Unbind domain (move to a new install)">
                            <ActionIcon variant="subtle" color="orange" loading={unbindMut.isPending}
                              onClick={() => {
                                if (confirm(`Unbind "${lic.domain}" from this license?`)) unbindMut.mutate(lic.id);
                              }}>
                              <IconLockOpen size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        <ActionIcon variant="subtle" color="red" loading={deleteMut.isPending}
                          onClick={() => {
                            if (confirm(`Delete license for "${lic.customer_name}"?`)) deleteMut.mutate(lic.id);
                          }}>
                          <IconTrash size={16} />
                        </ActionIcon>
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
                {licenses.length === 0 && (
                  <Table.Tr>
                    <Table.Td colSpan={7}>
                      <Text ta="center" c="dimmed" py="md">No licenses issued yet</Text>
                    </Table.Td>
                  </Table.Tr>
                )}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal opened={createOpen} onClose={() => setCreateOpen(false)} title="Issue License">
        <CreateForm onSaved={() => { queryClient.invalidateQueries({ queryKey: ['admin-licenses'] }); setCreateOpen(false); }} />
      </Modal>

      <Modal opened={!!editLicense} onClose={() => setEditLicense(null)} title={`Edit — ${editLicense?.customer_name}`}>
        {editLicense && (
          <EditForm existing={editLicense} onSaved={() => { queryClient.invalidateQueries({ queryKey: ['admin-licenses'] }); setEditLicense(null); }} />
        )}
      </Modal>

      <Modal opened={!!renewLicense} onClose={() => setRenewLicense(null)} title={`Renew — ${renewLicense?.customer_name}`}>
        {renewLicense && (
          <RenewForm existing={renewLicense} onSaved={() => { queryClient.invalidateQueries({ queryKey: ['admin-licenses'] }); setRenewLicense(null); }} />
        )}
      </Modal>
    </>
  );
}

const billingPeriodOptions = (Object.keys(billingPeriodLabels) as LicenseBillingPeriod[])
  .map((value) => ({ value, label: billingPeriodLabels[value] }));

function CreateForm({ onSaved }: { onSaved: () => void }) {
  const form = useForm<LicenseCreateFormData>({
    initialValues: {
      customer_name: '', customer_email: '',
      starts_at: dayjs().format('YYYY-MM-DD'),
      billing_period: 'annual',
      notes: '',
    },
    validate: {
      customer_name: (v) => (v.trim() ? null : 'Required'),
      customer_email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email required'),
    },
  });

  const mutation = useMutation({
    mutationFn: (values: LicenseCreateFormData) => createLicense(values),
    onSuccess: (res) => {
      notifications.show({ title: 'License issued', message: `Key: ${res.data.data.license_key}`, color: 'green' });
      onSaved();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to issue license', color: 'red',
    }),
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput label="Customer Name" required {...form.getInputProps('customer_name')} />
        <TextInput label="Customer Email" required {...form.getInputProps('customer_email')} />
        <DateInput label="Start Date" required
          value={new Date(form.values.starts_at)}
          onChange={(v) => v && form.setFieldValue('starts_at', dayjs(v as unknown as string).format('YYYY-MM-DD'))} />
        <Select label="Billing Period" data={billingPeriodOptions} allowDeselect={false}
          {...form.getInputProps('billing_period')} />
        <Text size="sm">Expires: <Text span fw={600}>{previewExpiry(new Date(form.values.starts_at), form.values.billing_period)}</Text></Text>
        <Textarea label="Notes" placeholder="e.g. Sold via invoice #123" minRows={2} {...form.getInputProps('notes')} />
        <Text size="xs" c="dimmed">The license key is generated automatically and locks to whichever domain first checks in.</Text>
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>Issue License</Button>
        </Group>
      </Stack>
    </form>
  );
}

function EditForm({ existing, onSaved }: { existing: License; onSaved: () => void }) {
  const form = useForm<LicenseUpdateFormData>({
    initialValues: {
      customer_name: existing.customer_name,
      customer_email: existing.customer_email,
      status: existing.status,
      notes: existing.notes ?? '',
    },
  });

  const mutation = useMutation({
    mutationFn: (values: LicenseUpdateFormData) => updateLicense(existing.id, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'License updated', color: 'green' });
      onSaved();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to update license', color: 'red',
    }),
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput label="Customer Name" required {...form.getInputProps('customer_name')} />
        <TextInput label="Customer Email" required {...form.getInputProps('customer_email')} />
        <Select label="Status" data={[
          { value: 'active', label: 'Active' },
          { value: 'suspended', label: 'Suspended' },
          { value: 'expired', label: 'Expired' },
        ]} allowDeselect={false} {...form.getInputProps('status')} />
        <Textarea label="Notes" minRows={2} {...form.getInputProps('notes')} />
        <Text size="xs" c="dimmed">To extend the expiry date, use the Renew action instead.</Text>
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>Save</Button>
        </Group>
      </Stack>
    </form>
  );
}

function RenewForm({ existing, onSaved }: { existing: License; onSaved: () => void }) {
  // Renewing before expiry should extend from where the current period ends,
  // not from today (otherwise the customer loses the time they already paid
  // for). Only default to today if there's no expiry yet or it's already past.
  const defaultStart = existing.expires_at && dayjs(existing.expires_at).isAfter(dayjs())
    ? existing.expires_at
    : dayjs().format('YYYY-MM-DD');

  const form = useForm<{ starts_at: string; billing_period: LicenseBillingPeriod }>({
    initialValues: {
      starts_at: defaultStart,
      billing_period: existing.billing_period === 'perpetual' ? 'annual' : existing.billing_period,
    },
  });

  const mutation = useMutation({
    mutationFn: (values: { starts_at: string; billing_period: LicenseBillingPeriod }) =>
      updateLicense(existing.id, {
        customer_name: existing.customer_name,
        customer_email: existing.customer_email,
        status: existing.status === 'expired' ? 'active' : existing.status,
        starts_at: values.starts_at,
        billing_period: values.billing_period,
      }),
    onSuccess: () => {
      notifications.show({ title: 'Renewed', message: 'License expiry extended.', color: 'green' });
      onSaved();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to renew license', color: 'red',
    }),
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <Text size="sm" c="dimmed">Current expiry: {existing.expires_at ? dayjs(existing.expires_at).format('DD MMM YYYY') : 'Perpetual'}</Text>
        <Select label="Billing Period" data={billingPeriodOptions} allowDeselect={false}
          {...form.getInputProps('billing_period')} />
        <DateInput label="Extend From" description="Defaults to the current expiry date so no paid time is lost" required
          value={new Date(form.values.starts_at)}
          onChange={(v) => v && form.setFieldValue('starts_at', dayjs(v as unknown as string).format('YYYY-MM-DD'))} />
        <Text size="sm">New expiry: <Text span fw={600}>{previewExpiry(new Date(form.values.starts_at), form.values.billing_period)}</Text></Text>
        <Group justify="flex-end">
          <Button type="submit" color="teal" loading={mutation.isPending}>Renew</Button>
        </Group>
      </Stack>
    </form>
  );
}

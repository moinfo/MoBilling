import { useState } from 'react';
import {
  Stack, Group, Button, Table, Badge, ActionIcon, Tooltip, Modal, TextInput,
  NumberInput, Switch, Text, Paper, Loader, Center, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconPlus, IconEdit, IconTrash, IconPlugConnected, IconWorldWww, IconAlertCircle } from '@tabler/icons-react';
import {
  getRegistrarAccounts, testRegistrarAccount, getDomainTlds,
  createDomainTld, updateDomainTld, deleteDomainTld,
  RegistrarAccountRow, DomainTldRow,
} from '../../api/domains';
import { formatCurrency } from '../../utils/formatCurrency';

export default function DomainsTab() {
  return (
    <Stack gap="xl">
      <RegistrarAccountsSection />
      <TldPricingSection />
    </Stack>
  );
}

function RegistrarAccountsSection() {
  const [testingId, setTestingId] = useState<string | null>(null);
  const [credits, setCredits] = useState<{ id: string; rows: { zone: string; credit: string }[] } | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['registrar-accounts'], queryFn: getRegistrarAccounts });
  const accounts: RegistrarAccountRow[] = data?.data?.data ?? [];

  const handleTest = async (a: RegistrarAccountRow) => {
    setTestingId(a.id);
    setCredits(null);
    try {
      const res = await testRegistrarAccount(a.id);
      setCredits({ id: a.id, rows: res.data.credits });
      notifications.show({ message: 'Registry connection OK.', color: 'green' });
    } catch (e: any) {
      notifications.show({
        title: 'Connection failed',
        message: e?.response?.data?.message ?? 'Could not reach the registrar service.',
        color: 'red',
      });
    } finally {
      setTestingId(null);
    }
  };

  return (
    <Stack>
      <Group gap="xs">
        <IconWorldWww size={20} />
        <Text fw={600}>Registrar Accounts (.tz)</Text>
      </Group>

      {isLoading ? (
        <Center py="md"><Loader size="sm" /></Center>
      ) : (
        <Paper withBorder radius="md">
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Registrar ID</Table.Th>
                <Table.Th>Domains</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {accounts.map((a) => (
                <Table.Tr key={a.id}>
                  <Table.Td fw={500}>{a.name}</Table.Td>
                  <Table.Td>{a.registrar_id ?? '—'}</Table.Td>
                  <Table.Td>{a.domains_count}</Table.Td>
                  <Table.Td>
                    <Badge size="sm" variant="light" color={a.is_platform ? 'blue' : 'grape'}>
                      {a.is_platform ? 'Platform (shared)' : 'Own accreditation'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Badge size="sm" color={a.is_active ? 'green' : 'gray'} variant="light">
                      {a.is_active ? 'Active' : 'Inactive'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Tooltip label="Test connection (registry credit)">
                      <ActionIcon variant="light" color="teal" loading={testingId === a.id}
                        onClick={() => handleTest(a)}>
                        <IconPlugConnected size={15} />
                      </ActionIcon>
                    </Tooltip>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      {credits && (
        <Paper withBorder p="sm" radius="md">
          <Text size="sm" fw={600} mb={4}>Registry credit balances:</Text>
          <Group gap="sm">
            {credits.rows.length === 0
              ? <Text size="sm" c="dimmed">No zones with credit</Text>
              : credits.rows.map((c) => (
                  <Badge key={c.zone} variant="outline">{c.zone}: {Number(c.credit).toLocaleString()} TZS</Badge>
                ))}
          </Group>
        </Paper>
      )}
    </Stack>
  );
}

function TldPricingSection() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<DomainTldRow | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['domain-tlds'], queryFn: getDomainTlds });
  const tlds: DomainTldRow[] = data?.data?.data ?? [];

  const saveMutation = useMutation({
    mutationFn: (v: Partial<DomainTldRow>) =>
      editing && !editing.is_platform ? updateDomainTld(editing.id, v) : createDomainTld(v),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['domain-tlds'] });
      notifications.show({ message: 'Pricing saved.', color: 'green' });
      setModalOpen(false);
      setEditing(null);
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Failed to save pricing.', color: 'red',
    }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteDomainTld,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['domain-tlds'] });
      notifications.show({ message: 'Pricing removed.', color: 'gray' });
    },
  });

  const form = useForm({
    initialValues: {
      tld: '', register_price: 0, renew_price: 0, transfer_price: 0,
      years_min: 1, years_max: 10, is_active: true,
    },
  });

  const openModal = (row: DomainTldRow | null) => {
    setEditing(row);
    form.setValues(row ? {
      tld: row.tld, register_price: row.register_price, renew_price: row.renew_price,
      transfer_price: row.transfer_price, years_min: row.years_min, years_max: row.years_max,
      is_active: row.is_active,
    } : {
      tld: '', register_price: 0, renew_price: 0, transfer_price: 0,
      years_min: 1, years_max: 10, is_active: true,
    });
    setModalOpen(true);
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Text fw={600}>TLD Pricing</Text>
        <Button size="xs" leftSection={<IconPlus size={14} />} onClick={() => openModal(null)}>
          Add TLD
        </Button>
      </Group>

      <Alert icon={<IconAlertCircle size={16} />} color="blue" variant="light">
        Prices are per year, charged to your clients when registering, renewing or transferring
        domains. "Platform" rows are shared defaults — add a row with the same TLD to override
        with your own retail price.
      </Alert>

      {isLoading ? (
        <Center py="md"><Loader size="sm" /></Center>
      ) : tlds.length === 0 ? (
        <Text c="dimmed" size="sm">No TLD pricing yet — add .co.tz etc. to enable domain orders.</Text>
      ) : (
        <Paper withBorder radius="md">
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>TLD</Table.Th>
                <Table.Th>Register/yr</Table.Th>
                <Table.Th>Renew/yr</Table.Th>
                <Table.Th>Transfer</Table.Th>
                <Table.Th>Source</Table.Th>
                <Table.Th>Active</Table.Th>
                <Table.Th></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {tlds.map((t) => (
                <Table.Tr key={t.id}>
                  <Table.Td fw={500}>.{t.tld}</Table.Td>
                  <Table.Td>{formatCurrency(t.register_price)}</Table.Td>
                  <Table.Td>{formatCurrency(t.renew_price)}</Table.Td>
                  <Table.Td>{formatCurrency(t.transfer_price)}</Table.Td>
                  <Table.Td>
                    <Badge size="xs" variant="light" color={t.is_platform ? 'blue' : 'grape'}>
                      {t.is_platform ? 'Platform' : 'My price'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Badge size="xs" color={t.is_active ? 'green' : 'gray'} variant="light">
                      {t.is_active ? 'Yes' : 'No'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4} justify="flex-end">
                      <Tooltip label={t.is_platform ? 'Override with my price' : 'Edit'}>
                        <ActionIcon variant="light" onClick={() => openModal(t)}>
                          <IconEdit size={15} />
                        </ActionIcon>
                      </Tooltip>
                      {!t.is_platform && (
                        <ActionIcon variant="light" color="red" onClick={() => deleteMutation.mutate(t.id)}>
                          <IconTrash size={15} />
                        </ActionIcon>
                      )}
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)}
        title={editing ? (editing.is_platform ? `Override .${editing.tld} pricing` : `Edit .${editing.tld}`) : 'Add TLD pricing'} centered>
        <form onSubmit={form.onSubmit((v) => saveMutation.mutate(v))}>
          <Stack gap="sm">
            <TextInput label="TLD" placeholder="co.tz" required
              disabled={!!editing}
              {...form.getInputProps('tld')} />
            <Group grow>
              <NumberInput label="Register / year" min={0} required {...form.getInputProps('register_price')} />
              <NumberInput label="Renew / year" min={0} required {...form.getInputProps('renew_price')} />
            </Group>
            <Group grow>
              <NumberInput label="Transfer price" min={0} {...form.getInputProps('transfer_price')} />
              <NumberInput label="Min years" min={1} max={10} {...form.getInputProps('years_min')} />
              <NumberInput label="Max years" min={1} max={10} {...form.getInputProps('years_max')} />
            </Group>
            <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
              <Button type="submit" loading={saveMutation.isPending}>Save</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

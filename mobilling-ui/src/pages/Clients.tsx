import { useState } from 'react';
import {
  Title, Group, Button, TextInput, Modal, Pagination, Stack, PasswordInput, Text,
  Select, SegmentedControl, SimpleGrid, Paper, ThemeIcon,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconPlus, IconSearch, IconDownload, IconAddressBook, IconUsers, IconUserCheck,
  IconUserOff, IconRepeat, IconUserPlus, IconCoins,
} from '@tabler/icons-react';
import { getClients, getClientStats, createClient, updateClient, deleteClient, portalLoginAsClient, changePortalPassword, Client, ClientFormData } from '../api/clients';
import ClientTable from '../components/Billing/ClientTable';
import ClientForm from '../components/Billing/ClientForm';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';

type SortKey = 'name' | 'subscriptions' | 'amount' | 'newest';
type SubsFilter = 'all' | 'with' | 'without';

function StatCard({ icon, color, label, value }: { icon: React.ReactNode; color: string; label: string; value: string | number }) {
  return (
    <Paper withBorder radius="md" p="sm">
      <Group gap="sm" wrap="nowrap">
        <ThemeIcon variant="light" color={color} size={38} radius="md">{icon}</ThemeIcon>
        <div style={{ minWidth: 0 }}>
          <Text size="lg" fw={700} lh={1.2} truncate>{value}</Text>
          <Text size="xs" c="dimmed" truncate>{label}</Text>
        </div>
      </Group>
    </Paper>
  );
}

export default function Clients() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SortKey>('name');
  const [subsFilter, setSubsFilter] = useState<SubsFilter>('all');
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Client | null>(null);
  const [passwordClient, setPasswordClient] = useState<Client | null>(null);

  const listParams = {
    search: debouncedSearch || undefined,
    sort,
    has_subscriptions: subsFilter === 'all' ? undefined : subsFilter === 'with' ? (1 as const) : (0 as const),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['clients', debouncedSearch, page, sort, subsFilter],
    queryFn: () => getClients({ ...listParams, page }),
  });

  const { data: statsData } = useQuery({
    queryKey: ['client-stats'],
    queryFn: getClientStats,
  });
  const stats = statsData?.data?.data;

  const clients = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: ClientFormData) => createClient(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'Client created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create client', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: ClientFormData) => updateClient(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Client updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update client', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteClient(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] });
      notifications.show({ title: 'Success', message: 'Client deleted', color: 'green' });
    },
  });

  const handleEdit = (client: Client) => {
    setEditing(client);
    setModalOpen(true);
  };

  const handleDelete = (client: Client) => {
    modals.openConfirmModal({
      title: 'Delete Client',
      children: `Are you sure you want to delete "${client.name}"?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(client.id),
    });
  };

  const handleExportCsv = async () => {
    try {
      const res = await getClients({ ...listParams, per_page: 10000 });
      const allClients: Client[] = res.data?.data || [];
      const canSeeValue = can('client_profile.subscription_value');
      const esc = (v: string | number | null | undefined) => `"${String(v ?? '').replace(/"/g, '""')}"`;
      const header = ['Name', 'Email', 'Phone', 'Address', 'TIN', 'Active Subscriptions'];
      if (canSeeValue) header.push('Subscription Amount');
      const csvRows = [
        header.join(','),
        ...allClients.map((c) => {
          const row = [esc(c.name), esc(c.email), esc(c.phone), esc(c.address), esc(c.tax_id), c.active_subscriptions_count ?? 0];
          if (canSeeValue) row.push(Number(c.subscription_total ?? 0));
          return row.join(',');
        }),
      ];
      const blob = new Blob([csvRows.join('\n')], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `clients-${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      notifications.show({ title: 'Exported', message: `${allClients.length} clients exported to CSV`, color: 'green' });
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to export clients', color: 'red' });
    }
  };

  const handleExportVcf = async () => {
    try {
      const res = await getClients({ ...listParams, per_page: 10000 });
      const allClients: Client[] = res.data?.data || [];
      const vcards = allClients.map((c) => {
        const nameParts = (c.name || '').trim().split(/\s+/);
        const lastName = nameParts.length > 1 ? nameParts.pop() : '';
        const firstName = nameParts.join(' ');
        const lines = [
          'BEGIN:VCARD',
          'VERSION:3.0',
          `FN:${c.name || ''}`,
          `N:${lastName};${firstName};;;`,
        ];
        if (c.email) lines.push(`EMAIL:${c.email}`);
        if (c.phone) lines.push(`TEL;TYPE=CELL:${c.phone}`);
        if (c.address) lines.push(`ADR;TYPE=WORK:;;${c.address};;;;`);
        lines.push('END:VCARD');
        return lines.join('\r\n');
      });
      const blob = new Blob([vcards.join('\r\n')], { type: 'text/vcard' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `clients-${new Date().toISOString().slice(0, 10)}.vcf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to export contacts', color: 'red' });
    }
  };

  const handlePortalLogin = async (client: Client) => {
    try {
      const res = await portalLoginAsClient(client.id);
      const { token, user, user_type, permissions } = res.data;
      // Store current session to allow returning later
      const currentToken = localStorage.getItem('token');
      const currentUser = localStorage.getItem('user');
      if (currentToken) localStorage.setItem('impersonate_return_token', currentToken);
      if (currentUser) localStorage.setItem('impersonate_return_user', currentUser);
      // Login as portal user
      localStorage.setItem('token', token);
      localStorage.setItem('user', JSON.stringify({ ...user, user_type, permissions }));
      notifications.show({ title: 'Logged in as client', message: res.data.message, color: 'violet' });
      window.location.href = '/portal/dashboard';
    } catch (err: any) {
      notifications.show({ title: 'Error', message: err.response?.data?.message || 'No portal user found', color: 'red' });
    }
  };

  const passwordForm = useForm({
    initialValues: { password: '', password_confirmation: '' },
    validate: {
      password: (v) => (v.length >= 8 ? null : 'Min 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  const handleChangePassword = async (values: { password: string }) => {
    if (!passwordClient) return;
    try {
      const res = await changePortalPassword(passwordClient.id, values.password);
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
      setPasswordClient(null);
      passwordForm.reset();
    } catch (err: any) {
      notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to change password', color: 'red' });
    }
  };

  const handleSubmit = (values: ClientFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Clients</Title>
        <Group gap="xs">
          <Button variant="light" leftSection={<IconDownload size={16} />} onClick={handleExportCsv}>
            Export CSV
          </Button>
          <Button variant="light" leftSection={<IconAddressBook size={16} />} onClick={handleExportVcf}>
            Export VCF
          </Button>
          {can('clients.create') && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
              Add Client
            </Button>
          )}
        </Group>
      </Group>

      <SimpleGrid cols={{ base: 2, sm: 3, lg: stats?.subscription_value !== undefined ? 6 : 5 }} spacing="sm" mb="md">
        <StatCard icon={<IconUsers size={20} />} color="blue" label="Total Clients" value={stats?.total_clients ?? '—'} />
        <StatCard icon={<IconUserCheck size={20} />} color="green" label="With Subscriptions" value={stats?.with_subscriptions ?? '—'} />
        <StatCard icon={<IconUserOff size={20} />} color="gray" label="Without Subscriptions" value={stats?.without_subscriptions ?? '—'} />
        <StatCard icon={<IconRepeat size={20} />} color="violet" label="Active Subscriptions" value={stats?.active_subscriptions ?? '—'} />
        <StatCard icon={<IconUserPlus size={20} />} color="teal" label="New This Month" value={stats?.new_this_month ?? '—'} />
        {stats?.subscription_value !== undefined && (
          <StatCard icon={<IconCoins size={20} />} color="orange" label="Subscription Value" value={formatCurrency(stats.subscription_value)} />
        )}
      </SimpleGrid>

      <Group mb="md" gap="sm" wrap="wrap">
        <TextInput
          placeholder="Search clients..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          maw={300}
        />
        <SegmentedControl
          size="sm"
          value={subsFilter}
          onChange={(v) => { setSubsFilter(v as SubsFilter); setPage(1); }}
          data={[
            { label: 'All', value: 'all' },
            { label: 'With Subscriptions', value: 'with' },
            { label: 'No Subscriptions', value: 'without' },
          ]}
        />
        <Select
          size="sm"
          w={210}
          value={sort}
          onChange={(v) => { setSort((v as SortKey) ?? 'name'); setPage(1); }}
          data={[
            { label: 'Sort: Name (A–Z)', value: 'name' },
            { label: 'Sort: Most Subscriptions', value: 'subscriptions' },
            { label: 'Sort: Highest Sub. Amount', value: 'amount' },
            { label: 'Sort: Newest First', value: 'newest' },
          ]}
          allowDeselect={false}
        />
      </Group>

      <ClientTable
        clients={clients}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onPortalLogin={handlePortalLogin}
        onChangePassword={(c) => { setPasswordClient(c); passwordForm.reset(); }}
        startIndex={meta ? (meta.current_page - 1) * meta.per_page + 1 : 1}
        loading={isLoading}
      />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={modalOpen}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Client' : 'New Client'}
        size="md"
      >
        <ClientForm
          initialValues={editing ? {
            name: editing.name,
            email: editing.email || '',
            phone: editing.phone || '',
            address: editing.address || '',
            tax_id: editing.tax_id || '',
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>

      <Modal
        opened={!!passwordClient}
        onClose={() => { setPasswordClient(null); passwordForm.reset(); }}
        title="Change Portal Password"
        size="sm"
      >
        {passwordClient && (
          <form onSubmit={passwordForm.onSubmit(handleChangePassword)}>
            <Stack>
              <Text size="sm">Change portal password for <Text span fw={600}>{passwordClient.name}</Text></Text>
              <PasswordInput label="New Password" required {...passwordForm.getInputProps('password')} />
              <PasswordInput label="Confirm Password" required {...passwordForm.getInputProps('password_confirmation')} />
              <Group justify="flex-end">
                <Button variant="default" onClick={() => setPasswordClient(null)}>Cancel</Button>
                <Button type="submit" color="orange">Change Password</Button>
              </Group>
            </Stack>
          </form>
        )}
      </Modal>
    </>
  );
}

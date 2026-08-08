import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Tooltip, Modal, Button, Alert, SegmentedControl,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate } from 'react-router-dom';
import {
  IconServerBolt, IconSearch, IconExternalLink, IconAlertTriangle, IconPlus,
} from '@tabler/icons-react';
import {
  discoverHostingAccounts, importHostingAccount, getServers, DiscoveredAccount,
} from '../api/hosting';
import { getClients } from '../api/clients';
import { getProductServices } from '../api/productServices';

/**
 * Cross-checks every cPanel account that actually exists on the WHM
 * server(s) against hosting_accounts, so staff can see accounts created
 * directly on the server (or missed during the WHMCS import) that were
 * never linked to a client here, and import them in one step.
 */
export default function DiscoverHostingAccounts() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [serverId, setServerId] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'unimported' | 'imported'>('unimported');
  const [importing, setImporting] = useState<DiscoveredAccount | null>(null);

  const { data: serversData } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['discover-hosting', serverId, filter],
    queryFn: () => discoverHostingAccounts({
      server_id: serverId || undefined,
      imported: filter === 'all' ? undefined : filter === 'imported' ? 1 : 0,
    }),
    staleTime: 60_000,
  });

  const rows = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const filtered = debouncedSearch
    ? rows.filter((r) =>
        r.cpanel_username.toLowerCase().includes(debouncedSearch.toLowerCase())
        || (r.domain ?? '').toLowerCase().includes(debouncedSearch.toLowerCase())
        || (r.client?.name ?? '').toLowerCase().includes(debouncedSearch.toLowerCase()))
    : rows;

  const unimportedCount = rows.filter((r) => !r.imported).length;

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconServerBolt size={22} /> Discover cPanel Accounts</Group>
        </Title>
        {!isLoading && (
          <Badge size="lg" color={unimportedCount > 0 ? 'orange' : 'teal'} variant="light">
            {unimportedCount} not imported
          </Badge>
        )}
      </Group>

      <Text size="sm" c="dimmed">
        Every account WHM actually has, matched against what's tracked here — so accounts created
        directly on the server, or missed during import, don't go unbilled.
      </Text>

      {errors.length > 0 && (
        <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />}>
          {errors.join(' · ')}
        </Alert>
      )}

      <Paper withBorder p="sm" radius="sm">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search username, domain, or client…" leftSection={<IconSearch size={14} />}
            value={search} onChange={(e) => setSearch(e.currentTarget.value)}
            style={{ flex: 1, minWidth: 240 }}
          />
          {servers.length > 1 && (
            <Select placeholder="Server" clearable w={200} value={serverId} onChange={setServerId}
              data={servers.map((s) => ({ value: s.id, label: s.name }))} />
          )}
          <SegmentedControl value={filter} onChange={(v) => setFilter(v as typeof filter)}
            data={[
              { value: 'unimported', label: 'Not imported' },
              { value: 'imported', label: 'Imported' },
              { value: 'all', label: 'All' },
            ]} />
        </Group>
      </Paper>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : filtered.length === 0 ? (
          <Center py="xl"><Text c="dimmed">{isFetching ? 'Refreshing…' : 'No accounts found.'}</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={820}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>cPanel User</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Plan</Table.Th>
                  <Table.Th>Disk</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {filtered.map((r) => (
                  <Table.Tr key={`${r.server_id}-${r.cpanel_username}`}>
                    <Table.Td fw={500}>{r.cpanel_username}</Table.Td>
                    <Table.Td>{r.domain ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.plan ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.disk_used ?? '—'} / {r.disk_limit ?? '—'}</Table.Td>
                    <Table.Td>
                      <Badge size="sm" variant="light" color={r.suspended ? 'orange' : 'teal'}>
                        {r.suspended ? 'Suspended' : 'Active'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      {r.client ? (
                        <Group gap={4} wrap="nowrap">
                          <Text size="sm">{r.client.name}</Text>
                          <ActionIcon variant="subtle" size="xs" onClick={() => navigate(`/clients/${r.client!.id}`)}>
                            <IconExternalLink size={12} />
                          </ActionIcon>
                        </Group>
                      ) : (
                        <Badge size="sm" variant="light" color="gray">Not imported</Badge>
                      )}
                    </Table.Td>
                    <Table.Td>
                      {!r.imported && (
                        <Tooltip label="Import and link to a client">
                          <ActionIcon variant="light" color="blue" size="sm" onClick={() => setImporting(r)}>
                            <IconPlus size={14} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      <ImportModal
        account={importing}
        onClose={() => setImporting(null)}
        onImported={() => qc.invalidateQueries({ queryKey: ['discover-hosting'] })}
      />
    </Stack>
  );
}

function ImportModal({ account, onClose, onImported }: {
  account: DiscoveredAccount | null; onClose: () => void; onImported: () => void;
}) {
  const [clientSearch, setClientSearch] = useState('');
  const [debouncedClientSearch] = useDebouncedValue(clientSearch, 300);
  const [productSearch, setProductSearch] = useState('');
  const [debouncedProductSearch] = useDebouncedValue(productSearch, 300);

  const { data: clientsData } = useQuery({
    queryKey: ['clients-for-import', debouncedClientSearch],
    queryFn: () => getClients({ search: debouncedClientSearch || undefined, per_page: 30 }),
    enabled: !!account,
  });
  const clients = clientsData?.data?.data ?? [];

  const { data: productsData } = useQuery({
    queryKey: ['products-for-import', debouncedProductSearch],
    queryFn: () => getProductServices({ search: debouncedProductSearch || undefined, active_only: true, per_page: 30 }),
    enabled: !!account,
  });
  const products = productsData?.data?.data ?? [];

  const form = useForm({
    initialValues: { client_id: '', product_service_id: '' },
    validate: {
      client_id: (v) => (v ? null : 'Required'),
      product_service_id: (v) => (v ? null : 'Required'),
    },
  });

  const mutation = useMutation({
    mutationFn: () => importHostingAccount({
      server_id: account!.server_id,
      cpanel_username: account!.cpanel_username,
      domain: account!.domain ?? account!.cpanel_username,
      client_id: form.values.client_id,
      product_service_id: form.values.product_service_id,
    }),
    onSuccess: (res) => {
      notifications.show({ title: 'Imported', message: res.data.message, color: 'green' });
      onImported();
      handleClose();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Could not import this account.', color: 'red',
    }),
  });

  const handleClose = () => {
    form.reset();
    setClientSearch('');
    setProductSearch('');
    onClose();
  };

  return (
    <Modal opened={!!account} onClose={handleClose} title={`Import — ${account?.domain ?? account?.cpanel_username}`} centered>
      {account && (
        <form onSubmit={form.onSubmit(() => mutation.mutate())}>
          <Stack gap="sm">
            <Text size="sm" c="dimmed">
              {account.cpanel_username} on {account.server_name}{account.plan ? ` · ${account.plan}` : ''} —
              this creates a subscription and links the account to whoever it belongs to.
            </Text>
            <Select
              label="Client" placeholder="Search by name or email…" required searchable
              data={clients.map((c: any) => ({ value: c.id, label: `${c.name}${c.email ? ` (${c.email})` : ''}` }))}
              searchValue={clientSearch} onSearchChange={setClientSearch}
              value={form.values.client_id} onChange={(v) => form.setFieldValue('client_id', v ?? '')}
              error={form.errors.client_id}
              filter={({ options }) => options}
            />
            <Select
              label="Product / Plan" placeholder="Search products…" required searchable
              data={products.map((p: any) => ({ value: p.id, label: `${p.name}${p.price ? ` — ${p.price}` : ''}` }))}
              searchValue={productSearch} onSearchChange={setProductSearch}
              value={form.values.product_service_id} onChange={(v) => form.setFieldValue('product_service_id', v ?? '')}
              error={form.errors.product_service_id}
              filter={({ options }) => options}
            />
            <Group justify="flex-end" mt="xs">
              <Button variant="default" onClick={handleClose}>Cancel</Button>
              <Button type="submit" loading={mutation.isPending}>Import</Button>
            </Group>
          </Stack>
        </form>
      )}
    </Modal>
  );
}

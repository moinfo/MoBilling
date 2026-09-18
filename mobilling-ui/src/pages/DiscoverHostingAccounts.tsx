import { useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Tooltip, Modal, Button, Alert, SegmentedControl,
  SimpleGrid,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate } from 'react-router-dom';
import {
  IconServerBolt, IconSearch, IconExternalLink, IconAlertTriangle, IconPlus,
  IconServer2, IconCircleCheck, IconCircleDashed, IconAlertOctagon, IconBulb,
} from '@tabler/icons-react';
import {
  discoverHostingAccounts, importHostingAccount, getServers, DiscoveredAccount,
} from '../api/hosting';
import { getClients, Client } from '../api/clients';
import { getProductServices } from '../api/productServices';
import StatCard from '../components/Reports/StatCard';

const normEmail = (e: string | null | undefined) => (e ?? '').trim().toLowerCase();

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
  const [filter, setFilter] = useState<'all' | 'unimported' | 'imported' | 'suspended'>('unimported');
  const [importing, setImporting] = useState<DiscoveredAccount | null>(null);

  const { data: serversData } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['discover-hosting', serverId, filter],
    queryFn: () => discoverHostingAccounts({
      server_id: serverId || undefined,
      imported: filter === 'imported' ? 1 : filter === 'unimported' ? 0 : undefined,
      suspended: filter === 'suspended' ? 1 : undefined,
    }),
    staleTime: 60_000,
  });

  // Independent of the table's own filter, so the counts stay accurate no
  // matter which slice ("Not imported" / "Imported") the table is showing.
  const { data: allData, isLoading: statsLoading } = useQuery({
    queryKey: ['discover-hosting', 'stats', serverId],
    queryFn: () => discoverHostingAccounts({ server_id: serverId || undefined }),
    staleTime: 60_000,
  });
  const allRows = allData?.data?.data ?? [];
  const stats = {
    total: allRows.length,
    imported: allRows.filter((r) => r.imported).length,
    unimported: allRows.filter((r) => !r.imported).length,
    suspended: allRows.filter((r) => r.suspended).length,
  };

  const rows = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const filtered = debouncedSearch
    ? rows.filter((r) =>
        r.cpanel_username.toLowerCase().includes(debouncedSearch.toLowerCase())
        || (r.domain ?? '').toLowerCase().includes(debouncedSearch.toLowerCase())
        || (r.client?.name ?? '').toLowerCase().includes(debouncedSearch.toLowerCase()))
    : rows;

  // Every existing client, so an unimported account's WHM contact email can
  // be matched against one we already have — without a query per row.
  const { data: allClientsData } = useQuery({
    queryKey: ['clients-for-email-match'],
    queryFn: () => getClients({ per_page: 500 }),
    staleTime: 60_000,
  });
  const clientByEmail = useMemo(() => {
    const map = new Map<string, Client>();
    for (const c of allClientsData?.data?.data ?? []) {
      const email = normEmail(c.email);
      if (email) map.set(email, c);
    }
    return map;
  }, [allClientsData]);
  const suggestionFor = (r: DiscoveredAccount) =>
    !r.imported && r.email ? clientByEmail.get(normEmail(r.email)) : undefined;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconServerBolt size={22} /> Discover cPanel Accounts</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Every account WHM actually has, matched against what's tracked here — so accounts created
        directly on the server, or missed during import, don't go unbilled.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 4 }}>
        <ClickableStat active={filter === 'all'} onClick={() => setFilter('all')}>
          <StatCard label="Total Accounts" value={statsLoading ? '—' : stats.total}
            icon={<IconServer2 size={20} />} color="blue" />
        </ClickableStat>
        <ClickableStat active={filter === 'imported'} onClick={() => setFilter('imported')}>
          <StatCard label="Imported" value={statsLoading ? '—' : stats.imported}
            icon={<IconCircleCheck size={20} />} color="teal" />
        </ClickableStat>
        <ClickableStat active={filter === 'unimported'} onClick={() => setFilter('unimported')}>
          <StatCard label="Not Imported" value={statsLoading ? '—' : stats.unimported}
            icon={<IconCircleDashed size={20} />} color="orange" />
        </ClickableStat>
        <ClickableStat active={filter === 'suspended'} onClick={() => setFilter('suspended')}>
          <StatCard label="Suspended" value={statsLoading ? '—' : stats.suspended}
            icon={<IconAlertOctagon size={20} />} color="red" />
        </ClickableStat>
      </SimpleGrid>

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
              { value: 'suspended', label: 'Suspended' },
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
          <Table.ScrollContainer minWidth={1700}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>IP Address</Table.Th>
                  <Table.Th>Username</Table.Th>
                  <Table.Th>Contact Email</Table.Th>
                  <Table.Th>Setup Date</Table.Th>
                  <Table.Th>Partition</Table.Th>
                  <Table.Th>Quota</Table.Th>
                  <Table.Th>Disk Used</Table.Th>
                  <Table.Th>Package</Table.Th>
                  <Table.Th>Theme</Table.Th>
                  <Table.Th>Reseller/Owner</Table.Th>
                  <Table.Th>Suspended</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {filtered.map((r, i) => {
                  const suggested = suggestionFor(r);
                  return (
                  <Table.Tr key={`${r.server_id}-${r.cpanel_username}`}>
                    <Table.Td c="dimmed">{i + 1}</Table.Td>
                    <Table.Td fw={500}>{r.domain ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.ip ?? '—'}</Table.Td>
                    <Table.Td>{r.cpanel_username}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.email ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.setup_date ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.partition ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.disk_limit ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.disk_used ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.plan ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.theme ?? '—'}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.owner ?? '—'}</Table.Td>
                    <Table.Td>
                      {r.suspended ? (
                        <Badge size="sm" variant="light" color="orange">
                          {r.suspend_reason || 'Suspended'}
                        </Badge>
                      ) : (
                        <Text size="sm" c="dimmed">—</Text>
                      )}
                    </Table.Td>
                    <Table.Td>
                      {r.client ? (
                        <Group gap={4} wrap="nowrap">
                          <Text size="sm">{r.client.name}</Text>
                          <ActionIcon variant="subtle" size="xs" onClick={() => navigate(`/clients/${r.client!.id}`)}>
                            <IconExternalLink size={12} />
                          </ActionIcon>
                        </Group>
                      ) : suggested ? (
                        <Tooltip label={`Matched by contact email (${r.email}) — click to review and link`}>
                          <Badge
                            size="sm" variant="light" color="violet" style={{ cursor: 'pointer' }}
                            leftSection={<IconBulb size={12} />}
                            onClick={() => setImporting(r)}
                          >
                            Suggested: {suggested.name}
                          </Badge>
                        </Tooltip>
                      ) : (
                        <Badge size="sm" variant="light" color="gray">Not imported</Badge>
                      )}
                    </Table.Td>
                    <Table.Td>
                      {!r.imported && (
                        <Tooltip label={suggested ? `Link to suggested client: ${suggested.name}` : 'Import and link to a client'}>
                          <ActionIcon variant="light" color={suggested ? 'violet' : 'blue'} size="sm" onClick={() => setImporting(r)}>
                            <IconPlus size={14} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                    </Table.Td>
                  </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      <ImportModal
        account={importing}
        suggestedClient={importing ? suggestionFor(importing) : undefined}
        onClose={() => setImporting(null)}
        onImported={() => qc.invalidateQueries({ queryKey: ['discover-hosting'] })}
      />
    </Stack>
  );
}

function ClickableStat({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <div
      role="button" tabIndex={0} onClick={onClick} onKeyDown={(e) => e.key === 'Enter' && onClick()}
      style={{
        cursor: 'pointer', borderRadius: 'var(--mantine-radius-md)',
        outline: active ? '2px solid var(--mantine-color-blue-5)' : '2px solid transparent',
        outlineOffset: 2, transition: 'outline-color 100ms ease',
      }}
    >
      {children}
    </div>
  );
}

function ImportModal({ account, suggestedClient, onClose, onImported }: {
  account: DiscoveredAccount | null; suggestedClient?: Client; onClose: () => void; onImported: () => void;
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
  // The suggested match may not be in the first 30 search results, so make
  // sure it's always a selectable option once one is offered.
  const clientOptions = suggestedClient && !clients.some((c: Client) => c.id === suggestedClient.id)
    ? [suggestedClient, ...clients]
    : clients;

  const { data: productsData } = useQuery({
    queryKey: ['products-for-import', debouncedProductSearch],
    queryFn: () => getProductServices({ search: debouncedProductSearch || undefined, active_only: true, per_page: 30 }),
    enabled: !!account,
  });
  const products = productsData?.data?.data ?? [];

  // Every product already linked to a WHM package (Product/Service's own
  // "cPanel Package" field), so this account's WHM plan can be matched the
  // same deterministic way `auto_provision` picks a package when creating a
  // NEW account — just run in reverse for an EXISTING one. Unlike the client
  // match, this can be genuinely ambiguous (several products share one
  // package name at different legacy prices), so it only pre-selects when
  // there's exactly one candidate — otherwise it just surfaces them first.
  const { data: allProductsData } = useQuery({
    queryKey: ['products-for-plan-match'],
    queryFn: () => getProductServices({ per_page: 500, active_only: true }),
    enabled: !!account,
    staleTime: 60_000,
  });
  const planMatches = useMemo(() => {
    const planKey = account?.plan?.trim().toLowerCase();
    if (!planKey) return [];
    return (allProductsData?.data?.data ?? []).filter(
      (p: any) => (p.cpanel_package ?? '').trim().toLowerCase() === planKey
    );
  }, [allProductsData, account]);
  const productOptions = [
    ...(planMatches.length > 0 ? [{
      group: `Matches WHM plan (${account?.plan})`,
      items: planMatches.map((p: any) => ({ value: p.id, label: `${p.name} — ${p.price}` })),
    }] : []),
    {
      group: planMatches.length > 0 ? 'All products' : 'Products',
      items: products
        .filter((p: any) => !planMatches.some((m: any) => m.id === p.id))
        .map((p: any) => ({ value: p.id, label: `${p.name}${p.price ? ` — ${p.price}` : ''}` })),
    },
  ];

  const form = useForm({
    initialValues: { client_id: '', product_service_id: '' },
    validate: {
      client_id: (v) => (v ? null : 'Required'),
      product_service_id: (v) => (v ? null : 'Required'),
    },
  });

  // Pre-select the suggested client each time the modal opens for a new
  // account — staff can still search and pick someone else instead.
  useEffect(() => {
    if (account) form.setFieldValue('client_id', suggestedClient?.id ?? '');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, suggestedClient]);

  // Same idea for the product/plan — but only when the WHM package name
  // resolves to exactly one product, since several can share a package at
  // different legacy prices and guessing wrong there is a billing mistake.
  useEffect(() => {
    if (account) {
      form.setFieldValue('product_service_id', planMatches.length === 1 ? planMatches[0].id : '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, planMatches.length === 1 ? planMatches[0]?.id : null]);

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
            {suggestedClient && (
              <Alert color="violet" variant="light" icon={<IconBulb size={16} />}>
                Matched by contact email ({account.email}) to an existing client:{' '}
                <strong>{suggestedClient.name}</strong>. Pre-selected below — change it if that's wrong.
              </Alert>
            )}
            <Select
              label="Client" placeholder="Search by name or email…" required searchable
              data={clientOptions.map((c: any) => ({ value: c.id, label: `${c.name}${c.email ? ` (${c.email})` : ''}` }))}
              searchValue={clientSearch} onSearchChange={setClientSearch}
              value={form.values.client_id} onChange={(v) => form.setFieldValue('client_id', v ?? '')}
              error={form.errors.client_id}
              filter={({ options }) => options}
            />
            {planMatches.length === 1 && (
              <Alert color="violet" variant="light" icon={<IconBulb size={16} />}>
                Matched by WHM package ({account.plan}) to: <strong>{planMatches[0].name} — {planMatches[0].price}</strong>.
                Pre-selected below — change it if that's wrong.
              </Alert>
            )}
            {planMatches.length > 1 && (
              <Alert color="yellow" variant="light" icon={<IconBulb size={16} />}>
                {planMatches.length} products match this WHM package ({account.plan}) at different prices —
                shown at the top of the list. Pick the one at the right price.
              </Alert>
            )}
            <Select
              label="Product / Plan" placeholder="Search products…" required searchable
              data={productOptions}
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

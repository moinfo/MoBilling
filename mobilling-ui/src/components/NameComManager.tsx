import { useState } from 'react';
import {
  Modal, Tabs, Stack, Group, Text, TextInput, PasswordInput, Checkbox, Button, Alert, Badge, Table, Select, Loader, Center, ScrollArea, Code, Paper,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { useDebouncedValue, useMediaQuery } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { IconPlugConnected, IconDownload, IconTags } from '@tabler/icons-react';
import NameComPricingPanel from './NameComPricingPanel';
import {
  getNameComAccount, saveNameComAccount, deleteNameComAccount, testNameComAccount, listNameComDomains, linkNameComDomain, NameComDomainRow,
} from '../api/namecom';
import { getClients } from '../api/clients';
import { usePermissions } from '../hooks/usePermissions';

const errMsg = (e: any): string =>
  e?.response?.data?.message
  || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null)
  || e?.message || 'Something went wrong';

/** Shared by the Domains-page modal and Settings > Domains (one implementation). */
export function NameComTabs() {
  const { can } = usePermissions();
  const [tab, setTab] = useState<string | null>(can('domains.settings') ? 'connection' : 'import');
  return (
    <Tabs value={tab} onChange={setTab} keepMounted={false}>
      <Tabs.List>
        {can('domains.settings') && <Tabs.Tab value="connection" leftSection={<IconPlugConnected size={14} />}>Connection</Tabs.Tab>}
        {can('domains.settings') && <Tabs.Tab value="pricing" leftSection={<IconTags size={14} />}>TLDs &amp; pricing</Tabs.Tab>}
        {can('domains.create') && <Tabs.Tab value="import" leftSection={<IconDownload size={14} />}>Import from Name.com</Tabs.Tab>}
      </Tabs.List>
      {can('domains.settings') && <Tabs.Panel value="connection" pt="md"><ConnectionTab /></Tabs.Panel>}
      {can('domains.settings') && <Tabs.Panel value="pricing" pt="md"><NameComPricingPanel /></Tabs.Panel>}
      {can('domains.create') && <Tabs.Panel value="import" pt="md"><ImportTab /></Tabs.Panel>}
    </Tabs>
  );
}

export default function NameComManager({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const mobile = useMediaQuery('(max-width: 48em)');
  return (
    <Modal opened={opened} onClose={onClose} title="Name.com" size="xl" fullScreen={!!mobile}>
      <NameComTabs />
    </Modal>
  );
}

function ConnectionTab() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['namecom-account'], queryFn: getNameComAccount });
  const account = data?.data?.data ?? null;
  const [username, setUsername] = useState<string | null>(null);
  const [token, setToken] = useState('');
  const [sandbox, setSandbox] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);

  const uname = username ?? account?.username ?? '';
  const isSandbox = sandbox ?? account?.is_sandbox ?? false;

  const save = useMutation({
    mutationFn: () => saveNameComAccount({ username: uname.trim(), token: token.trim() || undefined, is_sandbox: isSandbox }),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message });
      setToken(''); setUsername(null); setSandbox(null); setError(null);
      qc.invalidateQueries({ queryKey: ['namecom-account'] });
    },
    onError: (e) => setError(errMsg(e)),
  });
  const test = useMutation({
    mutationFn: testNameComAccount,
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['namecom-account'] }); },
    onError: (e) => { notifications.show({ color: 'red', message: errMsg(e) }); qc.invalidateQueries({ queryKey: ['namecom-account'] }); },
  });
  const remove = useMutation({
    mutationFn: deleteNameComAccount,
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['namecom-account'] }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  if (isLoading) return <Center py="md"><Loader size="sm" /></Center>;

  return (
    <Stack>
      <Text size="sm" c="dimmed">
        Connect your Name.com API account so MoBilling can read your domains, read TLD prices, check availability,
        change nameservers and - only when you confirm it (or if you turn on auto-register) - register domains that customers paid for.
        Renewals, transfers and deletions are never done through the API.
      </Text>
      <Alert color="blue" variant="light" title="Before you connect">
        Create an API token at Name.com (Account &gt; Settings &gt; API Token Management). Two-step verification (2FA)
        must be turned OFF on the account that owns the token, otherwise Name.com refuses API access.
      </Alert>
      {account && (
        <Paper withBorder p="sm" radius="md">
          <Group justify="space-between" wrap="wrap">
            <div>
              <Group gap="xs">
                <Text fw={600}>{account.username}</Text>
                <Badge color={account.status === 'active' ? 'green' : 'red'} variant="light">{account.status}</Badge>
                {account.is_sandbox && <Badge color="orange" variant="light">sandbox</Badge>}
              </Group>
              <Text size="xs" c="dimmed">Token <Code>{account.token_hint}</Code>
                {account.last_verified_at ? ` - verified ${new Date(account.last_verified_at).toLocaleString()}` : ''}</Text>
              {account.status_message && <Text size="xs" c="red">{account.status_message}</Text>}
            </div>
            <Group gap="xs">
              <Button size="xs" variant="light" loading={test.isPending} onClick={() => test.mutate()}>Test connection</Button>
              <Button size="xs" variant="subtle" color="red" loading={remove.isPending}
                onClick={() => { if (window.confirm('Remove the stored Name.com credentials? Linked domains stay in MoBilling but nameservers cannot be managed until you reconnect.')) remove.mutate(); }}>
                Remove
              </Button>
            </Group>
          </Group>
        </Paper>
      )}
      {error && <Alert color="red">{error}</Alert>}
      <TextInput label="Name.com username" value={uname} onChange={(e) => setUsername(e.currentTarget.value)} placeholder="Your Name.com username" />
      <PasswordInput label={account ? 'New API token (leave empty to keep the current one)' : 'API token'} value={token}
        onChange={(e) => setToken(e.currentTarget.value)} autoComplete="off" description="Write-only: the token is stored encrypted and is never shown again." />
      <Checkbox label="Use the Name.com sandbox (testing only)" checked={isSandbox} onChange={(e) => setSandbox(e.currentTarget.checked)} />
      <Group justify="flex-end">
        <Button loading={save.isPending} disabled={!uname.trim() || (!account && !token.trim())} onClick={() => { setError(null); save.mutate(); }}>
          {account ? 'Save / rotate token' : 'Connect'}
        </Button>
      </Group>
    </Stack>
  );
}

// Server-side client search (never loads every client).
function useClientOptions(search: string) {
  const [debounced] = useDebouncedValue(search, 300);
  const { data } = useQuery({
    queryKey: ['namecom-client-options', debounced],
    queryFn: () => getClients({ per_page: 50, status: 'all', search: debounced || undefined } as any),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
  const rows: any[] = data?.data?.data ?? [];
  return rows.map((c) => ({ value: String(c.id), label: c.email ? `${c.name} (${c.email})` : c.name }));
}

function ImportTab() {
  const [enabled, setEnabled] = useState(false);
  const { data, isFetching, error, refetch } = useQuery({
    queryKey: ['namecom-domains'],
    queryFn: listNameComDomains,
    enabled,
    staleTime: 0,
    gcTime: 0,
    retry: false,
  });
  const rows = data?.data?.data ?? [];
  const [linking, setLinking] = useState<NameComDomainRow | null>(null);

  return (
    <Stack>
      <Text size="sm" c="dimmed">Reads the domains in your Name.com account (read-only) and lets you link each one to a client.</Text>
      <Group>
        <Button leftSection={<IconDownload size={16} />} loading={isFetching} onClick={() => (enabled ? refetch() : setEnabled(true))}>
          {enabled ? 'Reload list' : 'Load domains from Name.com'}
        </Button>
      </Group>
      {error && <Alert color="red">{errMsg(error)}</Alert>}
      {enabled && !isFetching && !error && rows.length === 0 && <Text size="sm" c="dimmed">No domains found in this Name.com account.</Text>}
      {rows.length > 0 && (
        <ScrollArea>
          <Table striped withTableBorder miw={640}>
            <Table.Thead>
              <Table.Tr><Table.Th>Domain</Table.Th><Table.Th>Expires</Table.Th><Table.Th>Client</Table.Th><Table.Th>Status</Table.Th><Table.Th /></Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((r) => (
                <Table.Tr key={r.name}>
                  <Table.Td>{r.name}</Table.Td>
                  <Table.Td>{r.expires_at ?? '-'}</Table.Td>
                  <Table.Td>{r.client_name ?? '-'}</Table.Td>
                  <Table.Td>
                    {r.linked ? <Badge color="green" variant="light">Linked</Badge>
                      : r.fred_managed ? <Badge color="gray" variant="light">.tz registry</Badge>
                      : r.in_mobilling ? <Badge color="yellow" variant="light">In MoBilling - not linked</Badge>
                      : <Badge color="gray" variant="light">New</Badge>}
                  </Table.Td>
                  <Table.Td>
                    {!r.fred_managed && (
                      <Button size="compact-xs" variant="light" onClick={() => setLinking(r)}>
                        {r.linked ? 'Change client' : r.in_mobilling ? 'Link / upgrade' : 'Link to client'}
                      </Button>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </ScrollArea>
      )}
      {linking && <LinkModal row={linking} onClose={() => setLinking(null)} onDone={() => { setLinking(null); refetch(); }} />}
    </Stack>
  );
}

function LinkModal({ row, onClose, onDone }: { row: NameComDomainRow; onClose: () => void; onDone: () => void }) {
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const found = useClientOptions(search);
  const [clientId, setClientId] = useState<string | null>(row.client_id);
  const [pickedLabel, setPickedLabel] = useState<string | null>(row.client_name);
  const options = clientId && !found.some((o) => o.value === clientId) && pickedLabel ? [{ value: clientId, label: pickedLabel }, ...found] : found;
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => linkNameComDomain(row.name, clientId!),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message });
      qc.invalidateQueries({ queryKey: ['domains'] });
      qc.invalidateQueries({ queryKey: ['domain-stats'] });
      onDone();
    },
    onError: (e) => setError(errMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={`Link ${row.name}`} zIndex={400}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Text size="sm" c="dimmed">
          The domain is recorded under this client with its expiry date from Name.com, and its nameservers can then be
          changed from MoBilling (staff and the client portal).
        </Text>
        <Select label="Client" data={options} value={clientId}
          onChange={(v) => { setClientId(v); setPickedLabel(options.find((o) => o.value === v)?.label ?? null); }}
          searchValue={search} onSearchChange={setSearch} filter={({ options }) => options}
          nothingFoundMessage="No client found" searchable clearable placeholder="Search name, email or phone" />
        <Button disabled={!clientId} loading={m.isPending} onClick={() => { setError(null); m.mutate(); }}>Link domain</Button>
      </Stack>
    </Modal>
  );
}

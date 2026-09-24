import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert, Button, Modal,
  TextInput, PasswordInput, Tabs, ActionIcon, Drawer, NumberInput, CopyButton, Code, List, Tooltip,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPlus, IconRefresh, IconTrash, IconEdit, IconKey, IconCopy, IconCheck, IconServer, IconWorldWww, IconPlugConnected,
  IconLink,
} from '@tabler/icons-react';
import {
  getLinodeAccounts, createLinodeAccount, updateLinodeAccount, deleteLinodeAccount, verifyLinodeAccount,
  syncLinodeAccount, getLinodeServers, getLinodeDomains, addLinodeDomain, setLinodeNameservers,
  checkLinodeNameservers, getLinodeRecords, addLinodeRecord, updateLinodeRecord, deleteLinodeRecord,
  mapLinodeResource, LinodeAccount, LinodeResource, LinodeRecord, AddDomainResult, DOMAIN_TTLS, RECORD_TTLS,
  RECORD_TYPES, LINODE_NAMESERVERS,
} from '../api/linode';
import { getClients } from '../api/clients';
import { usePermissions } from '../hooks/usePermissions';

const errMsg = (e: any): string =>
  e?.response?.data?.message
  || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null)
  || e?.message || 'Something went wrong';

const fmt = (d: string | null | undefined) => (d ? new Date(d).toLocaleString() : 'never');
const ttlLabel = (s: number) => (s === 0 ? 'Default' : s >= 86400 ? `${s / 86400} day(s)` : s >= 3600 ? `${s / 3600} hour(s)` : `${s} sec`);
const ttlOptions = (list: number[]) => list.map((t) => ({ value: String(t), label: ttlLabel(t) }));

export default function Linode() {
  const { can } = usePermissions();
  const canManage = can('linode.manage');
  return (
    <Stack>
      <Group justify="space-between">
        <div>
          <Title order={2}>Linode</Title>
          <Text c="dimmed" size="sm">Connect your Linode account, see your servers and add domains to Linode DNS.</Text>
        </div>
      </Group>
      <Tabs defaultValue="accounts" keepMounted={false}>
        <Tabs.List>
          <Tabs.Tab value="accounts" leftSection={<IconPlugConnected size={14} />}>Accounts</Tabs.Tab>
          <Tabs.Tab value="servers" leftSection={<IconServer size={14} />}>Servers</Tabs.Tab>
          <Tabs.Tab value="domains" leftSection={<IconWorldWww size={14} />}>Domains</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="accounts" pt="md"><AccountsTab canManage={canManage} /></Tabs.Panel>
        <Tabs.Panel value="servers" pt="md"><ServersTab canManage={canManage} /></Tabs.Panel>
        <Tabs.Panel value="domains" pt="md"><DomainsTab canManage={canManage} /></Tabs.Panel>
      </Tabs>
    </Stack>
  );
}

// ───────────── Accounts ─────────────

function AccountsTab({ canManage }: { canManage: boolean }) {
  const qc = useQueryClient();
  const [modal, setModal] = useState<{ account: LinodeAccount | null } | null>(null);
  const { data, isLoading, isError, error } = useQuery({ queryKey: ['linode-accounts'], queryFn: getLinodeAccounts });
  const accounts = data?.data?.data ?? [];
  const refresh = () => { qc.invalidateQueries({ queryKey: ['linode-accounts'] }); qc.invalidateQueries({ queryKey: ['linode-servers'] }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); };
  const onErr = (e: any) => notifications.show({ color: 'red', title: 'Linode', message: errMsg(e) });

  const sync = useMutation({ mutationFn: (id: string) => syncLinodeAccount(id), onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); }, onError: onErr });
  const verify = useMutation({ mutationFn: (id: string) => verifyLinodeAccount(id), onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); }, onError: onErr });
  const del = useMutation({ mutationFn: (id: string) => deleteLinodeAccount(id), onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); }, onError: onErr });

  return (
    <Stack>
      <Alert color="blue" title="How to connect">
        <Text size="sm">In Linode Cloud Manager go to <b>Profile &rarr; API Tokens &rarr; Create a Personal Access Token</b>. Give it these scopes and paste it here:</Text>
        <List size="sm" mt={4}>
          <List.Item><Code>Linodes</Code>: Read Only (<Code>linodes:read_only</Code>)</List.Item>
          <List.Item><Code>Domains</Code>: Read/Write (<Code>domains:read_write</Code>)</List.Item>
        </List>
        <Text size="sm" mt={4}>Everything else can stay &quot;None&quot;. Linode tokens cannot be limited to single domains, so the token reaches your whole Linode account; MoBilling keeps it encrypted and never shows it again.</Text>
      </Alert>
      {canManage && <Group><Button leftSection={<IconPlus size={16} />} onClick={() => setModal({ account: null })}>Connect Linode account</Button></Group>}
      {isLoading ? <Center><Loader /></Center> : isError ? <Alert color="red">{errMsg(error)}</Alert> : accounts.length === 0 ? (
        <Paper withBorder p="xl"><Text ta="center" c="dimmed">No Linode account connected yet.</Text></Paper>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={700}>
            <Table verticalSpacing="sm">
              <Table.Thead><Table.Tr><Table.Th>Label</Table.Th><Table.Th>Token</Table.Th><Table.Th>Status</Table.Th><Table.Th>Default SOA email</Table.Th><Table.Th>Last synced</Table.Th><Table.Th /></Table.Tr></Table.Thead>
              <Table.Tbody>
                {accounts.map((a) => (
                  <Table.Tr key={a.id}>
                    <Table.Td>{a.label}</Table.Td>
                    <Table.Td><Code>{a.token_hint ?? '—'}</Code></Table.Td>
                    <Table.Td>
                      <Badge color={a.status === 'active' ? (a.status_message ? 'yellow' : 'green') : 'red'}>{a.status}</Badge>
                      {a.status_message && <Text size="xs" c="dimmed" maw={280}>{a.status_message}</Text>}
                      <Text size="xs" c="dimmed">verified {fmt(a.last_verified_at)}</Text>
                    </Table.Td>
                    <Table.Td>{a.soa_email ?? '—'}</Table.Td>
                    <Table.Td>{fmt(a.last_synced_at)}</Table.Td>
                    <Table.Td>
                      {canManage && (
                        <Group gap={4} wrap="nowrap">
                          <Button size="xs" leftSection={<IconRefresh size={14} />} loading={sync.isPending && sync.variables === a.id} onClick={() => sync.mutate(a.id)}>Sync now</Button>
                          <Tooltip label="Re-check token"><ActionIcon variant="light" loading={verify.isPending && verify.variables === a.id} onClick={() => verify.mutate(a.id)}><IconCheck size={16} /></ActionIcon></Tooltip>
                          <Tooltip label="Edit / rotate token"><ActionIcon variant="light" onClick={() => setModal({ account: a })}><IconKey size={16} /></ActionIcon></Tooltip>
                          <Tooltip label="Remove (nothing is deleted at Linode)"><ActionIcon variant="light" color="red" onClick={() => { if (window.confirm(`Remove "${a.label}" from MoBilling? Nothing is deleted at Linode.`)) del.mutate(a.id); }}><IconTrash size={16} /></ActionIcon></Tooltip>
                        </Group>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
      {modal && <AccountModal account={modal.account} onClose={() => setModal(null)} onSaved={refresh} />}
    </Stack>
  );
}

function AccountModal({ account, onClose, onSaved }: { account: LinodeAccount | null; onClose: () => void; onSaved: () => void }) {
  const [label, setLabel] = useState(account?.label ?? '');
  const [token, setToken] = useState('');
  const [soa, setSoa] = useState(account?.soa_email ?? '');
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => account
      ? updateLinodeAccount(account.id, { label, soa_email: soa || null, ...(token ? { token } : {}) })
      : createLinodeAccount({ label, token, soa_email: soa || undefined }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); onSaved(); onClose(); },
    onError: (e) => setError(errMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={account ? 'Edit Linode account' : 'Connect Linode account'}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <TextInput label="Label" placeholder="My Linode" value={label} onChange={(e) => setLabel(e.currentTarget.value)} required />
        <PasswordInput label={account ? 'New token (leave empty to keep current)' : 'Personal access token'} description="Needs linodes:read_only and domains:read_write. Never shown again after saving."
          value={token} onChange={(e) => setToken(e.currentTarget.value)} autoComplete="new-password" required={!account} />
        <TextInput label="Default SOA email" description="Contact email for the DNS zones you create" value={soa} onChange={(e) => setSoa(e.currentTarget.value)} />
        <Button loading={m.isPending} disabled={!label || (!account && token.length < 20)} onClick={() => { setError(null); m.mutate(); }}>
          {account ? 'Save' : 'Verify & connect'}
        </Button>
      </Stack>
    </Modal>
  );
}

// ───────────── Servers ─────────────

function useClientOptions() {
  const { data } = useQuery({ queryKey: ['linode-client-options'], queryFn: () => getClients({ per_page: 200, status: 'all' } as any), staleTime: 60_000 });
  const rows: any[] = data?.data?.data ?? [];
  return rows.map((c) => ({ value: String(c.id), label: c.name }));
}

function MapModal({ resource, onClose }: { resource: LinodeResource; onClose: () => void }) {
  const qc = useQueryClient();
  const options = useClientOptions();
  const [clientId, setClientId] = useState<string | null>(resource.client_id);
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => mapLinodeResource(resource.id, { client_id: clientId }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['linode-servers'] }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); onClose(); },
    onError: (e) => setError(errMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={`Map "${resource.label}" to a client`}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Select label="Client" data={options} value={clientId} onChange={setClientId} searchable clearable placeholder="No client" />
        <Button loading={m.isPending} onClick={() => { setError(null); m.mutate(); }}>Save</Button>
      </Stack>
    </Modal>
  );
}

function ServersTab({ canManage }: { canManage: boolean }) {
  const [mapFor, setMapFor] = useState<LinodeResource | null>(null);
  const { data, isLoading, isError, error } = useQuery({ queryKey: ['linode-servers'], queryFn: getLinodeServers });
  const rows = data?.data?.data ?? [];
  if (isLoading) return <Center><Loader /></Center>;
  if (isError) return <Alert color="red">{errMsg(error)}</Alert>;
  if (!rows.length) return <Paper withBorder p="xl"><Text ta="center" c="dimmed">No servers yet. Connect a Linode account and press &quot;Sync now&quot; on the Accounts tab.</Text></Paper>;
  return (
    <Paper withBorder>
      <Table.ScrollContainer minWidth={800}>
        <Table verticalSpacing="sm">
          <Table.Thead><Table.Tr><Table.Th>Label</Table.Th><Table.Th>Status</Table.Th><Table.Th>Region</Table.Th><Table.Th>Plan</Table.Th><Table.Th>IPv4</Table.Th><Table.Th>Client</Table.Th><Table.Th>Last synced</Table.Th><Table.Th /></Table.Tr></Table.Thead>
          <Table.Tbody>
            {rows.map((s) => (
              <Table.Tr key={s.id}>
                <Table.Td>{s.label}<Text size="xs" c="dimmed">{s.account_label}</Text></Table.Td>
                <Table.Td><Badge color={s.status === 'running' ? 'green' : s.status === 'gone' ? 'red' : 'gray'}>{s.status === 'gone' ? 'removed at Linode' : s.status}</Badge></Table.Td>
                <Table.Td>{s.region}</Table.Td>
                <Table.Td>{s.plan}</Table.Td>
                <Table.Td>{s.ipv4.join(', ')}</Table.Td>
                <Table.Td>{s.client_name ?? <Text c="dimmed" size="sm">unmapped</Text>}</Table.Td>
                <Table.Td>{fmt(s.synced_at)}</Table.Td>
                <Table.Td>{canManage && <Button size="xs" variant="light" leftSection={<IconLink size={14} />} onClick={() => setMapFor(s)}>Map to client</Button>}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {mapFor && <MapModal resource={mapFor} onClose={() => setMapFor(null)} />}
    </Paper>
  );
}

// ───────────── Domains ─────────────

function NameserverCard({ result, onDone }: { result: AddDomainResult; onDone: () => void }) {
  const qc = useQueryClient();
  const set = useMutation({
    mutationFn: () => setLinodeNameservers(result.id),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); },
    onError: (e) => notifications.show({ color: 'red', title: 'Nameservers', message: errMsg(e) }),
  });
  const list = result.nameservers.join('\n');
  return (
    <Stack>
      <Alert color="green" title={`${result.label} added to Linode`}>
        {result.records_created > 0 && <Text size="sm">{result.records_created} A record(s) created.</Text>}
      </Alert>
      <Paper withBorder p="md">
        <Text fw={600}>Weka nameservers hizi kwa msajili wako (Set these nameservers at your registrar)</Text>
        <Stack gap={2} my="xs">{result.nameservers.map((n) => <Code key={n}>{n}</Code>)}</Stack>
        <CopyButton value={list}>{({ copied, copy }) => (
          <Button size="xs" variant="light" leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />} onClick={copy}>{copied ? 'Copied' : 'Copy nameservers'}</Button>
        )}</CopyButton>
        <Text size="xs" c="dimmed" mt="xs">{result.note}</Text>
      </Paper>
      {result.can_set_nameservers && (
        <Button color="orange" loading={set.isPending} onClick={() => {
          if (window.confirm(`Change the registry nameservers of ${result.label} to ns1-ns5.linode.com now? Its website/email will switch to Linode DNS.`)) set.mutate();
        }}>Set nameservers now (registered with us)</Button>
      )}
      <Button variant="default" onClick={onDone}>Close</Button>
    </Stack>
  );
}

function AddDomainModal({ onClose }: { onClose: () => void }) {
  const qc = useQueryClient();
  const { data: accData } = useQuery({ queryKey: ['linode-accounts'], queryFn: getLinodeAccounts });
  const { data: srvData } = useQuery({ queryKey: ['linode-servers'], queryFn: getLinodeServers });
  const accounts = (accData?.data?.data ?? []).filter((a) => a.status === 'active');
  const [accountId, setAccountId] = useState<string | null>(accounts.length === 1 ? accounts[0].id : null);
  const [domain, setDomain] = useState('');
  const [soa, setSoa] = useState('');
  const [ttl, setTtl] = useState<string | null>('0');
  const [serverId, setServerId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<AddDomainResult | null>(null);

  const account = accounts.find((a) => a.id === accountId);
  const servers = (srvData?.data?.data ?? []).filter((s) => s.linode_account_id === accountId && s.status !== 'gone' && s.ipv4.length);
  const server = servers.find((s) => s.id === serverId);
  const name = domain.trim().toLowerCase();

  const m = useMutation({
    mutationFn: () => addLinodeDomain({ account_id: accountId!, domain: name, soa_email: soa || account?.soa_email || undefined, ttl: ttl ? Number(ttl) : undefined, server_id: serverId || undefined }),
    onSuccess: (r) => { setResult(r.data.data); if (r.data.message.includes('failed')) notifications.show({ color: 'yellow', message: r.data.message }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); },
    onError: (e) => setError(errMsg(e)),
  });

  return (
    <Modal opened onClose={onClose} title="Add domain to Linode" size="lg">
      {result ? <NameserverCard result={result} onDone={onClose} /> : (
        <Stack>
          {error && <Alert color="red">{error}</Alert>}
          <Select label="Linode account" data={accounts.map((a) => ({ value: a.id, label: a.label }))} value={accountId} onChange={(v) => { setAccountId(v); setServerId(null); }} placeholder="Choose account" />
          <TextInput label="Domain name" placeholder="example.co.tz" value={domain} onChange={(e) => setDomain(e.currentTarget.value)} required />
          <TextInput label="SOA email" description="Defaults to the account's SOA email" placeholder={account?.soa_email ?? ''} value={soa} onChange={(e) => setSoa(e.currentTarget.value)} />
          <Select label="TTL" data={ttlOptions(DOMAIN_TTLS)} value={ttl} onChange={setTtl} allowDeselect={false} />
          <Select label="Point to server (optional)" data={servers.map((s) => ({ value: s.id, label: `${s.label} (${s.ipv4[0]})` }))} value={serverId} onChange={setServerId} clearable disabled={!accountId}
            placeholder={servers.length ? 'Choose a server' : 'No synced servers for this account'} />
          <Paper withBorder p="sm">
            <Text size="sm" fw={600}>Will be created</Text>
            <Text size="sm">Domain zone <Code>{name || 'example.co.tz'}</Code> (master){server ? '' : ' - no records'}</Text>
            {server && (<>
              <Text size="sm">A <Code>{name || 'example.co.tz'}</Code> &rarr; <Code>{server.ipv4[0]}</Code></Text>
              <Text size="sm">A <Code>www.{name || 'example.co.tz'}</Code> &rarr; <Code>{server.ipv4[0]}</Code></Text>
            </>)}
          </Paper>
          <Button loading={m.isPending} disabled={!accountId || !name} onClick={() => { setError(null); m.mutate(); }}>Add domain</Button>
        </Stack>
      )}
    </Modal>
  );
}

function DomainsTab({ canManage }: { canManage: boolean }) {
  const qc = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [recordsFor, setRecordsFor] = useState<LinodeResource | null>(null);
  const [mapFor, setMapFor] = useState<LinodeResource | null>(null);
  const { data, isLoading, isError, error } = useQuery({ queryKey: ['linode-domains'], queryFn: getLinodeDomains });
  const rows = data?.data?.data ?? [];
  const check = useMutation({
    mutationFn: (id: string) => checkLinodeNameservers(id),
    onSuccess: (r) => notifications.show({ color: r.data.data.pointing_to_linode ? 'green' : 'yellow',
      message: r.data.data.pointing_to_linode ? 'Nameservers already point to Linode.' : `Nameservers are not Linode's yet (currently: ${r.data.data.nameservers.join(', ') || 'none found'}).` }),
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const setNs = useMutation({
    mutationFn: (id: string) => setLinodeNameservers(id),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  return (
    <Stack>
      {canManage && <Group><Button leftSection={<IconPlus size={16} />} onClick={() => setAdding(true)}>Add domain</Button></Group>}
      {isLoading ? <Center><Loader /></Center> : isError ? <Alert color="red">{errMsg(error)}</Alert> : !rows.length ? (
        <Paper withBorder p="xl"><Text ta="center" c="dimmed">No domains yet. Sync an account or add a domain.</Text></Paper>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={800}>
            <Table verticalSpacing="sm">
              <Table.Thead><Table.Tr><Table.Th>Domain</Table.Th><Table.Th>Status</Table.Th><Table.Th>Account</Table.Th><Table.Th>Registered with us</Table.Th><Table.Th>Client</Table.Th><Table.Th /></Table.Tr></Table.Thead>
              <Table.Tbody>
                {rows.map((d) => (
                  <Table.Tr key={d.id}>
                    <Table.Td>{d.label}</Table.Td>
                    <Table.Td><Badge color={d.status === 'active' ? 'green' : d.status === 'gone' ? 'red' : 'gray'}>{d.status === 'gone' ? 'removed at Linode' : d.status}</Badge></Table.Td>
                    <Table.Td>{d.account_label}</Table.Td>
                    <Table.Td>{d.our_domain ? <Badge variant="light">{d.our_domain.status}</Badge> : <Text size="sm" c="dimmed">no</Text>}</Table.Td>
                    <Table.Td>{d.client_name ?? <Text size="sm" c="dimmed">unmapped</Text>}</Table.Td>
                    <Table.Td>
                      <Group gap={4} wrap="nowrap">
                        <Button size="xs" variant="light" leftSection={<IconEdit size={14} />} onClick={() => setRecordsFor(d)} disabled={d.status === 'gone'}>Records</Button>
                        <Button size="xs" variant="subtle" loading={check.isPending && check.variables === d.id} onClick={() => check.mutate(d.id)}>Check NS</Button>
                        {canManage && d.our_domain?.can_set_nameservers && (
                          <Button size="xs" variant="light" color="orange" loading={setNs.isPending && setNs.variables === d.id}
                            onClick={() => { if (window.confirm(`Change the registry nameservers of ${d.label} to ns1-ns5.linode.com now?`)) setNs.mutate(d.id); }}>Set nameservers now</Button>
                        )}
                        {canManage && <ActionIcon variant="light" onClick={() => setMapFor(d)}><IconLink size={16} /></ActionIcon>}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
      <Text size="xs" c="dimmed">Domains must point to {LINODE_NAMESERVERS[0]} ... {LINODE_NAMESERVERS[4]} at the registrar before Linode DNS records take effect.</Text>
      {adding && <AddDomainModal onClose={() => setAdding(false)} />}
      {recordsFor && <RecordsDrawer resource={recordsFor} canManage={canManage} onClose={() => setRecordsFor(null)} />}
      {mapFor && <MapModal resource={mapFor} onClose={() => setMapFor(null)} />}
    </Stack>
  );
}

// ───────────── Records drawer ─────────────

function RecordsDrawer({ resource, canManage, onClose }: { resource: LinodeResource; canManage: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const key = ['linode-records', resource.id];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => getLinodeRecords(resource.id) });
  const rows = data?.data?.data ?? [];
  const [editing, setEditing] = useState<LinodeRecord | 'new' | null>(null);
  const del = useMutation({
    mutationFn: (id: number) => deleteLinodeRecord(resource.id, id),
    onSuccess: () => { notifications.show({ color: 'green', message: 'Record deleted.' }); qc.invalidateQueries({ queryKey: key }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  return (
    <Drawer opened onClose={onClose} title={`DNS records - ${resource.label}`} position="right" size="xl">
      <Stack>
        <Text size="xs" c="dimmed">NS and SOA records are managed by Linode and cannot be changed here.</Text>
        {canManage && <Group><Button size="xs" leftSection={<IconPlus size={14} />} onClick={() => setEditing('new')}>Add record</Button></Group>}
        {isLoading ? <Center><Loader /></Center> : isError ? <Alert color="red">{errMsg(error)}</Alert> : !rows.length ? <Text c="dimmed">No records.</Text> : (
          <Table.ScrollContainer minWidth={520}>
            <Table verticalSpacing="xs">
              <Table.Thead><Table.Tr><Table.Th>Type</Table.Th><Table.Th>Name</Table.Th><Table.Th>Target</Table.Th><Table.Th>TTL</Table.Th><Table.Th /></Table.Tr></Table.Thead>
              <Table.Tbody>
                {rows.map((r) => (
                  <Table.Tr key={r.id}>
                    <Table.Td><Badge variant="light">{r.type}</Badge></Table.Td>
                    <Table.Td>{r.name || '@'}</Table.Td>
                    <Table.Td style={{ wordBreak: 'break-all' }}>{r.target}{r.priority != null && r.type === 'MX' ? ` (prio ${r.priority})` : ''}</Table.Td>
                    <Table.Td>{ttlLabel(r.ttl_sec)}</Table.Td>
                    <Table.Td>
                      {canManage && !r.locked && (
                        <Group gap={4} wrap="nowrap">
                          <ActionIcon variant="light" onClick={() => setEditing(r)}><IconEdit size={14} /></ActionIcon>
                          <ActionIcon variant="light" color="red" onClick={() => { if (window.confirm(`Delete ${r.type} record ${r.name || '@'}?`)) del.mutate(r.id); }}><IconTrash size={14} /></ActionIcon>
                        </Group>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Stack>
      {editing && <RecordModal resource={resource} record={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: key })} />}
    </Drawer>
  );
}

function RecordModal({ resource, record, onClose, onSaved }: { resource: LinodeResource; record: LinodeRecord | null; onClose: () => void; onSaved: () => void }) {
  const [type, setType] = useState<string>(record?.type ?? 'A');
  const [name, setName] = useState(record?.name ?? '');
  const [target, setTarget] = useState(record?.target ?? '');
  const [ttl, setTtl] = useState<string>(String(record?.ttl_sec ?? 0));
  const [priority, setPriority] = useState<number | string>(record?.priority ?? 10);
  const [weight, setWeight] = useState<number | string>(record?.weight ?? 0);
  const [port, setPort] = useState<number | string>(record?.port ?? 0);
  const [tag, setTag] = useState<string>(record?.tag ?? 'issue');
  const [error, setError] = useState<string | null>(null);

  const m = useMutation({
    mutationFn: () => {
      const p = { type, name: name.trim(), target: target.trim(), ttl_sec: Number(ttl),
        ...(type === 'MX' || type === 'SRV' ? { priority: Number(priority) } : {}),
        ...(type === 'SRV' ? { weight: Number(weight), port: Number(port) } : {}),
        ...(type === 'CAA' ? { tag } : {}) };
      return record ? updateLinodeRecord(resource.id, record.id, p) : addLinodeRecord(resource.id, p);
    },
    onSuccess: () => { notifications.show({ color: 'green', message: record ? 'Record updated.' : 'Record added.' }); onSaved(); onClose(); },
    onError: (e) => setError(errMsg(e)),
  });

  return (
    <Modal opened onClose={onClose} title={record ? 'Edit record' : 'Add record'}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Select label="Type" data={RECORD_TYPES} value={type} onChange={(v) => setType(v ?? 'A')} allowDeselect={false} disabled={!!record} />
        <TextInput label="Name" description="Leave empty for the root domain. CNAME cannot be on the root." placeholder="www" value={name} onChange={(e) => setName(e.currentTarget.value)} />
        <TextInput label="Target" placeholder={type === 'A' ? '1.2.3.4' : type === 'CNAME' || type === 'MX' ? 'host.example.com' : ''} value={target} onChange={(e) => setTarget(e.currentTarget.value)} required />
        {(type === 'MX' || type === 'SRV') && <NumberInput label="Priority (0-255)" min={0} max={255} value={priority} onChange={setPriority} />}
        {type === 'SRV' && (<Group grow><NumberInput label="Weight" min={0} max={65535} value={weight} onChange={setWeight} /><NumberInput label="Port" min={0} max={65535} value={port} onChange={setPort} /></Group>)}
        {type === 'CAA' && <Select label="Tag" data={['issue', 'issuewild', 'iodef']} value={tag} onChange={(v) => setTag(v ?? 'issue')} allowDeselect={false} />}
        <Select label="TTL" data={ttlOptions(RECORD_TTLS)} value={ttl} onChange={(v) => setTtl(v ?? '0')} allowDeselect={false} />
        <Button loading={m.isPending} disabled={!target} onClick={() => { setError(null); m.mutate(); }}>Save</Button>
      </Stack>
    </Modal>
  );
}

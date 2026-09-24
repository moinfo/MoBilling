import { useState, useMemo } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert, Button, Modal,
  TextInput, PasswordInput, Radio, Checkbox, Tabs, ActionIcon, Drawer, NumberInput, CopyButton, Code, List, Tooltip, ScrollArea,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import {
  IconPlus, IconRefresh, IconTrash, IconEdit, IconKey, IconCopy, IconCheck, IconServer, IconWorldWww, IconPlugConnected,
  IconLink, IconWand, IconReceipt, IconPower,
} from '@tabler/icons-react';
import {
  getLinodeAccounts, createLinodeAccount, updateLinodeAccount, deleteLinodeAccount, verifyLinodeAccount,
  syncLinodeAccount, getLinodeServers, getLinodeDomains, addLinodeDomain, setLinodeNameservers,
  checkLinodeNameservers, getLinodeRecords, addLinodeRecord, updateLinodeRecord, deleteLinodeRecord,
  mapLinodeResource, refreshLinodeDns, getLinodeBillingProducts, getLinodeClientSubscriptions, billLinodeServer, linkLinodeSubscription, unlinkLinodeSubscription, autoMapLinodeClients, DnsStatus, LinodeAccount, LinodeResource, LinodeRecord, AddDomainResult, DOMAIN_TTLS, RECORD_TTLS,
  RECORD_TYPES, LINODE_NAMESERVERS, DnsRefreshBatch, PowerAction,
} from '../api/linode';
import { getClients } from '../api/clients';
import LinodePowerModal, { BUSY_STATUSES } from '../components/LinodePowerModal';
import { Menu } from '@mantine/core';
import { usePermissions } from '../hooks/usePermissions';
import { useNavigate } from 'react-router-dom';

const errMsg = (e: any): string =>
  e?.response?.data?.message
  || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null)
  || e?.message || 'Something went wrong';

const fmt = (d: string | null | undefined) => (d ? new Date(d).toLocaleString() : 'never');
const ttlLabel = (s: number) => (s === 0 ? 'Default' : s >= 86400 ? `${s / 86400} day(s)` : s >= 3600 ? `${s / 3600} hour(s)` : `${s} sec`);
const ttlOptions = (list: number[]) => list.map((t) => ({ value: String(t), label: ttlLabel(t) }));

export default function Linode() {
  const { can } = usePermissions();
  const [tab, setTab] = useState<string | null>('accounts');
  const [serverFilter, setServerFilter] = useState<string | null>(null);
  const showServerDomains = (id: string) => { setServerFilter(id); setTab('domains'); };
  const canManage = can('linode.manage');
  return (
    <Stack>
      <Group justify="space-between">
        <div>
          <Title order={2}>Linode</Title>
          <Text c="dimmed" size="sm">Connect your Linode account, see your servers and add domains to Linode DNS.</Text>
        </div>
      </Group>
      <Tabs value={tab} onChange={setTab} keepMounted={false}>
        <Tabs.List>
          <Tabs.Tab value="accounts" leftSection={<IconPlugConnected size={14} />}>Accounts</Tabs.Tab>
          <Tabs.Tab value="servers" leftSection={<IconServer size={14} />}>Servers</Tabs.Tab>
          <Tabs.Tab value="domains" leftSection={<IconWorldWww size={14} />}>Domains</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="accounts" pt="md"><AccountsTab canManage={canManage} /></Tabs.Panel>
        <Tabs.Panel value="servers" pt="md"><ServersTab canManage={canManage} onShowDomains={showServerDomains} /></Tabs.Panel>
        <Tabs.Panel value="domains" pt="md"><DomainsTab canManage={canManage} serverFilter={serverFilter} setServerFilter={setServerFilter} /></Tabs.Panel>
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

// Server-side search (name/email/phone) — the old version loaded only the first 200 clients and
// filtered them locally, so any client beyond that (or matched by email) could never be found.
function useClientOptions(search: string) {
  const [debounced] = useDebouncedValue(search, 300);
  const { data } = useQuery({
    queryKey: ['linode-client-options', debounced],
    queryFn: () => getClients({ per_page: 50, status: 'all', search: debounced || undefined } as any),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
  const rows: any[] = data?.data?.data ?? [];
  return rows.map((c) => ({ value: String(c.id), label: c.email ? `${c.name} (${c.email})` : c.name }));
}

function MapModal({ resource, onClose }: { resource: LinodeResource; onClose: () => void }) {
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const found = useClientOptions(search);
  const [clientId, setClientId] = useState<string | null>(resource.client_id);
  const [pickedLabel, setPickedLabel] = useState<string | null>(resource.client_name ?? null);
  // keep the chosen client in the list even after the search text changes
  const options = clientId && !found.some((o) => o.value === clientId) && pickedLabel ? [{ value: clientId, label: pickedLabel }, ...found] : found;
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
        <Select label="Client" data={options} value={clientId} onChange={(v) => { setClientId(v); setPickedLabel(options.find((o) => o.value === v)?.label ?? null); }} searchValue={search} onSearchChange={setSearch} filter={({ options }) => options} nothingFoundMessage="No client found" searchable clearable placeholder="Search name, email or phone" />
        <Button loading={m.isPending} onClick={() => { setError(null); m.mutate(); }}>Save</Button>
      </Stack>
    </Modal>
  );
}


const addMonths = (iso: string, m: number) => {
  const [y, mo, d] = iso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, mo - 1 + m, d));
  return dt.toISOString().slice(0, 10);
};
const CYCLE_MONTHS: Record<string, number> = { monthly: 1, quarterly: 3, half_yearly: 6, yearly: 12 };
const CYCLE_LABEL: Record<string, string> = { monthly: 'Monthly', quarterly: 'Quarterly', half_yearly: 'Half-yearly', yearly: 'Yearly' };
const money = (n: number | string) => Number(n).toLocaleString(undefined, { maximumFractionDigits: 2 });

const BILL_STATE: Record<string, { color: string; label: string }> = {
  active: { color: 'green', label: 'Active' }, pending: { color: 'yellow', label: 'Pending payment' },
  suspended: { color: 'orange', label: 'Suspended' }, expired: { color: 'red', label: 'Expired' },
};

function BillModal({ resource, onClose }: { resource: LinodeResource; onClose: () => void }) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const found = useClientOptions(search);
  const [clientId, setClientId] = useState<string | null>(resource.client_id);
  const [pickedLabel, setPickedLabel] = useState<string | null>(resource.client_name ?? null);
  const options = clientId && !found.some((o) => o.value === clientId) && pickedLabel ? [{ value: clientId, label: pickedLabel }, ...found] : found;
  const [tab, setTab] = useState<string | null>('new');
  const [productId, setProductId] = useState<string | null>(null);
  const [amount, setAmount] = useState<number | string>('');
  const [start, setStart] = useState('');
  const [expire, setExpire] = useState('');
  const [expireTouched, setExpireTouched] = useState(false);
  const [mode, setMode] = useState<'paid_outside' | 'invoice_now'>('paid_outside');
  const [label, setLabel] = useState(`${resource.label}${resource.ipv4?.[0] ? ' ' + resource.ipv4[0] : ''}`);
  const [existingId, setExistingId] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { data: prodData } = useQuery({ queryKey: ['linode-billing-products'], queryFn: getLinodeBillingProducts });
  const products = prodData?.data?.data ?? [];
  const product = products.find((p) => p.id === productId) ?? null;
  const cycle = product?.billing_cycle ?? null;
  const { data: subData } = useQuery({
    queryKey: ['linode-client-subs', clientId], queryFn: () => getLinodeClientSubscriptions(clientId!), enabled: !!clientId && tab === 'existing',
  });
  const existing = subData?.data?.data ?? [];

  const pickProduct = (v: string | null) => {
    setProductId(v);
    const p = products.find((x) => x.id === v);
    if (p) setAmount(Number(p.price));
    setExpireTouched(false);
  };
  const computedExpire = start && cycle ? addMonths(start, CYCLE_MONTHS[cycle]) : '';
  const expireShown = expireTouched ? expire : computedExpire;

  const done = (msg: string) => { notifications.show({ color: 'green', message: msg }); qc.invalidateQueries({ queryKey: ['linode-servers'] }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); onClose(); };
  const bill = useMutation({
    mutationFn: () => billLinodeServer(resource.id, {
      client_id: clientId!, product_service_id: productId!, amount: Number(amount), billing_cycle: cycle ?? undefined,
      start_date: start, expire_date: mode === 'paid_outside' ? expireShown : null, label, mode,
    }),
    onSuccess: (r) => { done(r.data.message); if (r.data.data.document_id) navigate('/invoices'); },
    onError: (e) => setError(errMsg(e)),
  });
  const link = useMutation({
    mutationFn: () => linkLinodeSubscription(resource.id, existingId!),
    onSuccess: (r) => done(r.data.message), onError: (e) => setError(errMsg(e)),
  });

  const canSubmit = !!clientId && !!productId && Number(amount) > 0 && !!start && confirm && (mode === 'invoice_now' || !!expireShown);
  return (
    <Modal opened onClose={onClose} title={`Bill server "${resource.label}"`} size="lg">
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Alert color="blue" variant="light">Billing only. Nothing is changed at Linode: suspending or cancelling this subscription never touches the server.</Alert>
        <Select label="Client" data={options} value={clientId}
          onChange={(v) => { setClientId(v); setExistingId(null); setPickedLabel(options.find((o) => o.value === v)?.label ?? null); }}
          searchValue={search} onSearchChange={setSearch} filter={({ options }) => options} nothingFoundMessage="No client found" searchable clearable placeholder="Search name, email or phone"
          description="Choosing a client also maps this server to them." />
        <Tabs value={tab} onChange={setTab}>
          <Tabs.List><Tabs.Tab value="new">New subscription</Tabs.Tab><Tabs.Tab value="existing">Link existing subscription</Tabs.Tab></Tabs.List>
          <Tabs.Panel value="new" pt="sm">
            <Stack>
              <Select label="Linode product" data={products.map((p) => ({ value: p.id, label: `${p.name} — ${money(p.price)} / ${CYCLE_LABEL[p.billing_cycle] ?? p.billing_cycle}` }))}
                value={productId} onChange={pickProduct} placeholder={products.length ? 'Choose a product' : 'No Linode products yet'}
                nothingFoundMessage="None" searchable
                description={products.length ? undefined : 'Create one in Products & Services: type Service, Provisioning = Linode Server, a yearly/monthly cycle.'} />
              <Group grow align="flex-start">
                <NumberInput label="Billing amount (TZS)" value={amount} onChange={setAmount} min={0} thousandSeparator="," hideControls
                  description={product && Number(amount) !== Number(product.price) ? `Overrides the product price (${money(product.price)}) for this server` : 'Defaults to the product price'} />
                <TextInput label="Billing cycle" value={cycle ? CYCLE_LABEL[cycle] : ''} readOnly description="Set by the chosen product" />
              </Group>
              <Group grow align="flex-start">
                <TextInput type="date" label="Start date" value={start} onChange={(e) => { setStart(e.currentTarget.value); setExpireTouched(false); }} required />
                <TextInput type="date" label="Expiry / next due date" value={mode === 'paid_outside' ? expireShown : computedExpire}
                  onChange={(e) => { setExpire(e.currentTarget.value); setExpireTouched(true); }} disabled={mode !== 'paid_outside'}
                  description={mode === 'paid_outside' ? 'Start + cycle; editable. The next invoice is generated ~30 days before this date.' : 'Set automatically when the invoice is paid'} />
              </Group>
              <TextInput label="Label" value={label} onChange={(e) => setLabel(e.currentTarget.value)} />
              <Radio.Group label="Current period" value={mode} onChange={(v) => setMode(v as any)}>
                <Stack gap={6} mt={6}>
                  <Radio value="paid_outside" label="Already paid / invoiced outside the system (do not create an invoice now; next invoice at renewal)" />
                  <Radio value="invoice_now" label="Create invoice now (subscription stays pending until the invoice is paid)" />
                </Stack>
              </Radio.Group>
              <Checkbox checked={confirm} onChange={(e) => setConfirm(e.currentTarget.checked)}
                label={`Confirm: bill ${money(Number(amount) || 0)} ${cycle ? CYCLE_LABEL[cycle].toLowerCase() : ''} from ${start || '…'}${mode === 'paid_outside' ? `, paid until ${expireShown || '…'}, no invoice now` : ', invoice created now'}`} />
              <Button loading={bill.isPending} disabled={!canSubmit} onClick={() => { setError(null); bill.mutate(); }}>Create subscription</Button>
            </Stack>
          </Tabs.Panel>
          <Tabs.Panel value="existing" pt="sm">
            <Stack>
              {!clientId && <Text size="sm" c="dimmed">Choose a client first.</Text>}
              {clientId && (
                <Select label="Client's subscription" data={existing.map((x) => ({ value: x.id, label: `${x.label || x.product_name || x.id} (${x.status}${x.expire_date ? ', to ' + x.expire_date : ''})` }))}
                  value={existingId} onChange={setExistingId} nothingFoundMessage="No unlinked subscriptions for this client" placeholder="Choose subscription" />
              )}
              <Button loading={link.isPending} disabled={!clientId || !existingId} onClick={() => { setError(null); link.mutate(); }}>Link to this server</Button>
            </Stack>
          </Tabs.Panel>
        </Tabs>
      </Stack>
    </Modal>
  );
}

function ServersTab({ canManage, onShowDomains }: { canManage: boolean; onShowDomains: (id: string) => void }) {
  const { can } = usePermissions();
  const canBill = can('linode.manage') && can('client_subscriptions.create');
  const canPower = can('linode.power');
  const [powerFor, setPowerFor] = useState<{ s: LinodeResource; action: PowerAction } | null>(null);
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [mapFor, setMapFor] = useState<LinodeResource | null>(null);
  const [billFor, setBillFor] = useState<LinodeResource | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [billFilter, setBillFilter] = useState<string>('all');
  const { data, isLoading, isError, error } = useQuery({ queryKey: ['linode-servers'], queryFn: getLinodeServers });
  const allRows = data?.data?.data ?? [];
  const unbilledCount = allRows.filter((s) => s.status !== 'gone' && !s.subscription).length;
  const rows = billFilter === 'unbilled' ? allRows.filter((s) => !s.subscription) : allRows;
  const unlink = useMutation({
    mutationFn: (id: string) => unlinkLinodeSubscription(id),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['linode-servers'] }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  if (isLoading) return <Center><Loader /></Center>;
  if (isError) return <Alert color="red">{errMsg(error)}</Alert>;
  if (!allRows.length) return <Paper withBorder p="xl"><Text ta="center" c="dimmed">No servers yet. Connect a Linode account and press &quot;Sync now&quot; on the Accounts tab.</Text></Paper>;
  return (
    <Paper withBorder>
      <Group p="sm" gap="sm">
        <Select size="xs" w={220} value={billFilter} onChange={(v) => setBillFilter(v ?? 'all')} allowDeselect={false}
          data={[{ value: 'all', label: 'All servers' }, { value: 'unbilled', label: `Unbilled servers (${unbilledCount})` }]} />
      </Group>
      <Table.ScrollContainer minWidth={1150}>
        <Table verticalSpacing="sm">
          <Table.Thead><Table.Tr><Table.Th>Label</Table.Th><Table.Th>Status</Table.Th><Table.Th>Region</Table.Th><Table.Th>Plan</Table.Th><Table.Th>IPv4</Table.Th><Table.Th>Domains</Table.Th><Table.Th>Client</Table.Th><Table.Th>Billing</Table.Th><Table.Th>Last synced</Table.Th><Table.Th /></Table.Tr></Table.Thead>
          <Table.Tbody>
            {rows.map((s) => (
              <Table.Tr key={s.id}>
                <Table.Td>{s.label}<Text size="xs" c="dimmed">{s.account_label}</Text></Table.Td>
                <Table.Td><Badge color={s.status === 'running' ? 'green' : s.status === 'gone' ? 'red' : BUSY_STATUSES.includes(s.status ?? '') ? 'yellow' : 'gray'}>{s.status === 'gone' ? 'removed at Linode' : s.status}</Badge></Table.Td>
                <Table.Td>{s.region}</Table.Td>
                <Table.Td>{s.plan}</Table.Td>
                <Table.Td>{s.ipv4.join(', ')}</Table.Td>
                <Table.Td>
                  {s.domain_count ? (
                    <Stack gap={2}>
                      <Group gap={4} wrap="nowrap">
                        <Button size="compact-xs" variant="light" onClick={() => onShowDomains(s.id)}>{s.domain_count} domain(s)</Button>
                        <Button size="compact-xs" variant="subtle" onClick={() => setOpen(open === s.id ? null : s.id)}>{open === s.id ? 'hide' : 'list'}</Button>
                      </Group>
                      {open === s.id && <Stack gap={0}>{(s.domains ?? []).map((d) => <Text key={d.id} size="xs">{d.label}</Text>)}</Stack>}
                    </Stack>
                  ) : <Text c="dimmed" size="sm">none (refresh DNS mapping)</Text>}
                </Table.Td>
                <Table.Td>
                  {s.client_name ?? <Text c="dimmed" size="sm">unmapped</Text>}
                  {!s.client_name && s.suggested_client && (
                    <Text size="xs" c="blue">Suggested: {s.suggested_client.name} (all {s.suggested_client.domains} domain(s) belong to them)</Text>
                  )}
                </Table.Td>
                <Table.Td>
                  {s.subscription ? (
                    <Stack gap={2}>
                      <Badge color={BILL_STATE[s.subscription.state]?.color ?? 'gray'}>{BILL_STATE[s.subscription.state]?.label ?? s.subscription.state}</Badge>
                      <Text size="xs">{money(s.subscription.amount)} / {CYCLE_LABEL[s.subscription.billing_cycle ?? ''] ?? s.subscription.billing_cycle}</Text>
                      <Text size="xs" c="dimmed">Expires {s.subscription.expire_date ?? '—'}</Text>
                      <Text size="xs" c="dimmed">Next invoice {s.subscription.next_invoice_date ?? '—'}</Text>
                      {s.subscription.latest_invoice && (
                        <Text size="xs" c="blue" style={{ cursor: 'pointer' }} onClick={() => navigate('/invoices')}>
                          {s.subscription.latest_invoice.number} ({s.subscription.latest_invoice.status})
                        </Text>
                      )}
                    </Stack>
                  ) : <Badge color="gray" variant="light">Unbilled</Badge>}
                </Table.Td>
                <Table.Td>{fmt(s.synced_at)}</Table.Td>
                <Table.Td>
                  <Stack gap={4}>
                    {canPower && s.status !== 'gone' && (
                      <Menu withinPortal position="bottom-end">
                        <Menu.Target><Button size="xs" variant="light" color="red" leftSection={<IconPower size={14} />}>Power</Button></Menu.Target>
                        <Menu.Dropdown>
                          <Menu.Item disabled={s.status !== 'running'} onClick={() => setPowerFor({ s, action: 'reboot' })}>Reboot</Menu.Item>
                          <Menu.Item color="red" disabled={s.status !== 'running'} onClick={() => setPowerFor({ s, action: 'shutdown' })}>Shutdown</Menu.Item>
                          <Menu.Item disabled={s.status !== 'offline'} onClick={() => setPowerFor({ s, action: 'boot' })}>Boot</Menu.Item>
                        </Menu.Dropdown>
                      </Menu>
                    )}
                    {canManage && <Button size="xs" variant="light" leftSection={<IconLink size={14} />} onClick={() => setMapFor(s)}>Map to client</Button>}
                    {canBill && !s.subscription && s.status !== 'gone' && <Button size="xs" leftSection={<IconReceipt size={14} />} onClick={() => setBillFor(s)}>Bill this server</Button>}
                    {canManage && s.subscription && <Button size="xs" variant="subtle" color="gray" loading={unlink.isPending} onClick={() => { if (window.confirm('Unlink this subscription from the server? The subscription keeps billing; nothing changes at Linode.')) unlink.mutate(s.id); }}>Unlink</Button>}
                  </Stack>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {powerFor && <LinodePowerModal server={powerFor.s} action={powerFor.action} onClose={() => setPowerFor(null)} />}
      {mapFor && <MapModal resource={mapFor} onClose={() => setMapFor(null)} />}
      {billFor && <BillModal resource={billFor} onClose={() => setBillFor(null)} />}
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

const DNS_STATUS_OPTIONS: { value: DnsStatus; label: string }[] = [
  { value: 'server', label: 'Points to our server' },
  { value: 'external', label: 'External IP' },
  { value: 'no_a_record', label: 'No A record' },
  { value: 'unknown', label: 'Not checked yet' },
];

function PointsTo({ d, onServer }: { d: LinodeResource; onServer: (id: string) => void }) {
  const dns = d.dns;
  if (!dns || dns.status === 'unknown') {
    return <Tooltip label={dns?.error ?? 'Press "Refresh DNS mapping"'}><Text size="sm" c={dns?.error ? 'red' : 'dimmed'}>{dns?.error ? 'error' : 'not checked'}</Text></Tooltip>;
  }
  return (
    <Stack gap={2}>
      {dns.status === 'server' && (
        <Group gap={4}>
          {dns.servers.map((s) => (
            <Tooltip key={s.id} label={`${s.apex ? 'root' : ''}${s.apex && s.www ? ' + ' : ''}${s.www ? 'www' : ''}`}>
              <Badge component="button" style={{ cursor: 'pointer' }} variant="light" onClick={() => onServer(s.id)}>{s.label}</Badge>
            </Tooltip>
          ))}
        </Group>
      )}
      {dns.external_ips.length > 0 && <Badge color="orange" variant="light">External IP {dns.external_ips.join(', ')}</Badge>}
      {dns.status === 'no_a_record' && <Badge color="gray" variant="light">No A record</Badge>}
      {dns.error && <Text size="xs" c="red">last refresh failed</Text>}
    </Stack>
  );
}

function DnsRefreshButton() {
  const qc = useQueryClient();
  const { data: accData } = useQuery({ queryKey: ['linode-accounts'], queryFn: getLinodeAccounts });
  const accounts = (accData?.data?.data ?? []).filter((a) => a.status === 'active');
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const run = async () => {
    const failed: { domain: string; error: string }[] = [];
    let ok = 0;
    try {
      for (const acc of accounts) {
        let offset: number | null = 0;
        while (offset !== null) {
          const r: DnsRefreshBatch = (await refreshLinodeDns(acc.id, offset)).data;
          ok += r.ok; failed.push(...r.failed);
          setProgress({ done: (offset ?? 0) + r.processed, total: r.total });
          offset = r.next_offset;
        }
      }
      notifications.show({
        color: failed.length ? 'yellow' : 'green', autoClose: failed.length ? 12000 : 4000, title: 'DNS mapping refreshed',
        message: `${ok} domain(s) checked` + (failed.length ? `; ${failed.length} failed (${failed.slice(0, 3).map((f) => f.domain).join(', ')}${failed.length > 3 ? ', ...' : ''}). Press again to retry those.` : '.'),
      });
    } catch (e) {
      notifications.show({ color: 'red', title: 'DNS mapping', message: errMsg(e) });
    } finally {
      setProgress(null);
      qc.invalidateQueries({ queryKey: ['linode-domains'] });
      qc.invalidateQueries({ queryKey: ['linode-servers'] });
    }
  };
  return (
    <Button variant="light" leftSection={<IconRefresh size={16} />} loading={!!progress} disabled={!accounts.length} onClick={run}>
      {progress ? `Checking DNS ${progress.done}/${progress.total}` : 'Refresh DNS mapping'}
    </Button>
  );
}

function AutoMapModal({ rows, onClose }: { rows: LinodeResource[]; onClose: () => void }) {
  const qc = useQueryClient();
  const m = useMutation({
    mutationFn: () => autoMapLinodeClients(rows.map((r) => r.id)),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); qc.invalidateQueries({ queryKey: ['linode-domains'] }); qc.invalidateQueries({ queryKey: ['linode-servers'] }); onClose(); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  return (
    <Modal opened onClose={onClose} title="Auto-map suggested clients" size="lg">
      <Stack>
        <Text size="sm">These {rows.length} domain(s) are registered with us and currently unmapped. Each will be mapped to the client that owns it in MoBilling. Existing mappings are never changed.</Text>
        {/* Table.ScrollContainer only scrolls horizontally, so a long list was cut off with no way to see the rest. */}
        <ScrollArea.Autosize mah={360} type="auto" offsetScrollbars>
          <Table verticalSpacing="xs"><Table.Tbody>
            {rows.map((r) => <Table.Tr key={r.id}><Table.Td>{r.label}</Table.Td><Table.Td>&rarr; {r.suggested_client?.name}</Table.Td></Table.Tr>)}
          </Table.Tbody></Table>
        </ScrollArea.Autosize>
        <Group justify="flex-end"><Button variant="default" onClick={onClose}>Cancel</Button><Button loading={m.isPending} onClick={() => m.mutate()}>Map {rows.length} domain(s)</Button></Group>
      </Stack>
    </Modal>
  );
}

function DomainsTab({ canManage, serverFilter, setServerFilter }: { canManage: boolean; serverFilter: string | null; setServerFilter: (v: string | null) => void }) {
  const qc = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [recordsFor, setRecordsFor] = useState<LinodeResource | null>(null);
  const [mapFor, setMapFor] = useState<LinodeResource | null>(null);
  const { data, isLoading, isError, error } = useQuery({ queryKey: ['linode-domains'], queryFn: getLinodeDomains });
  const allRows = data?.data?.data ?? [];
  const lastRefreshed = data?.data?.dns_last_refreshed ?? null;
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [autoMap, setAutoMap] = useState(false);
  const { data: srvData } = useQuery({ queryKey: ['linode-servers'], queryFn: getLinodeServers });
  const servers = srvData?.data?.data ?? [];
  const rows = useMemo(() => allRows.filter((d) =>
    (!serverFilter || d.dns?.servers.some((s) => s.id === serverFilter))
    && (!statusFilter || (d.dns?.status ?? 'unknown') === statusFilter)), [allRows, serverFilter, statusFilter]);
  const suggestions = allRows.filter((d) => !d.client_id && d.suggested_client);
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
      <Group align="flex-end">
        {canManage && <Button leftSection={<IconPlus size={16} />} onClick={() => setAdding(true)}>Add domain</Button>}
        {canManage && <DnsRefreshButton />}
        {canManage && suggestions.length > 0 && <Button variant="light" color="teal" leftSection={<IconWand size={16} />} onClick={() => setAutoMap(true)}>Auto-map suggested clients ({suggestions.length})</Button>}
        <Select placeholder="Filter by server" clearable size="sm" data={servers.map((s) => ({ value: s.id, label: `${s.label} (${s.domain_count ?? 0})` }))} value={serverFilter} onChange={setServerFilter} />
        <Select placeholder="Filter by DNS status" clearable size="sm" data={DNS_STATUS_OPTIONS} value={statusFilter} onChange={setStatusFilter} />
        <Text size="xs" c="dimmed">DNS mapping last refreshed: {fmt(lastRefreshed)}</Text>
      </Group>
      {isLoading ? <Center><Loader /></Center> : isError ? <Alert color="red">{errMsg(error)}</Alert> : !rows.length ? (
        <Paper withBorder p="xl"><Text ta="center" c="dimmed">{allRows.length ? 'No domains match the filters.' : 'No domains yet. Sync an account or add a domain.'}</Text></Paper>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={1000}>
            <Table verticalSpacing="sm">
              <Table.Thead><Table.Tr><Table.Th>Domain</Table.Th><Table.Th>Status</Table.Th><Table.Th>Account</Table.Th><Table.Th>Points to</Table.Th><Table.Th>Registered with us</Table.Th><Table.Th>Client</Table.Th><Table.Th /></Table.Tr></Table.Thead>
              <Table.Tbody>
                {rows.map((d) => (
                  <Table.Tr key={d.id}>
                    <Table.Td>{d.label}</Table.Td>
                    <Table.Td><Badge color={d.status === 'active' ? 'green' : d.status === 'gone' ? 'red' : 'gray'}>{d.status === 'gone' ? 'removed at Linode' : d.status}</Badge></Table.Td>
                    <Table.Td>{d.account_label}</Table.Td>
                    <Table.Td><PointsTo d={d} onServer={setServerFilter} /></Table.Td>
                    <Table.Td>{d.our_domain ? <Badge variant="light">{d.our_domain.status}</Badge> : <Text size="sm" c="dimmed">no</Text>}</Table.Td>
                    <Table.Td>
                      {d.client_name ?? <Text size="sm" c="dimmed">unmapped</Text>}
                      {!d.client_name && d.suggested_client && <Text size="xs" c="blue">Suggested: {d.suggested_client.name}</Text>}
                    </Table.Td>
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
      {autoMap && <AutoMapModal rows={suggestions} onClose={() => setAutoMap(false)} />}
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

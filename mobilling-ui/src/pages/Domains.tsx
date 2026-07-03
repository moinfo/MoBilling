import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, ActionIcon, Tooltip, Text, Paper, Select,
  TextInput, Loader, Center, Drawer, Modal, Button, Pagination, Code, NumberInput,
  Alert, CopyButton,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconSearch, IconWorldWww, IconPlus, IconHistory, IconRefresh, IconKey,
  IconCheck, IconX, IconCopy,
} from '@tabler/icons-react';
import {
  checkDomain, getDomains, getDomainLogs, orderDomain, renewDomain, getDomainAuthInfo,
  DomainRecord, DomainCheckResult, DomainLogRow, DOMAIN_STATUS_COLORS,
} from '../api/domains';
import { getClients } from '../api/clients';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';
import dayjs from 'dayjs';

export default function Domains() {
  const { can } = usePermissions();
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [wizardOpen, setWizardOpen] = useState(false);
  const [logsFor, setLogsFor] = useState<DomainRecord | null>(null);
  const [renewFor, setRenewFor] = useState<DomainRecord | null>(null);
  const [authInfoFor, setAuthInfoFor] = useState<{ domain: DomainRecord; code: string | null } | null>(null);

  const params: Record<string, string> = { page: String(page) };
  if (statusFilter) params.status = statusFilter;
  if (search) params.search = search;

  const { data, isLoading } = useQuery({
    queryKey: ['domains', params],
    queryFn: () => getDomains(params),
  });
  const domains: DomainRecord[] = data?.data?.data?.data ?? [];
  const lastPage: number = data?.data?.data?.last_page ?? 1;

  const revealAuthInfo = async (d: DomainRecord) => {
    try {
      const res = await getDomainAuthInfo(d.id);
      setAuthInfoFor({ domain: d, code: res.data.auth_info });
    } catch {
      notifications.show({ message: 'Could not fetch the transfer code.', color: 'red' });
    }
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <IconWorldWww size={22} />
          <Title order={2}>Domains</Title>
        </Group>
        {can('domains.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => setWizardOpen(true)}>
            Register / Transfer
          </Button>
        )}
      </Group>

      <Group gap="xs">
        <TextInput size="xs" placeholder="Search domain…" leftSection={<IconSearch size={13} />}
          value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} w={220} />
        <Select size="xs" placeholder="All statuses" clearable w={160}
          value={statusFilter} onChange={(v) => { setStatusFilter(v ?? ''); setPage(1); }}
          data={[
            { value: 'pending', label: 'Pending' },
            { value: 'active', label: 'Active' },
            { value: 'expired', label: 'Expired' },
            { value: 'failed', label: 'Failed' },
            { value: 'cancelled', label: 'Cancelled' },
          ]} />
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : domains.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No domains yet.</Text></Center>
      ) : (
        <Paper withBorder radius="md">
          <Table.ScrollContainer minWidth={760}>
            <Table highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Registered</Table.Th>
                  <Table.Th>Expires</Table.Th>
                  <Table.Th>Auto-renew</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th></Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {domains.map((d) => {
                  const expiringSoon = d.expires_at && dayjs(d.expires_at).diff(dayjs(), 'day') <= 45;
                  return (
                    <Table.Tr key={d.id}>
                      <Table.Td fw={500}>{d.name}</Table.Td>
                      <Table.Td><Text size="sm">{d.client?.name ?? '—'}</Text></Table.Td>
                      <Table.Td><Text size="sm" c="dimmed">{d.registered_at ?? '—'}</Text></Table.Td>
                      <Table.Td>
                        <Text size="sm" c={expiringSoon ? 'red' : undefined} fw={expiringSoon ? 600 : undefined}>
                          {d.expires_at ?? '—'}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        {d.auto_renew
                          ? <IconCheck size={15} color="var(--mantine-color-green-6)" />
                          : <IconX size={15} color="var(--mantine-color-gray-5)" />}
                      </Table.Td>
                      <Table.Td>
                        <Badge size="sm" color={DOMAIN_STATUS_COLORS[d.status]} variant="light">
                          {d.status}
                        </Badge>
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4} justify="flex-end" wrap="nowrap">
                          {can('domains.renew') && ['active', 'expired'].includes(d.status) && (
                            <Tooltip label="Renew (creates invoice)">
                              <ActionIcon variant="light" color="green" onClick={() => setRenewFor(d)}>
                                <IconRefresh size={15} />
                              </ActionIcon>
                            </Tooltip>
                          )}
                          {can('domains.transfer') && (
                            <Tooltip label="Transfer code">
                              <ActionIcon variant="light" color="orange" onClick={() => revealAuthInfo(d)}>
                                <IconKey size={15} />
                              </ActionIcon>
                            </Tooltip>
                          )}
                          <Tooltip label="Registry log">
                            <ActionIcon variant="light" onClick={() => setLogsFor(d)}>
                              <IconHistory size={15} />
                            </ActionIcon>
                          </Tooltip>
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {lastPage > 1 && (
        <Group justify="center"><Pagination value={page} onChange={setPage} total={lastPage} size="sm" /></Group>
      )}

      <OrderWizard opened={wizardOpen} onClose={() => setWizardOpen(false)} />

      <RenewModal domain={renewFor} onClose={() => setRenewFor(null)} />

      <Drawer opened={!!logsFor} onClose={() => setLogsFor(null)}
        title={`Registry log — ${logsFor?.name ?? ''}`} position="right" size="md">
        {logsFor && <DomainLogsList domainId={logsFor.id} />}
      </Drawer>

      <Modal opened={!!authInfoFor} onClose={() => setAuthInfoFor(null)}
        title={`Transfer code — ${authInfoFor?.domain.name}`} centered>
        {authInfoFor?.code ? (
          <Group>
            <Code fz="md">{authInfoFor.code}</Code>
            <CopyButton value={authInfoFor.code}>
              {({ copied, copy }) => (
                <Button size="xs" variant="light" color={copied ? 'green' : 'blue'}
                  leftSection={<IconCopy size={13} />} onClick={copy}>
                  {copied ? 'Copied' : 'Copy'}
                </Button>
              )}
            </CopyButton>
          </Group>
        ) : (
          <Text size="sm" c="dimmed">No transfer code stored for this domain.</Text>
        )}
        <Text size="xs" c="dimmed" mt="sm">This access is recorded in the domain's registry log.</Text>
      </Modal>
    </Stack>
  );
}

// ── Register / Transfer wizard ─────────────────────────────────────────────────

function OrderWizard({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const [action, setAction] = useState<'register' | 'transfer'>('register');
  const [name, setName] = useState('');
  const [checked, setChecked] = useState<DomainCheckResult | null>(null);
  const [checking, setChecking] = useState(false);
  const [clientId, setClientId] = useState<string | null>(null);
  const [years, setYears] = useState<number>(1);
  const [authInfo, setAuthInfo] = useState('');

  const { data: clientsData } = useQuery({
    queryKey: ['clients-for-domains'],
    queryFn: () => getClients({ per_page: 200 }),
    enabled: opened,
  });
  const clientOptions = (clientsData?.data?.data ?? []).map((c: any) => ({ value: c.id, label: c.name }));

  const doCheck = async () => {
    if (!name.trim()) return;
    setChecking(true);
    setChecked(null);
    try {
      const res = await checkDomain(name.trim().toLowerCase());
      setChecked(res.data);
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Check failed.', color: 'red' });
    } finally {
      setChecking(false);
    }
  };

  const orderMutation = useMutation({
    mutationFn: () => orderDomain({
      name: name.trim().toLowerCase(),
      client_id: clientId!,
      years,
      action,
      auth_info: action === 'transfer' ? authInfo : undefined,
    }),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['domains'] });
      notifications.show({ title: 'Order created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      handleClose();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Order failed.', color: 'red',
    }),
  });

  const handleClose = () => {
    setName(''); setChecked(null); setClientId(null); setYears(1); setAuthInfo('');
    onClose();
  };

  const pricing = checked?.pricing;
  const unit = action === 'register' ? pricing?.register_price : pricing?.transfer_price;
  const canSubmit = clientId && checked && pricing
    && (action === 'transfer' ? authInfo.trim().length > 0 : checked.available);

  return (
    <Modal opened={opened} onClose={handleClose} title="Register / Transfer Domain" centered size="lg">
      <Stack gap="sm">
        <Select label="Action" value={action}
          onChange={(v) => { setAction((v as any) ?? 'register'); setChecked(null); }}
          data={[
            { value: 'register', label: 'Register new domain' },
            { value: 'transfer', label: 'Transfer in (from another registrar)' },
          ]} />

        <Group align="flex-end" gap="xs">
          <TextInput label="Domain name" placeholder="example.co.tz" style={{ flex: 1 }}
            value={name} onChange={(e) => { setName(e.currentTarget.value); setChecked(null); }} />
          <Button variant="light" loading={checking} onClick={doCheck} disabled={!name.trim()}>
            Check
          </Button>
        </Group>

        {checked && (
          <Alert
            color={action === 'transfer' ? 'blue' : checked.available ? 'green' : 'red'}
            icon={checked.available ? <IconCheck size={16} /> : <IconX size={16} />}
          >
            {action === 'register'
              ? (checked.available
                  ? `${checked.name} is available!`
                  : `${checked.name} is not available${checked.reason ? ` — ${checked.reason}` : ''}`)
              : (checked.available
                  ? `${checked.name} is not registered — nothing to transfer.`
                  : `${checked.name} is registered — transfer possible with its auth code.`)}
            {pricing === null && (
              <Text size="xs" mt={4}>⚠ No pricing configured for this TLD — add it in Settings → Domains first.</Text>
            )}
          </Alert>
        )}

        <Select label="Client" placeholder="Who is this domain for?" searchable required
          data={clientOptions} value={clientId} onChange={setClientId} />

        <Group grow>
          <NumberInput label="Years" min={pricing?.years_min ?? 1} max={pricing?.years_max ?? 10}
            value={years} onChange={(v) => setYears(Number(v) || 1)} />
          {action === 'transfer' && (
            <TextInput label="Auth-info (transfer code)" required
              value={authInfo} onChange={(e) => setAuthInfo(e.currentTarget.value)} />
          )}
        </Group>

        {pricing && unit !== undefined && (
          <Paper withBorder p="sm" radius="md">
            <Group justify="space-between">
              <Text size="sm">{years} year(s) × {formatCurrency(unit)}</Text>
              <Text fw={700}>{formatCurrency(unit * years)}</Text>
            </Group>
            <Text size="xs" c="dimmed" mt={4}>
              An invoice is created now; the domain is {action === 'register' ? 'registered' : 'transferred'} at
              the registry automatically after the invoice is paid.
            </Text>
          </Paper>
        )}

        <Group justify="flex-end">
          <Button variant="default" onClick={handleClose}>Cancel</Button>
          <Button disabled={!canSubmit} loading={orderMutation.isPending} onClick={() => orderMutation.mutate()}>
            Create Order & Invoice
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

// ── Renew modal ────────────────────────────────────────────────────────────────

function RenewModal({ domain, onClose }: { domain: DomainRecord | null; onClose: () => void }) {
  const qc = useQueryClient();
  const [years, setYears] = useState(1);

  const mutation = useMutation({
    mutationFn: () => renewDomain(domain!.id, years),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['domains'] });
      notifications.show({ title: 'Renewal invoice created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      onClose();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Renewal failed.', color: 'red',
    }),
  });

  return (
    <Modal opened={!!domain} onClose={onClose} title={`Renew ${domain?.name}`} centered>
      <Stack>
        <NumberInput label="Years" min={1} max={10} value={years} onChange={(v) => setYears(Number(v) || 1)} />
        <Text size="xs" c="dimmed">
          Creates a renewal invoice; the registry renewal runs automatically once it is paid.
        </Text>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="green" loading={mutation.isPending} onClick={() => mutation.mutate()}>
            Create Renewal Invoice
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

// ── Logs ───────────────────────────────────────────────────────────────────────

function DomainLogsList({ domainId }: { domainId: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['domain-logs', domainId],
    queryFn: () => getDomainLogs(domainId),
  });
  const logs: DomainLogRow[] = data?.data?.data ?? [];

  if (isLoading) return <Center py="md"><Loader size="sm" /></Center>;
  if (!logs.length) return <Text c="dimmed" size="sm">No log entries yet.</Text>;

  return (
    <Stack gap="xs">
      {logs.map((l) => (
        <Paper key={l.id} withBorder p="xs" radius="sm">
          <Group justify="space-between" wrap="nowrap">
            <Group gap="xs">
              <Badge size="xs" color={l.status === 'success' ? 'green' : 'red'} variant="light">{l.status}</Badge>
              <Code>{l.action}</Code>
            </Group>
            <Text size="xs" c="dimmed">{dayjs(l.created_at).format('D MMM YYYY HH:mm')}</Text>
          </Group>
          {l.error && <Text size="xs" c="red" mt={4}>{l.error}</Text>}
        </Paper>
      ))}
    </Stack>
  );
}

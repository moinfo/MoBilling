import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, ActionIcon, Tooltip, Text, Paper, Select,
  TextInput, Loader, Center, Drawer, Modal, Button, Pagination, Code, NumberInput,
  Alert, CopyButton, SimpleGrid, ThemeIcon, Switch, Anchor,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { notifications } from '@mantine/notifications';
import {
  IconSearch, IconWorldWww, IconPlus, IconHistory, IconRefresh, IconKey,
  IconCheck, IconX, IconCopy, IconWorld, IconWallet, IconArrowsLeftRight, IconClockExclamation, IconAlertTriangle,
  IconHourglass, IconRepeat, IconShieldCheck, IconShieldOff,
} from '@tabler/icons-react';
import {
  checkDomain, getDomains, getDomainStats, getRegistrarCredit, getDomainLogs, orderDomain, renewDomain,
  getDomainAuthInfo, setDomainAutoRenew, describeDomainAction,
  createCreditTransfer, completeCreditTransfer, cancelCreditTransfer, RegistrarCredit, TransferEmail,
  DomainRecord, DomainCheckResult, DomainLogRow, DOMAIN_STATUS_COLORS,
} from '../api/domains';
import { getClients } from '../api/clients';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';
import dayjs from 'dayjs';

function DomainStatCard({ icon, color, label, value, active, onClick }: {
  icon: React.ReactNode; color: string; label: string; value: number | string;
  active?: boolean; onClick?: () => void;
}) {
  return (
    <Paper withBorder radius="md" p="sm"
      style={{
        cursor: onClick ? 'pointer' : undefined,
        borderColor: active ? `var(--mantine-color-${color}-6)` : undefined,
      }}
      onClick={onClick}>
      <Group gap="sm" wrap="nowrap">
        <ThemeIcon variant={active ? 'filled' : 'light'} color={color} size={38} radius="md">{icon}</ThemeIcon>
        <div style={{ minWidth: 0 }}>
          <Text size="lg" fw={700} lh={1.2} truncate>{value}</Text>
          <Text size="xs" c="dimmed" truncate>{label}</Text>
        </div>
      </Group>
    </Paper>
  );
}

export default function Domains() {
  const { can } = usePermissions();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [togglingId, setTogglingId] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState('');
  const [expiringOnly, setExpiringOnly] = useState(false);
  const [oursFilter, setOursFilter] = useState<'' | '1' | '0'>('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [wizardOpen, setWizardOpen] = useState(false);
  const [logsFor, setLogsFor] = useState<DomainRecord | null>(null);
  const [renewFor, setRenewFor] = useState<DomainRecord | null>(null);
  const [authInfoFor, setAuthInfoFor] = useState<{ domain: DomainRecord; code: string | null } | null>(null);

  const params: Record<string, string> = { page: String(page) };
  if (statusFilter) params.status = statusFilter;
  if (expiringOnly) params.expiring = '1';
  if (oursFilter) params.ours = oursFilter;
  if (search) params.search = search;

  // stat card click: toggle the corresponding filter
  const filterByStatus = (status: string) => {
    setExpiringOnly(false);
    setOursFilter('');
    setStatusFilter((cur) => (cur === status && !expiringOnly ? '' : status));
    setPage(1);
  };
  const filterExpiring = () => {
    setStatusFilter('');
    setOursFilter('');
    setExpiringOnly((v) => !v);
    setPage(1);
  };
  const filterOurs = (v: '1' | '0') => {
    setStatusFilter('');
    setExpiringOnly(false);
    setOursFilter((cur) => (cur === v ? '' : v));
    setPage(1);
  };

  const { data, isLoading } = useQuery({
    queryKey: ['domains', params],
    queryFn: () => getDomains(params),
  });

  const { data: statsData } = useQuery({
    queryKey: ['domain-stats'],
    queryFn: getDomainStats,
  });
  const stats = statsData?.data?.data;

  const { data: creditData } = useQuery({
    queryKey: ['registrar-credit'],
    queryFn: getRegistrarCredit,
    staleTime: 5 * 60 * 1000,
  });
  const registrarCredit = creditData?.data?.data;
  const [transferOpen, setTransferOpen] = useState(false);
  const [completingId, setCompletingId] = useState<string | null>(null);

  const completeTransfer = async (id: string) => {
    setCompletingId(id);
    try {
      const res = await completeCreditTransfer(id);
      qc.invalidateQueries({ queryKey: ['registrar-credit'] });
      notifications.show({ message: res.data.message, color: 'green' });
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Failed.', color: 'red' });
    } finally { setCompletingId(null); }
  };
  const cancelTransfer = async (id: string) => {
    try {
      await cancelCreditTransfer(id);
      qc.invalidateQueries({ queryKey: ['registrar-credit'] });
      notifications.show({ message: 'Transfer request cancelled.', color: 'gray' });
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Failed.', color: 'red' });
    }
  };

  const toggleAutoRenew = async (d: DomainRecord, enabled: boolean) => {
    setTogglingId(d.id);
    try {
      const res = await setDomainAutoRenew(d.id, enabled);
      qc.invalidateQueries({ queryKey: ['domains'] });
      qc.invalidateQueries({ queryKey: ['domain-stats'] });
      notifications.show({ message: res.data.message, color: enabled ? 'teal' : 'gray' });
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not change auto-renew.', color: 'red' });
    } finally {
      setTogglingId(null);
    }
  };
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

      <SimpleGrid cols={{ base: 2, sm: 3, lg: 4 }} spacing="sm">
        <DomainStatCard icon={<IconWorld size={20} />} color="blue" label="Total Domains"
          value={stats?.total ?? '—'} active={!statusFilter && !expiringOnly && !oursFilter}
          onClick={() => { setStatusFilter(''); setExpiringOnly(false); setOursFilter(''); setPage(1); }} />
        <DomainStatCard icon={<IconCheck size={20} />} color="green" label="Active"
          value={stats?.active ?? '—'} active={statusFilter === 'active' && !expiringOnly}
          onClick={() => filterByStatus('active')} />
        <DomainStatCard icon={<IconShieldCheck size={20} />} color="teal"
          label={`On ${stats?.our_registrar ?? 'Our Registrar'}`}
          value={stats?.ours ?? '—'} active={oursFilter === '1'}
          onClick={() => filterOurs('1')} />
        <DomainStatCard icon={<IconShieldOff size={20} />} color="gray" label="External / Unconfirmed"
          value={stats?.external ?? '—'} active={oursFilter === '0'}
          onClick={() => filterOurs('0')} />
        <DomainStatCard icon={<IconClockExclamation size={20} />} color="orange" label="Expiring ≤ 45 Days"
          value={stats?.expiring_soon ?? '—'} active={expiringOnly}
          onClick={filterExpiring} />
        <DomainStatCard icon={<IconAlertTriangle size={20} />} color="red" label="Expired"
          value={stats?.expired ?? '—'} active={statusFilter === 'expired' && !expiringOnly}
          onClick={() => filterByStatus('expired')} />
        <DomainStatCard icon={<IconHourglass size={20} />} color="cyan" label="Pending"
          value={stats?.pending ?? '—'} active={statusFilter === 'pending' && !expiringOnly}
          onClick={() => filterByStatus('pending')} />
        <DomainStatCard icon={<IconRepeat size={20} />} color="violet" label="Auto-renew On"
          value={stats?.auto_renew ?? '—'} />
      </SimpleGrid>

      {/* Registrar (TZNIC) prepaid credit — real money the registry draws for register/renew */}
      {registrarCredit && (
        <Paper withBorder radius="md" p="sm">
          <Group justify="space-between" mb={8} wrap="wrap">
            <Group gap="xs">
              <IconWallet size={18} />
              <Text fw={600} size="sm">Registrar Credit — TZNIC (REG-MOINFOTECH)</Text>
              {!registrarCredit.ok && <Badge size="xs" color="red" variant="light">unreachable</Badge>}
            </Group>
            <Group gap="xs">
              <Text size="sm" c="dimmed">Total funded:</Text>
              <Text fw={700}>{registrarCredit.total.toLocaleString()} TZS</Text>
              {can('domains.settings') && registrarCredit.funded_count > 0 && (
                <Button size="compact-xs" variant="light" leftSection={<IconArrowsLeftRight size={13} />}
                  onClick={() => setTransferOpen(true)}>Request Transfer</Button>
              )}
            </Group>
          </Group>
          {registrarCredit.low.length > 0 && (
            <Alert color="orange" variant="light" p="xs" mb={8}>
              Low balance — top up soon: {registrarCredit.low.join(', ')} (renewals draw real prepaid credit)
            </Alert>
          )}
          <SimpleGrid cols={{ base: 2, sm: 3, md: 6 }} spacing="xs">
            {registrarCredit.zones.filter((z) => z.credit > 0).map((z) => {
              const low = registrarCredit.low.includes(z.zone);
              return (
                <Paper key={z.zone} withBorder p={8} radius="sm"
                  style={{ borderColor: low ? 'var(--mantine-color-orange-5)' : undefined }}>
                  <Text size="xs" c="dimmed">.{z.zone}</Text>
                  <Text size="sm" fw={700} c={low ? 'orange' : undefined}>
                    {z.credit.toLocaleString()}
                  </Text>
                </Paper>
              );
            })}
            {registrarCredit.funded_count === 0 && (
              <Text size="sm" c="dimmed">No funded zones.</Text>
            )}
          </SimpleGrid>

          {/* Pending transfer requests — TZNIC must action these; balance updates after */}
          {(registrarCredit.pending_transfers?.length ?? 0) > 0 && (
            <Stack gap={4} mt={8}>
              <Text size="xs" fw={700} c="dimmed" tt="uppercase">Pending transfer requests</Text>
              {registrarCredit.pending_transfers.map((tf) => (
                <Group key={tf.id} justify="space-between" gap="xs"
                  style={{ background: 'var(--mantine-color-yellow-0)', padding: '4px 8px', borderRadius: 6 }}>
                  <Text size="xs">
                    .{tf.from_zone} → .{tf.to_zone} · {tf.amount.toLocaleString()} TZS
                    {tf.requested_by ? ` · ${tf.requested_by}` : ''}
                    <Text span c="dimmed"> (awaiting TZNIC)</Text>
                  </Text>
                  {can('domains.settings') && (
                    <Group gap={4}>
                      <Button size="compact-xs" variant="light" color="green"
                        loading={completingId === tf.id}
                        onClick={() => completeTransfer(tf.id)}>Mark Done</Button>
                      <Button size="compact-xs" variant="subtle" color="gray"
                        onClick={() => cancelTransfer(tf.id)}>Cancel</Button>
                    </Group>
                  )}
                </Group>
              ))}
            </Stack>
          )}

          {registrarCredit.checked_at && (
            <Text size="xs" c="dimmed" mt={6}>
              As of {new Date(registrarCredit.checked_at).toLocaleString('en-GB')} · cached 5 min
            </Text>
          )}
        </Paper>
      )}

      <TransferRequestModal opened={transferOpen} onClose={() => setTransferOpen(false)}
        credit={registrarCredit}
        onDone={() => qc.invalidateQueries({ queryKey: ['registrar-credit'] })} />

      <Group gap="xs">
        <TextInput size="xs" placeholder="Search domain…" leftSection={<IconSearch size={13} />}
          value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} w={220} />
        <Select size="xs" placeholder="All statuses" clearable w={160}
          value={statusFilter} onChange={(v) => { setStatusFilter(v ?? ''); setExpiringOnly(false); setPage(1); }}
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
                  const sponsor = d.meta?.sponsoring_registrar as string | undefined;
                  const isOurs = !!sponsor && sponsor === stats?.our_registrar;
                  return (
                    <Table.Tr key={d.id}>
                      <Table.Td fw={500}>
                        <Group gap={6} wrap="nowrap">
                          <Anchor size="sm" fw={600} onClick={() => navigate(`/domains/${d.id}`)}>{d.name}</Anchor>
                          {isOurs && (
                            <Tooltip label={`Registry-confirmed on ${sponsor}`}>
                              <IconShieldCheck size={15} color="var(--mantine-color-teal-6)" />
                            </Tooltip>
                          )}
                          {sponsor && !isOurs && (
                            <Tooltip label="Sponsored by another registrar at the registry">
                              <Badge size="xs" color="gray" variant="light">{sponsor}</Badge>
                            </Tooltip>
                          )}
                        </Group>
                      </Table.Td>
                      <Table.Td><Text size="sm">{d.client?.name ?? '—'}</Text></Table.Td>
                      <Table.Td><Text size="sm" c="dimmed">{d.registered_at ?? '—'}</Text></Table.Td>
                      <Table.Td>
                        <Text size="sm" c={expiringSoon ? 'red' : undefined} fw={expiringSoon ? 600 : undefined}>
                          {d.expires_at ?? '—'}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        {can('domains.renew') && !d.meta?.unmanaged && ['active', 'expired'].includes(d.status) ? (
                          <Tooltip label="When ON, renewals are invoiced and paid from the client's wallet balance automatically">
                            <Switch size="xs" checked={d.auto_renew}
                              disabled={togglingId === d.id}
                              onChange={(e) => toggleAutoRenew(d, e.currentTarget.checked)} />
                          </Tooltip>
                        ) : d.auto_renew
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
        title={<Text fw={700}>{logsFor?.name ?? ''}</Text>} position="right" size="md">
        {logsFor && (
          <Stack gap="md">
            <Paper withBorder p="sm" radius="md">
              <Stack gap={6}>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Client</Text>
                  <Text size="sm" fw={500}>{logsFor.client?.name ?? '—'}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Status</Text>
                  <Badge size="sm" color={DOMAIN_STATUS_COLORS[logsFor.status]} variant="light">{logsFor.status}</Badge>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Registered</Text>
                  <Text size="sm">{logsFor.registered_at ? dayjs(logsFor.registered_at).format('D MMM YYYY') : '—'}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Expires</Text>
                  <Text size="sm">{logsFor.expires_at ? dayjs(logsFor.expires_at).format('D MMM YYYY') : '—'}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Auto-renew</Text>
                  <Text size="sm">{logsFor.auto_renew ? 'On (wallet-funded)' : 'Off'}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Sponsoring registrar</Text>
                  <Text size="sm">{logsFor.meta?.sponsoring_registrar ?? (logsFor.meta?.unmanaged ? 'unmanaged gTLD' : 'unconfirmed')}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">SSL</Text>
                  <Text size="sm">
                    {logsFor.meta?.ssl_valid
                      ? `Valid${logsFor.meta?.ssl_issuer ? ` (${logsFor.meta.ssl_issuer})` : ''} until ${logsFor.meta?.ssl_expires_at ?? '?'}`
                      : 'None detected'}
                  </Text>
                </Group>
                {logsFor.meta?.last_synced_at && (
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">Last registry sync</Text>
                    <Text size="sm">{dayjs(logsFor.meta.last_synced_at).format('D MMM YYYY HH:mm')}</Text>
                  </Group>
                )}
              </Stack>
            </Paper>
            <Text size="sm" fw={700}>Activity</Text>
            <DomainLogsList domainId={logsFor.id} />
          </Stack>
        )}
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
              <Text size="sm">{describeDomainAction(l.action)}</Text>
            </Group>
            <Text size="xs" c="dimmed">{dayjs(l.created_at).format('D MMM YYYY HH:mm')}</Text>
          </Group>
          {l.error && <Text size="xs" c="red" mt={4}>{l.error}</Text>}
        </Paper>
      ))}
    </Stack>
  );
}


function TransferRequestModal({ opened, onClose, credit, onDone }: {
  opened: boolean; onClose: () => void; credit: RegistrarCredit | undefined; onDone: () => void;
}) {
  const [fromZone, setFromZone] = useState<string | null>(null);
  const [toZone, setToZone] = useState<string | null>(null);
  const [amount, setAmount] = useState<number | ''>('');
  const [notes, setNotes] = useState('');
  const [email, setEmail] = useState<TransferEmail | null>(null);

  const funded = (credit?.zones ?? []).filter((z) => z.credit > 0);
  const fromBalance = funded.find((z) => z.zone === fromZone)?.credit ?? 0;
  const allZones = (credit?.zones ?? []).map((z) => z.zone);

  const mutation = useMutation({
    mutationFn: () => createCreditTransfer({ from_zone: fromZone!, to_zone: toZone!, amount: Number(amount), notes: notes || undefined }),
    onSuccess: (res) => {
      setEmail(res.data.email);
      notifications.show({ message: res.data.message, color: 'green', autoClose: 9000 });
      onDone();
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not create request.', color: 'red' }),
  });

  const reset = () => { setFromZone(null); setToZone(null); setAmount(''); setNotes(''); setEmail(null); };
  const close = () => { reset(); onClose(); };

  const canSubmit = fromZone && toZone && fromZone !== toZone && Number(amount) > 0 && Number(amount) <= fromBalance;

  return (
    <Modal opened={opened} onClose={close} title="Request Zone Credit Transfer" centered>
      {email ? (
        <Stack gap="sm">
          <Alert color="blue" variant="light">
            Request logged as <b>pending</b>. TZNIC has no API for zone transfers — send them this email; the
            balance updates after they process it, then click "Mark Done".
          </Alert>
          <Text size="sm" fw={600}>To: {email.to}</Text>
          <Text size="sm" fw={600}>Subject: {email.subject}</Text>
          <Paper withBorder p="xs" radius="sm" style={{ whiteSpace: 'pre-wrap', fontSize: 13 }}>{email.body}</Paper>
          <Group justify="flex-end">
            <CopyButton value={`${email.subject}\n\n${email.body}`}>
              {({ copied, copy }) => (
                <Button size="xs" variant="light" color={copied ? 'green' : 'blue'}
                  leftSection={<IconCopy size={13} />} onClick={copy}>{copied ? 'Copied' : 'Copy email'}</Button>
              )}
            </CopyButton>
            <Button size="xs" component="a"
              href={`mailto:${email.to}?subject=${encodeURIComponent(email.subject)}&body=${encodeURIComponent(email.body)}`}>
              Open in mail
            </Button>
            <Button size="xs" variant="default" onClick={close}>Done</Button>
          </Group>
        </Stack>
      ) : (
        <Stack gap="sm">
          <Text size="xs" c="dimmed">
            Moving credit between zones is a TZNIC-side action. This logs the request and generates the email to send them.
          </Text>
          <Group grow>
            <Select label="From zone" placeholder="funded zone" data={funded.map((z) => ({ value: z.zone, label: `.${z.zone} (${z.credit.toLocaleString()})` }))}
              value={fromZone} onChange={setFromZone} searchable />
            <Select label="To zone" placeholder="zone" data={allZones.filter((z) => z !== fromZone).map((z) => ({ value: z, label: `.${z}` }))}
              value={toZone} onChange={setToZone} searchable />
          </Group>
          <NumberInput label="Amount (TZS)" min={1} max={fromBalance || undefined} value={amount}
            onChange={(v) => setAmount(v === '' ? '' : Number(v))}
            description={fromZone ? `Available in .${fromZone}: ${fromBalance.toLocaleString()}` : undefined}
            thousandSeparator="," />
          <TextInput label="Notes (optional)" value={notes} onChange={(e) => setNotes(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={close}>Cancel</Button>
            <Button disabled={!canSubmit} loading={mutation.isPending} onClick={() => mutation.mutate()}>
              Create Request
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}

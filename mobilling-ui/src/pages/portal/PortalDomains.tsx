import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Table, Badge, LoadingOverlay, Button, Group, Text,
  SimpleGrid, Modal, TextInput, NumberInput, Alert, Tooltip, Menu, Switch,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  IconWorldWww, IconRefresh, IconPlus, IconArrowRight, IconLock, IconLockOpen,
  IconCheck, IconX, IconChevronDown,
} from '@tabler/icons-react';
import {
  getPortalDomains, portalRenewDomain, portalCheckDomain, portalOrderDomain,
  portalSetAutoRenew, PortalDomain,
} from '../../api/portal';
import { useAuth } from '../../context/AuthContext';

const fmtDate = (d: string | null) =>
  d ? new Date(d).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '—';
const fmt = (n: number) => n.toLocaleString();

const statusColor: Record<string, string> = {
  active: 'green', expired: 'red', pending: 'blue', failed: 'red',
};

export default function PortalDomains() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { user } = useAuth();
  const isPortalAdmin = (user as any)?.role === 'admin';
  const [searchParams, setSearchParams] = useSearchParams();
  const [renewFor, setRenewFor] = useState<PortalDomain | null>(null);
  const [orderAction, setOrderAction] = useState<'register' | 'transfer' | null>(null);
  const [prefillName, setPrefillName] = useState('');
  const [togglingId, setTogglingId] = useState<string | null>(null);

  const toggleAutoRenew = async (d: PortalDomain, enabled: boolean) => {
    setTogglingId(d.id);
    try {
      const res = await portalSetAutoRenew(d.id, enabled);
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
      notifications.show({
        title: enabled ? 'Auto-renew enabled' : 'Auto-renew disabled',
        message: res.data.message,
        color: enabled ? 'teal' : 'gray',
        autoClose: 9000,
      });
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not change auto-renew.', color: 'red' });
    } finally {
      setTogglingId(null);
    }
  };

  // Deep link from the dashboard: /portal/domains?order=register&name=example.co.tz
  useEffect(() => {
    const order = searchParams.get('order');
    if (order === 'register' || order === 'transfer') {
      setPrefillName(searchParams.get('name') ?? '');
      setOrderAction(order);
      setSearchParams({}, { replace: true });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const { data, isLoading } = useQuery({ queryKey: ['portal-domains'], queryFn: getPortalDomains });
  const domains: PortalDomain[] = data?.data?.data ?? [];
  const stats = data?.data?.stats;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />

      <Group justify="space-between" align="center">
        <Group gap="xs">
          <IconWorldWww size={22} />
          <Title order={3}>My Domains</Title>
        </Group>
        <Menu shadow="md">
          <Menu.Target>
            <Button rightSection={<IconChevronDown size={14} />}>Actions</Button>
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Item leftSection={<IconPlus size={14} />} onClick={() => setOrderAction('register')}>
              Register a New Domain
            </Menu.Item>
            <Menu.Item leftSection={<IconArrowRight size={14} />} onClick={() => setOrderAction('transfer')}>
              Transfer in a Domain
            </Menu.Item>
          </Menu.Dropdown>
        </Menu>
      </Group>

      {stats && (
        <SimpleGrid cols={{ base: 3 }}>
          <Paper withBorder p="md" ta="center">
            <Text size="xl" fw={800} c="green">{stats.active}</Text>
            <Text size="sm" c="dimmed">Active</Text>
          </Paper>
          <Paper withBorder p="md" ta="center">
            <Text size="xl" fw={800} c="red">{stats.expired}</Text>
            <Text size="sm" c="dimmed">Expired</Text>
          </Paper>
          <Paper withBorder p="md" ta="center">
            <Text size="xl" fw={800} c="orange">{stats.expiring_soon}</Text>
            <Text size="sm" c="dimmed">Expiring Soon</Text>
          </Paper>
        </SimpleGrid>
      )}

      {(stats?.expiring_soon ?? 0) > 0 && (
        <Alert color="orange" variant="light">
          You have {stats!.expiring_soon} domain(s) expiring within 45 days — renew them to avoid losing your website and email.
        </Alert>
      )}

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={720}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Domain</Table.Th>
                <Table.Th>Registration Date</Table.Th>
                <Table.Th>Next Due Date</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th ta="center">Action</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {domains.length === 0 && (
                <Table.Tr><Table.Td colSpan={5}><Text c="dimmed" ta="center" py="md" size="sm">No domains yet.</Text></Table.Td></Table.Tr>
              )}
              {domains.map((d) => (
                <Table.Tr key={d.id}>
                  <Table.Td>
                    <Group gap={6} wrap="nowrap">
                      {d.ssl_valid !== null && (
                        <Tooltip label={d.ssl_valid
                          ? `Valid SSL detected — expires ${fmtDate(d.ssl_expires_at)}`
                          : 'No valid SSL certificate detected'}>
                          {d.ssl_valid
                            ? <IconLock size={15} color="var(--mantine-color-green-6)" />
                            : <IconLockOpen size={15} color="var(--mantine-color-gray-5)" />}
                        </Tooltip>
                      )}
                      <div>
                        <Text size="sm" fw={600}>{d.name}</Text>
                        <Group gap={6}>
                          {isPortalAdmin && !d.unmanaged && ['active', 'expired'].includes(d.status) ? (
                            <Tooltip multiline w={260}
                              label="When ON, we renew this domain automatically before it expires and charge your account credit — keep enough balance in your wallet.">
                              <Switch size="xs" label="Auto Renew" checked={d.auto_renew}
                                disabled={togglingId === d.id}
                                onChange={(e) => toggleAutoRenew(d, e.currentTarget.checked)}
                                styles={{ label: { fontSize: 11, color: 'var(--mantine-color-dimmed)' } }} />
                            </Tooltip>
                          ) : (
                            <Badge size="xs" variant="light" color={d.auto_renew ? 'teal' : 'gray'}
                              leftSection={d.auto_renew ? <IconCheck size={9} /> : <IconX size={9} />}>
                              Auto Renew
                            </Badge>
                          )}
                          {d.ssl_valid && (
                            <Text size="xs" c="dimmed">SSL until {new Date(d.ssl_expires_at!).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</Text>
                          )}
                        </Group>
                      </div>
                    </Group>
                  </Table.Td>
                  <Table.Td><Text size="sm">{fmtDate(d.registered_at)}</Text></Table.Td>
                  <Table.Td>
                    <Text size="sm" c={d.expiring_soon || d.status === 'expired' ? 'red' : undefined}
                      fw={d.expiring_soon ? 600 : undefined}>
                      {fmtDate(d.expires_at)}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge size="sm" color={statusColor[d.status] ?? 'gray'} variant="light">{d.status}</Badge>
                  </Table.Td>
                  <Table.Td ta="center">
                    {!d.unmanaged && ['active', 'expired'].includes(d.status) && (
                      <Button size="xs" variant="light" color={d.expiring_soon || d.status === 'expired' ? 'orange' : 'blue'}
                        leftSection={<IconRefresh size={13} />}
                        onClick={() => setRenewFor(d)}>
                        Renew
                      </Button>
                    )}
                    {d.unmanaged && <Text size="xs" c="dimmed">contact us to renew</Text>}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>

      <RenewModal domain={renewFor} onClose={() => setRenewFor(null)}
        onDone={() => navigate('/portal/invoices')} />
      <OrderModal action={orderAction} prefillName={prefillName} onClose={() => { setOrderAction(null); setPrefillName(''); }}
        onDone={() => navigate('/portal/invoices')} />
    </Stack>
  );
}

function RenewModal({ domain, onClose, onDone }: {
  domain: PortalDomain | null; onClose: () => void; onDone: () => void;
}) {
  const qc = useQueryClient();
  const [years, setYears] = useState(1);

  const mutation = useMutation({
    mutationFn: () => portalRenewDomain(domain!.id, years),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
      notifications.show({ title: 'Renewal invoice created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      onClose();
      onDone();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Renewal failed — please contact us.', color: 'red',
    }),
  });

  return (
    <Modal opened={!!domain} onClose={onClose} title={`Renew ${domain?.name}`} centered>
      <Stack>
        <NumberInput label="Years" min={1} max={10} value={years} onChange={(v) => setYears(Number(v) || 1)} />
        <Text size="xs" c="dimmed">
          An invoice is created now — your domain renews automatically the moment it is paid.
        </Text>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="green" loading={mutation.isPending} onClick={() => mutation.mutate()}>
            Create Invoice & Pay
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function OrderModal({ action, prefillName = '', onClose, onDone }: {
  action: 'register' | 'transfer' | null; prefillName?: string; onClose: () => void; onDone: () => void;
}) {
  const qc = useQueryClient();
  const [name, setName] = useState('');

  useEffect(() => {
    if (action && prefillName) setName(prefillName);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [action, prefillName]);
  const [years, setYears] = useState(1);
  const [authInfo, setAuthInfo] = useState('');
  const [checked, setChecked] = useState<any>(null);
  const [checking, setChecking] = useState(false);

  const doCheck = async () => {
    if (!name.trim()) return;
    setChecking(true);
    setChecked(null);
    try {
      const res = await portalCheckDomain(name.trim().toLowerCase());
      setChecked(res.data);
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Check failed.', color: 'red' });
    } finally {
      setChecking(false);
    }
  };

  const mutation = useMutation({
    mutationFn: () => portalOrderDomain({
      name: name.trim().toLowerCase(), years,
      action: action!, auth_info: action === 'transfer' ? authInfo : undefined,
    }),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
      notifications.show({ title: 'Order created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      handleClose();
      onDone();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Order failed.', color: 'red',
    }),
  });

  const handleClose = () => {
    setName(''); setYears(1); setAuthInfo(''); setChecked(null);
    onClose();
  };

  const unit = action === 'register' ? checked?.pricing?.register_price : checked?.pricing?.transfer_price;
  const canSubmit = checked && checked.pricing
    && (action === 'register' ? checked.available : authInfo.trim().length > 0);

  return (
    <Modal opened={!!action} onClose={handleClose} centered size="md"
      title={action === 'register' ? 'Register a New Domain' : 'Transfer in a Domain'}>
      <Stack gap="sm">
        <Group align="flex-end" gap="xs">
          <TextInput label="Domain name" placeholder="example.co.tz" style={{ flex: 1 }}
            value={name} onChange={(e) => { setName(e.currentTarget.value); setChecked(null); }} />
          <Button variant="light" loading={checking} onClick={doCheck} disabled={!name.trim()}>Check</Button>
        </Group>

        {checked && (
          <Alert color={action === 'register' ? (checked.available ? 'green' : 'red') : 'blue'} variant="light">
            {action === 'register'
              ? (checked.available ? `${checked.name} is available!` : `${checked.name} is not available.`)
              : (checked.available ? `${checked.name} is not registered — nothing to transfer.` : `${checked.name} can be transferred with its transfer code.`)}
            {checked.pricing === null && <Text size="xs" mt={4}>This extension is not available — please contact us.</Text>}
          </Alert>
        )}

        <Group grow>
          <NumberInput label="Years" min={checked?.pricing?.years_min ?? 1} max={checked?.pricing?.years_max ?? 10}
            value={years} onChange={(v) => setYears(Number(v) || 1)} />
          {action === 'transfer' && (
            <TextInput label="Transfer code (auth-info)" required
              value={authInfo} onChange={(e) => setAuthInfo(e.currentTarget.value)} />
          )}
        </Group>

        {checked?.pricing && unit !== undefined && (
          <Paper withBorder p="sm">
            <Group justify="space-between">
              <Text size="sm">{years} year(s) × {fmt(unit)}</Text>
              <Text fw={700}>TZS {fmt(unit * years)}</Text>
            </Group>
            <Text size="xs" c="dimmed" mt={4}>Pay the invoice and your domain is {action === 'register' ? 'registered' : 'transferred'} automatically.</Text>
          </Paper>
        )}

        <Group justify="flex-end">
          <Button variant="default" onClick={handleClose}>Cancel</Button>
          <Button disabled={!canSubmit} loading={mutation.isPending} onClick={() => mutation.mutate()}>
            Create Order & Invoice
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Button, Select, Table, Badge, Grid, TextInput,
  NumberInput, PasswordInput, SegmentedControl, Menu,
  Tooltip, Loader, Center, Box, Modal,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  IconLock, IconLockOpen, IconExternalLink, IconChevronDown,
  IconFileInvoice, IconArrowsUpDown, IconUserShare, IconTrash,
  IconRefresh, IconDeviceFloppy,
} from '@tabler/icons-react';
import { getClients } from '../api/clients';
import {
  getClientServices, getServiceDetail, updateService, changeHostingPassword,
  refreshHostingUsage, provisionSubscription, suspendHosting, unsuspendHosting,
  terminateHosting, changeHostingPackage, getHostingSso, getServerPackages,
  getUpgradeOptions, applyUpgrade,
  ServiceListItem, ServiceDetail, UpgradePlan,
} from '../api/hosting';
import { deleteClientSubscription } from '../api/clientSubscriptions';

const statusColor: Record<string, string> = {
  pending: 'blue', active: 'green', suspended: 'orange',
  terminated: 'gray', cancelled: 'gray', fraud: 'red', failed: 'red',
};

// striped label:field row, WHMCS admin look
function Row({ label, children, alt }: { label: string; children: React.ReactNode; alt?: boolean }) {
  return (
    <Group gap={0} wrap="nowrap" align="stretch"
      style={{ background: alt ? 'var(--mantine-color-gray-0)' : undefined, borderBottom: '1px solid var(--mantine-color-gray-2)' }}>
      <Box p={8} w={170} style={{ flexShrink: 0, fontSize: 13, fontWeight: 600, background: 'var(--mantine-color-gray-1)', borderRight: '1px solid var(--mantine-color-gray-2)' }}>
        {label}
      </Box>
      <Box p={6} style={{ flex: 1 }}>{children}</Box>
    </Group>
  );
}

export default function ServiceManagement() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  const [clientId, setClientId] = useState<string | null>(searchParams.get('client'));
  const [clientSearch, setClientSearch] = useState('');
  const [subId, setSubId] = useState<string | null>(searchParams.get('service'));
  const [selectPick, setSelectPick] = useState<string | null>(searchParams.get('service'));

  // ── client selector ──
  const { data: clientsData } = useQuery({
    queryKey: ['svc-clients', clientSearch],
    queryFn: () => getClients({ search: clientSearch || undefined, per_page: 50 }),
  });
  const clientOptions = (clientsData?.data?.data ?? []).map((c: any) => ({
    value: c.id,
    label: `${c.name}${c.email ? ` (${c.email})` : ''}`,
  }));

  // ── this client's services ──
  const { data: servicesData, isLoading: loadingServices } = useQuery({
    queryKey: ['client-services', clientId],
    queryFn: () => getClientServices(clientId!),
    enabled: !!clientId,
  });
  const services: ServiceListItem[] = servicesData?.data?.data ?? [];
  const serviceOptions = services.map((s) => ({
    value: s.id, label: `${s.product_name} - ${s.domain ?? '—'} (${s.status})`,
  }));

  // auto-select first service when a client is picked
  useEffect(() => {
    if (clientId && services.length && !services.find((s) => s.id === subId)) {
      setSelectPick(services[0].id);
      setSubId(services[0].id);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clientId, servicesData]);

  useEffect(() => {
    const p: Record<string, string> = {};
    if (clientId) p.client = clientId;
    if (subId) p.service = subId;
    setSearchParams(p, { replace: true });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clientId, subId]);

  return (
    <Stack gap="md">
      <Title order={3}>Client Profile — Products / Services</Title>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Client"
          placeholder="Search a client by name or email…"
          searchable
          data={clientOptions}
          value={clientId}
          searchValue={clientSearch}
          onSearchChange={setClientSearch}
          onChange={(v) => { setClientId(v); setSubId(null); setSelectPick(null); }}
          nothingFoundMessage="No clients"
          size="sm"
        />
      </Paper>

      {!clientId ? (
        <Paper withBorder p="xl" radius="sm"><Text c="dimmed" ta="center">Select a client to manage their services.</Text></Paper>
      ) : loadingServices ? (
        <Center py="xl"><Loader /></Center>
      ) : services.length === 0 ? (
        <Paper withBorder p="xl" radius="sm"><Text c="dimmed" ta="center">This client has no services.</Text></Paper>
      ) : (
        <>
          <Paper withBorder p="sm" radius="sm">
            <Group align="flex-end" gap="xs" wrap="wrap">
              <Select style={{ flex: 1, minWidth: 280 }} size="sm" label="Service"
                data={serviceOptions} value={selectPick} onChange={setSelectPick} searchable />
              <Button size="sm" variant="default" onClick={() => selectPick && setSubId(selectPick)}>Go</Button>
            </Group>
          </Paper>

          {subId && <ServiceEditor key={subId} subId={subId} onDeleted={() => { setSubId(null); qc.invalidateQueries({ queryKey: ['client-services', clientId] }); }} navigate={navigate} />}
        </>
      )}
    </Stack>
  );
}

function ServiceEditor({ subId, onDeleted, navigate }: { subId: string; onDeleted: () => void; navigate: (p: string) => void }) {
  const qc = useQueryClient();
  const [form, setForm] = useState<Partial<ServiceDetail>>({});
  const [recalc, setRecalc] = useState('no');
  const [busy, setBusy] = useState<string | null>(null);
  const [pwModal, setPwModal] = useState(false);
  const [upgradeOpen, setUpgradeOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['service-detail', subId],
    queryFn: () => getServiceDetail(subId),
  });
  const d = data?.data?.data;

  useEffect(() => { if (d) setForm(d); }, [d]);

  // live WHM packages for this service's server
  const { data: pkgData, isLoading: pkgLoading } = useQuery({
    queryKey: ['server-packages', form.server_id],
    queryFn: () => getServerPackages(form.server_id!),
    enabled: !!form.server_id,
  });
  const pkgList: string[] = pkgData?.data?.data ?? [];
  const pkgOptions = Array.from(new Set([...(form.package ? [form.package] : []), ...pkgList]))
    .map((p) => ({ value: p, label: p }));

  const set = <K extends keyof ServiceDetail>(k: K, v: ServiceDetail[K]) => setForm((f) => ({ ...f, [k]: v }));

  const saveMutation = useMutation({
    mutationFn: () => updateService(subId, {
      product_service_id: form.product_service_id,
      status: form.status,
      domain: form.domain,
      dedicated_ip: form.dedicated_ip,
      username: form.username,
      package: form.package,
      server_id: form.server_id,
      start_date: form.start_date,
      quantity: form.quantity ?? 1,
      first_payment_amount: form.first_payment_amount,
      recurring_amount: form.recurring_amount,
      next_due_date: form.next_due_date,
      termination_date: form.termination_date,
      payment_method: form.payment_method,
      promo_code: form.promo_code,
      recalculate: recalc === 'yes',
    }),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['service-detail', subId] });
      qc.invalidateQueries({ queryKey: ['client-services'] });
      setForm(res.data.data);
      setRecalc('no');
      notifications.show({ message: 'Service saved.', color: 'green' });
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Save failed.', color: 'red' }),
  });

  const ha = d?.hosting_account;

  // ── module commands ──
  const runModule = async (label: string, fn: () => Promise<any>, confirm = false) => {
    const go = async () => {
      setBusy(label);
      try {
        const res = await fn();
        notifications.show({ title: label, message: res?.data?.message ?? `${label} started.`, color: 'blue' });
        qc.invalidateQueries({ queryKey: ['service-detail', subId] });
      } catch (e: any) {
        notifications.show({ title: label, message: e?.response?.data?.message ?? `${label} failed.`, color: 'red' });
      } finally { setBusy(null); }
    };
    if (confirm) {
      modals.openConfirmModal({
        title: label, children: <Text size="sm">Run "{label}" on this account at the server?</Text>,
        labels: { confirm: label, cancel: 'Cancel' },
        confirmProps: { color: label === 'Terminate' ? 'red' : 'blue' }, onConfirm: go,
      });
    } else go();
  };

  const openCpanel = async () => {
    if (!ha) return;
    setBusy('sso');
    try {
      const res = await getHostingSso(ha.id);
      window.open(res.data.url, '_blank', 'noopener');
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not open cPanel.', color: 'red' });
    } finally { setBusy(null); }
  };

  const refreshUsage = async () => {
    if (!ha) return;
    setBusy('usage');
    try {
      await refreshHostingUsage(ha.id);
      qc.invalidateQueries({ queryKey: ['service-detail', subId] });
      notifications.show({ message: 'Usage refreshed from server.', color: 'green' });
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Usage refresh failed.', color: 'red' });
    } finally { setBusy(null); }
  };

  if (isLoading || !d) return <Center py="xl"><Loader /></Center>;

  const productOpts = d.options.products.map((p) => ({ value: p.id, label: p.name }));
  const serverOpts = d.options.servers.map((s) => ({ value: s.id, label: s.label }));

  return (
    <Paper withBorder radius="sm">
      {/* action bar */}
      <Group justify="space-between" p="sm" wrap="wrap" style={{ borderBottom: '1px solid var(--mantine-color-gray-2)' }}>
        <Group gap="xs">
          <Text fw={600} size="sm">{d.domain ?? d.client.name}</Text>
          <Badge size="sm" color={statusColor[d.status] ?? 'gray'} variant="light">{d.status}</Badge>
          {d.ssl.valid !== null && (
            <Tooltip label={d.ssl.valid ? `Valid SSL${d.ssl.issuer ? ` — ${d.ssl.issuer}` : ''}` : 'No SSL detected'}>
              {d.ssl.valid ? <IconLock size={16} color="var(--mantine-color-green-6)" /> : <IconLockOpen size={16} color="var(--mantine-color-gray-5)" />}
            </Tooltip>
          )}
        </Group>
        <Group gap="xs">
          {ha && ha.status === 'active' && !ha.not_on_whm && (
            <Button size="xs" color="blue" leftSection={<IconExternalLink size={14} />}
              loading={busy === 'sso'} onClick={openCpanel}>
              Log in to cPanel
            </Button>
          )}
          <Menu shadow="md" width={220}>
            <Menu.Target>
              <Button size="xs" variant="default" rightSection={<IconChevronDown size={13} />}>More</Button>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Item leftSection={<IconFileInvoice size={14} />}
                onClick={() => navigate(d.order_document_id ? `/invoices/${d.order_document_id}` : '/invoices')}>
                View Invoices
              </Menu.Item>
              <Menu.Item leftSection={<IconArrowsUpDown size={14} />} onClick={() => setUpgradeOpen(true)}>
                Upgrade / Downgrade
              </Menu.Item>
              <Menu.Item leftSection={<IconUserShare size={14} />} onClick={() => navigate(`/clients/${d.client.id}`)}>
                Client Profile
              </Menu.Item>
              <Menu.Divider />
              <Menu.Item leftSection={<IconTrash size={14} />} color="red"
                onClick={() => modals.openConfirmModal({
                  title: 'Delete Service', children: <Text size="sm">Delete this service record? This does not touch the server — terminate first if needed.</Text>,
                  labels: { confirm: 'Delete', cancel: 'Cancel' }, confirmProps: { color: 'red' },
                  onConfirm: async () => {
                    try { await deleteClientSubscription(subId); onDeleted(); notifications.show({ message: 'Service deleted.', color: 'gray' }); }
                    catch { notifications.show({ message: 'Delete failed.', color: 'red' }); }
                  },
                })}>
                Delete
              </Menu.Item>
            </Menu.Dropdown>
          </Menu>
        </Group>
      </Group>

      {/* edit form — two columns */}
      <Grid gutter={0}>
        <Grid.Col span={{ base: 12, md: 6 }} style={{ borderRight: '1px solid var(--mantine-color-gray-2)' }}>
          <Row label="Product/Service">
            <Select size="xs" data={productOpts} value={form.product_service_id}
              onChange={(v) => set('product_service_id', v as string)} searchable />
          </Row>
          <Row label="Server" alt>
            <Select size="xs" data={serverOpts} value={form.server_id} placeholder="—"
              onChange={(v) => set('server_id', v)} clearable />
          </Row>
          <Row label="Domain">
            <TextInput size="xs" value={form.domain ?? ''} onChange={(e) => set('domain', e.currentTarget.value)} />
          </Row>
          <Row label="Dedicated IP" alt>
            <TextInput size="xs" value={form.dedicated_ip ?? ''} onChange={(e) => set('dedicated_ip', e.currentTarget.value)} />
          </Row>
          <Row label="Username">
            <TextInput size="xs" value={form.username ?? ''} onChange={(e) => set('username', e.currentTarget.value)} />
          </Row>
          <Row label="cPanel Package">
            {pkgList.length > 0 ? (
              <Select size="xs" data={pkgOptions} value={form.package ?? null}
                placeholder={pkgLoading ? 'Loading…' : 'Select package'} searchable
                rightSection={pkgLoading ? <Loader size="xs" /> : undefined}
                onChange={(v) => set('package', v)} />
            ) : (
              <TextInput size="xs" value={form.package ?? ''} placeholder={pkgLoading ? 'Loading…' : 'Package name'}
                onChange={(e) => set('package', e.currentTarget.value)} />
            )}
          </Row>
          <Row label="Password" alt>
            <Group gap="xs">
              <Button size="compact-xs" variant="default" disabled={!ha} onClick={() => setPwModal(true)}>
                Change Password…
              </Button>
              {!ha && <Text size="xs" c="dimmed">no server account</Text>}
            </Group>
          </Row>
          <Row label="Status">
            <Select size="xs" data={d.options.statuses.map((s) => ({ value: s, label: s }))}
              value={form.status} onChange={(v) => set('status', v as string)} />
          </Row>
        </Grid.Col>

        <Grid.Col span={{ base: 12, md: 6 }}>
          <Row label="Registration Date">
            <TextInput size="xs" type="date" value={form.start_date ?? ''} onChange={(e) => set('start_date', e.currentTarget.value)} />
          </Row>
          <Row label="Quantity" alt>
            <NumberInput size="xs" min={1} value={form.quantity ?? 1} onChange={(v) => set('quantity', Number(v) || 1)} />
          </Row>
          <Row label="First Payment">
            <NumberInput size="xs" decimalScale={2} thousandSeparator="," value={form.first_payment_amount ?? undefined}
              onChange={(v) => set('first_payment_amount', v === '' ? null : Number(v))} />
          </Row>
          <Row label="Recurring Amount" alt>
            <Group gap="xs" wrap="nowrap">
              <NumberInput size="xs" style={{ flex: 1 }} decimalScale={2} thousandSeparator=","
                value={form.recurring_amount ?? undefined} disabled={recalc === 'yes'}
                onChange={(v) => set('recurring_amount', v === '' ? null : Number(v))} />
              <Tooltip label="Recalculate from current product price on save">
                <SegmentedControl size="xs" value={recalc} onChange={setRecalc}
                  data={[{ label: 'Keep', value: 'no' }, { label: 'Recalc', value: 'yes' }]} />
              </Tooltip>
            </Group>
          </Row>
          <Row label="Next Due Date">
            <TextInput size="xs" type="date" value={form.next_due_date ?? ''} onChange={(e) => set('next_due_date', e.currentTarget.value)} />
          </Row>
          <Row label="Termination Date" alt>
            <TextInput size="xs" type="date" value={form.termination_date ?? ''} onChange={(e) => set('termination_date', e.currentTarget.value)} />
          </Row>
          <Row label="Billing Cycle">
            <Text size="xs" c="dimmed">{form.billing_cycle ?? '—'} <Text span size="xs" c="dimmed">(from product)</Text></Text>
          </Row>
          <Row label="Payment Method" alt>
            <Select size="xs" data={d.options.payment_methods.map((m) => ({ value: m, label: m }))}
              value={form.payment_method} placeholder="—" clearable onChange={(v) => set('payment_method', v)} />
          </Row>
          <Row label="Promotion Code">
            <TextInput size="xs" placeholder="None" value={form.promo_code ?? ''} onChange={(e) => set('promo_code', e.currentTarget.value)} />
          </Row>
        </Grid.Col>
      </Grid>

      {/* module commands */}
      <Box p="sm" style={{ borderTop: '1px solid var(--mantine-color-gray-2)' }}>
        <Text size="xs" fw={700} c="dimmed" mb={6} tt="uppercase">Module Commands</Text>
        <Group gap="xs" wrap="wrap">
          <Button size="xs" variant="light" color="green" loading={busy === 'Create'} disabled={!!ha}
            onClick={() => runModule('Create', () => provisionSubscription(subId), true)}>Create</Button>
          <Button size="xs" variant="light" color="orange" loading={busy === 'Suspend'} disabled={!ha}
            onClick={() => runModule('Suspend', () => suspendHosting(ha!.id), true)}>Suspend</Button>
          <Button size="xs" variant="light" color="teal" loading={busy === 'Unsuspend'} disabled={!ha}
            onClick={() => runModule('Unsuspend', () => unsuspendHosting(ha!.id), true)}>Unsuspend</Button>
          <Button size="xs" variant="light" color="red" loading={busy === 'Terminate'} disabled={!ha}
            onClick={() => runModule('Terminate', () => terminateHosting(ha!.id), true)}>Terminate</Button>
          <Button size="xs" variant="light" loading={busy === 'Change Package'} disabled={!ha || !form.package}
            onClick={() => runModule('Change Package', () => changeHostingPackage(ha!.id, form.package!), true)}>Change Package</Button>
          <Button size="xs" variant="light" disabled={!ha} onClick={() => setPwModal(true)}>Change Password</Button>
        </Group>
      </Box>

      {/* metrics */}
      <Box p="sm" style={{ borderTop: '1px solid var(--mantine-color-gray-2)' }}>
        <Group justify="space-between" mb={6}>
          <Text size="xs" fw={700} c="dimmed" tt="uppercase">Metric Statistics</Text>
          <Button size="compact-xs" variant="subtle" leftSection={<IconRefresh size={13} />}
            disabled={!ha} loading={busy === 'usage'} onClick={refreshUsage}>Refresh usage</Button>
        </Group>
        <Table striped withTableBorder fz="xs">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Metric</Table.Th><Table.Th>Enabled</Table.Th>
              <Table.Th>Current Usage</Table.Th><Table.Th>Last Update</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {d.metrics.map((m) => (
              <Table.Tr key={m.metric}>
                <Table.Td>{m.metric}</Table.Td>
                <Table.Td>{m.enabled ? <Badge size="xs" color="green" variant="light">Yes</Badge> : '—'}</Table.Td>
                <Table.Td>{m.usage ?? '—'}</Table.Td>
                <Table.Td c="dimmed">{m.last_update ? new Date(m.last_update).toLocaleString('en-GB') : '—'}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Box>

      {/* save bar */}
      <Group justify="flex-end" p="sm" style={{ borderTop: '1px solid var(--mantine-color-gray-2)' }}>
        <Button variant="default" size="sm" onClick={() => setForm(d)}>Cancel</Button>
        <Button size="sm" leftSection={<IconDeviceFloppy size={15} />} loading={saveMutation.isPending}
          onClick={() => saveMutation.mutate()}>Save Changes</Button>
      </Group>

      <ChangePasswordModal opened={pwModal} onClose={() => setPwModal(false)} accountId={ha?.id ?? null} />
      <UpgradeModal opened={upgradeOpen} onClose={() => setUpgradeOpen(false)} subId={subId}
        navigate={navigate} onApplied={() => { qc.invalidateQueries({ queryKey: ['service-detail', subId] }); qc.invalidateQueries({ queryKey: ['client-services'] }); }} />
    </Paper>
  );
}

function UpgradeModal({ opened, onClose, subId, navigate, onApplied }: {
  opened: boolean; onClose: () => void; subId: string; navigate: (p: string) => void; onApplied: () => void;
}) {
  const [picked, setPicked] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['upgrade-options', subId],
    queryFn: () => getUpgradeOptions(subId),
    enabled: opened,
  });
  const o = data?.data?.data;
  const plan: UpgradePlan | undefined = o?.plans.find((p) => p.id === picked);

  const mutate = useMutation({
    mutationFn: (mode: 'invoice' | 'immediate') => applyUpgrade(subId, picked!, mode),
    onSuccess: (res) => {
      notifications.show({ title: 'Plan change', message: res.data.message, color: 'green', autoClose: 9000 });
      onApplied();
      onClose();
      setPicked(null);
      if (res.data.document) navigate(`/invoices/${res.data.document.id}`);
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Plan change failed.', color: 'red' }),
  });

  const money = (n: number) => `Tsh.${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`;

  return (
    <Modal opened={opened} onClose={onClose} title="Upgrade / Downgrade" centered size="lg">
      {isLoading || !o ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Stack gap="sm">
          <Group gap="xs">
            <Text size="sm">Current plan:</Text>
            <Badge variant="light">{o.current_plan.name}</Badge>
            <Text size="sm" c="dimmed">{money(o.current_plan.price)} / {o.billing_cycle} · next due {o.next_due_date ?? '—'}</Text>
          </Group>

          <Table striped withTableBorder fz="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th w={36}></Table.Th>
                <Table.Th>Plan</Table.Th>
                <Table.Th ta="right">Recurring</Table.Th>
                <Table.Th ta="center">Change</Table.Th>
                <Table.Th ta="right">Due Now / Credit</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {o.plans.filter((p) => !p.is_current).map((p) => (
                <Table.Tr key={p.id} style={{ cursor: 'pointer' }} onClick={() => setPicked(p.id)}>
                  <Table.Td>
                    <input type="radio" checked={picked === p.id} onChange={() => setPicked(p.id)} />
                  </Table.Td>
                  <Table.Td fw={500}>{p.name}</Table.Td>
                  <Table.Td ta="right">{money(p.price)}</Table.Td>
                  <Table.Td ta="center">
                    <Badge size="xs" variant="light" color={p.direction === 'upgrade' ? 'blue' : 'orange'}>
                      {p.direction}
                    </Badge>
                  </Table.Td>
                  <Table.Td ta="right" fw={600}
                    c={p.prorated_due > 0 ? 'blue' : p.prorated_credit > 0 ? 'teal' : 'green'}>
                    {p.prorated_due > 0 ? money(p.prorated_due)
                      : p.prorated_credit > 0 ? `+${money(p.prorated_credit)} credit` : 'Free'}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>

          {plan && (
            <Text size="xs" c="dimmed">
              {plan.direction === 'upgrade' && plan.prorated_due > 0
                ? `An upgrade invoice for ${money(plan.prorated_due)} (prorated for the remaining term) will be created; the package changes automatically when it is paid. Or apply now without charge.`
                : plan.prorated_credit > 0
                  ? `This downgrade switches the plan now, sets recurring to ${money(plan.price)}, and credits ${money(plan.prorated_credit)} for the unused term to the client's wallet.`
                  : `This is a ${plan.direction}. Applying switches the plan now and updates the recurring amount to ${money(plan.price)}.`}
            </Text>
          )}

          <Group justify="flex-end" mt="xs">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            {plan && plan.prorated_due > 0 && (
              <Button variant="light" color="gray" disabled={!picked} loading={mutate.isPending}
                onClick={() => mutate.mutate('immediate')}>
                Apply Now (no charge)
              </Button>
            )}
            <Button disabled={!picked} loading={mutate.isPending}
              color={plan && plan.prorated_due > 0 ? 'blue' : 'orange'}
              onClick={() => mutate.mutate(plan && plan.prorated_due > 0 ? 'invoice' : 'immediate')}>
              {plan && plan.prorated_due > 0 ? 'Create Prorated Invoice' : 'Apply Change'}
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}

function ChangePasswordModal({ opened, onClose, accountId }: { opened: boolean; onClose: () => void; accountId: string | null }) {
  const [pw, setPw] = useState('');
  const mutation = useMutation({
    mutationFn: () => changeHostingPassword(accountId!, pw),
    onSuccess: (res) => { notifications.show({ message: res.data.message, color: 'green' }); setPw(''); onClose(); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Change failed.', color: 'red' }),
  });
  return (
    <Modal opened={opened} onClose={onClose} title="Change cPanel Password" centered size="sm">
      <Stack>
        <PasswordInput label="New Password" value={pw} onChange={(e) => setPw(e.currentTarget.value)}
          description="Pushed to the server immediately (WHM passwd)." />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="orange" disabled={pw.length < 8} loading={mutation.isPending} onClick={() => mutation.mutate()}>
            Change Password
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, LoadingOverlay, Grid, Button, NavLink,
  Badge, Divider, Modal, PasswordInput, Textarea, Radio, RingProgress,
  SimpleGrid, UnstyledButton, Center, Anchor, Alert,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useParams } from 'react-router-dom';
import {
  IconStar, IconTool, IconLogin, IconMail, IconKey, IconBan, IconWorldWww,
  IconExternalLink, IconRefresh, IconArrowLeft, IconFolders, IconDatabase,
  IconClock, IconChartBar, IconArrowForward, IconServer, IconArchive,
  IconArrowUp, IconListDetails,
} from '@tabler/icons-react';
import {
  getPortalHostingDetail, portalHostingSso, refreshPortalHostingUsage,
  changePortalHostingPassword, requestPortalHostingCancellation,
  getPortalUpgradeOptions, requestPortalUpgrade, UpgradePlanRow,
} from '../../api/portal';
import { Tooltip } from '@mantine/core';
import { useAuth } from '../../context/AuthContext';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const cycleLabel: Record<string, string> = {
  once: 'One-time', monthly: 'Monthly', quarterly: 'Quarterly',
  half_yearly: 'Semi-Annually', yearly: 'Annually',
};

const statusColor: Record<string, string> = {
  active: 'green', suspended: 'orange', pending: 'blue', failed: 'red', terminated: 'gray',
};

const SHORTCUTS: { key: string; label: string; icon: React.ReactNode }[] = [
  { key: 'email',      label: 'Email Accounts',    icon: <IconMail size={26} /> },
  { key: 'forwarders', label: 'Forwarders',        icon: <IconArrowForward size={26} /> },
  { key: 'files',      label: 'File Manager',      icon: <IconFolders size={26} /> },
  { key: 'backup',     label: 'Backup',            icon: <IconArchive size={26} /> },
  { key: 'domains',    label: 'Domains',           icon: <IconWorldWww size={26} /> },
  { key: 'cron',       label: 'Cron Jobs',         icon: <IconClock size={26} /> },
  { key: 'mysql',      label: 'MySQL® Databases',  icon: <IconDatabase size={26} /> },
  { key: 'phpmyadmin', label: 'phpMyAdmin',        icon: <IconServer size={26} /> },
  { key: 'stats',      label: 'Awstats',           icon: <IconChartBar size={26} /> },
];

export default function PortalServiceDetails() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const qc = useQueryClient();
  const isPortalAdmin = (user as any)?.role === 'admin';

  const [pwOpen, setPwOpen] = useState(false);
  const [upgradeOpen, setUpgradeOpen] = useState(false);
  const [cancelOpen, setCancelOpen] = useState(false);
  const [ssoBusy, setSsoBusy] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-hosting-detail', id],
    queryFn: () => getPortalHostingDetail(id!),
    enabled: !!id,
  });
  const d = data?.data?.data;

  const refreshMutation = useMutation({
    mutationFn: () => refreshPortalHostingUsage(id!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['portal-hosting-detail', id] });
      notifications.show({ message: 'Usage refreshed from the server.', color: 'green' });
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Refresh failed.', color: 'red',
    }),
  });

  const openSso = async (opts: { service?: 'cpanel' | 'webmail'; goto?: string }, busyKey: string) => {
    setSsoBusy(busyKey);
    try {
      const res = await portalHostingSso(id!, opts);
      window.open(res.data.url, '_blank', 'noopener');
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not open the panel.', color: 'red' });
    } finally {
      setSsoBusy(null);
    }
  };

  if (isLoading || !d) {
    return <Stack pos="relative" mih={300}><LoadingOverlay visible /></Stack>;
  }

  const diskUsed  = parseFloat(String(d.disk_used ?? '').replace(/[^\d.]/g, '')) || 0;
  const diskLimit = parseFloat(String(d.disk_limit ?? '').replace(/[^\d.]/g, '')) || 0;
  const diskPct   = diskLimit > 0 ? Math.min(100, (diskUsed / diskLimit) * 100) : 0;

  return (
    <Stack gap="lg">
      <Group gap="xs">
        <Button variant="subtle" size="xs" leftSection={<IconArrowLeft size={14} />}
          onClick={() => navigate('/portal/hosting')}>
          My Hosting
        </Button>
        <Title order={3}>Service Details</Title>
        <Badge color={statusColor[d.status] ?? 'gray'} variant="light">{d.status}</Badge>
      </Group>

      <Grid gutter="lg">
        {/* ── Sidebar ── */}
        <Grid.Col span={{ base: 12, md: 3 }}>
          <Stack gap="lg">
            <Paper withBorder radius="md" p="xs">
              <Group gap="xs" px="sm" pt="sm" pb="xs"><IconStar size={16} /><Text fw={700}>Overview</Text></Group>
              <NavLink label="Information" active variant="filled" style={{ borderRadius: 8 }} />
            </Paper>

            {isPortalAdmin && (
              <Paper withBorder radius="md" p="xs">
                <Group gap="xs" px="sm" pt="sm" pb="xs"><IconTool size={16} /><Text fw={700}>Actions</Text></Group>
                <NavLink label="Log in to cPanel" leftSection={<IconLogin size={16} />}
                  disabled={d.status !== 'active' || ssoBusy === 'cpanel'}
                  onClick={() => openSso({ service: 'cpanel' }, 'cpanel')} />
                <NavLink label="Log in to Webmail" leftSection={<IconMail size={16} />}
                  disabled={d.status !== 'active' || ssoBusy === 'webmail'}
                  onClick={() => openSso({ service: 'webmail' }, 'webmail')} />
                <NavLink label="Change Password" leftSection={<IconKey size={16} />}
                  disabled={d.status !== 'active'}
                  onClick={() => setPwOpen(true)} />
                <NavLink label="Upgrade/Downgrade" leftSection={<IconArrowUp size={16} />}
                  disabled={d.status !== 'active'}
                  onClick={() => setUpgradeOpen(true)} />
                <Tooltip label="No configurable options are available for this product" position="right">
                  <div>
                    <NavLink label="Upgrade/Downgrade Options" leftSection={<IconListDetails size={16} />} disabled />
                  </div>
                </Tooltip>
                <NavLink label="Request Cancellation" leftSection={<IconBan size={16} />} c="red"
                  onClick={() => setCancelOpen(true)} />
              </Paper>
            )}
          </Stack>
        </Grid.Col>

        {/* ── Main ── */}
        <Grid.Col span={{ base: 12, md: 5 }}>
          <Paper withBorder radius="md" p="lg">
            <Stack align="center" gap={4}>
              <Text fs="italic" c="dimmed">{d.product_group ?? 'Hosting'}</Text>
              <Title order={2} ta="center">{d.product_name ?? d.package ?? 'Hosting Service'}</Title>
              <Anchor href={`https://${d.domain}`} target="_blank" c="blue" fw={600}>
                www.{d.domain}
              </Anchor>
              <Group mt="sm">
                <Button variant="default" leftSection={<IconExternalLink size={14} />}
                  onClick={() => window.open(`https://${d.domain}`, '_blank', 'noopener')}>
                  Visit Website
                </Button>
                <Button color="green" leftSection={<IconWorldWww size={14} />}
                  onClick={() => navigate('/portal/domains')}>
                  Manage Domain
                </Button>
              </Group>
            </Stack>

            <Divider my="md" />

            <Stack gap={6}>
              <InfoRow label="Registration Date" value={d.registered_at ?? '—'} />
              <InfoRow label="Recurring Amount" value={`Tsh.${fmt(d.price)}`} />
              <InfoRow label="Billing Cycle" value={cycleLabel[d.billing_cycle ?? ''] ?? d.billing_cycle ?? '—'} />
              <InfoRow label="Next Due Date" value={d.next_due ?? '—'} />
              <InfoRow label="Username" value={d.cpanel_username} />
              <InfoRow label="Package" value={d.package ?? '—'} />
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Status</Text>
                <Badge color={statusColor[d.status] ?? 'gray'} variant="filled" radius="xl" size="sm">
                  {d.status}
                </Badge>
              </Group>
            </Stack>
          </Paper>
        </Grid.Col>

        <Grid.Col span={{ base: 12, md: 4 }}>
          <Paper withBorder radius="md" p="lg">
            <Text fw={700} mb="md">Usage Statistics</Text>
            <Center>
              <Stack align="center" gap={4}>
                <RingProgress
                  size={150} thickness={14} roundCaps
                  sections={[{ value: diskPct, color: diskPct > 90 ? 'red' : diskPct > 70 ? 'orange' : 'blue' }]}
                  label={
                    <Text ta="center" fw={700} size="sm">
                      {diskLimit > 0 ? `${Math.round(diskPct)}%` : '—'}
                    </Text>
                  }
                />
                <Text fw={600} size="sm">Disk Usage</Text>
                <Text size="xs" c="dimmed">
                  {d.disk_used ?? '0M'} / {d.disk_limit ?? 'Unlimited'}
                </Text>
              </Stack>
            </Center>
            <Divider my="md" />
            <Group justify="space-between">
              <Text size="xs" c="dimmed">
                Last updated: {d.last_synced_at ? new Date(d.last_synced_at).toLocaleString('en-GB') : 'never'}
              </Text>
              <Button size="xs" variant="light" leftSection={<IconRefresh size={12} />}
                loading={refreshMutation.isPending}
                onClick={() => refreshMutation.mutate()}>
                Refresh
              </Button>
            </Group>
          </Paper>
        </Grid.Col>
      </Grid>

      {/* Quick shortcuts */}
      {isPortalAdmin && d.status === 'active' && (
        <Paper withBorder radius="md" p="lg">
          <Text fw={700} mb="md">Quick Shortcuts</Text>
          <SimpleGrid cols={{ base: 2, sm: 3, md: 5 }} spacing="md">
            {SHORTCUTS.filter((s) => d.shortcuts.includes(s.key)).map((s) => (
              <UnstyledButton key={s.key}
                onClick={() => openSso({ service: 'cpanel', goto: s.key }, s.key)}
                style={{ opacity: ssoBusy === s.key ? 0.5 : 1 }}>
                <Stack align="center" gap={6} p="sm"
                  style={{ border: '1px solid var(--mantine-color-default-border)', borderRadius: 10 }}>
                  <Text c="blue" style={{ display: 'flex' }}>{s.icon}</Text>
                  <Text size="xs" c="blue" fw={600} ta="center">{s.label}</Text>
                </Stack>
              </UnstyledButton>
            ))}
          </SimpleGrid>
        </Paper>
      )}

      <ChangePasswordModal id={d.id} opened={pwOpen} onClose={() => setPwOpen(false)} />
      <UpgradeModal id={d.id} opened={upgradeOpen} onClose={() => setUpgradeOpen(false)}
        onInvoiced={() => navigate('/portal/invoices')} />
      <CancellationModal id={d.id} domain={d.domain} opened={cancelOpen} onClose={() => setCancelOpen(false)} />
    </Stack>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <Group justify="space-between">
      <Text size="sm" c="dimmed">{label}</Text>
      <Text size="sm" fw={600}>{value}</Text>
    </Group>
  );
}

function ChangePasswordModal({ id, opened, onClose }: { id: string; opened: boolean; onClose: () => void }) {
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');

  const mutation = useMutation({
    mutationFn: () => changePortalHostingPassword(id, password, confirm),
    onSuccess: (res: any) => {
      notifications.show({ message: res?.data?.message ?? 'Password changed.', color: 'green' });
      setPassword(''); setConfirm('');
      onClose();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Password change failed.', color: 'red',
    }),
  });

  return (
    <Modal opened={opened} onClose={onClose} title="Change cPanel Password" centered>
      <Stack gap="sm">
        <PasswordInput label="New password" description="At least 12 characters"
          value={password} onChange={(e) => setPassword(e.currentTarget.value)} />
        <PasswordInput label="Confirm new password"
          value={confirm} onChange={(e) => setConfirm(e.currentTarget.value)} />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button disabled={password.length < 12 || password !== confirm}
            loading={mutation.isPending} onClick={() => mutation.mutate()}>
            Change Password
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function CancellationModal({ id, domain, opened, onClose }: {
  id: string; domain: string; opened: boolean; onClose: () => void;
}) {
  const [reason, setReason] = useState('');
  const [when, setWhen] = useState<'immediate' | 'end_of_period'>('end_of_period');

  const mutation = useMutation({
    mutationFn: () => requestPortalHostingCancellation(id, reason.trim(), when),
    onSuccess: (res: any) => {
      notifications.show({ title: 'Request submitted', message: res?.data?.message, color: 'green', autoClose: 9000 });
      setReason('');
      onClose();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Request failed.', color: 'red',
    }),
  });

  return (
    <Modal opened={opened} onClose={onClose} title={`Request Cancellation — ${domain}`} centered>
      <Stack gap="sm">
        <Textarea label="Reason for cancellation" required minRows={3} autosize maxRows={6}
          placeholder="Tell us briefly why you want to cancel…"
          value={reason} onChange={(e) => setReason(e.currentTarget.value)} />
        <Radio.Group label="When should the service be cancelled?" value={when}
          onChange={(v) => setWhen(v as any)}>
          <Stack gap={6} mt={4}>
            <Radio value="end_of_period" label="At the end of the current billing period" />
            <Radio value="immediate" label="Immediately" />
          </Stack>
        </Radio.Group>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="red" disabled={!reason.trim()} loading={mutation.isPending}
            onClick={() => mutation.mutate()}>
            Submit Request
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function UpgradeModal({ id, opened, onClose, onInvoiced }: {
  id: string; opened: boolean; onClose: () => void; onInvoiced: () => void;
}) {
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ['portal-upgrade-options', id],
    queryFn: () => getPortalUpgradeOptions(id),
    enabled: opened,
    retry: false,
  });
  const options = data?.data?.data;
  const errMsg = (error as any)?.response?.data?.message as string | undefined;
  const plans: UpgradePlanRow[] = options?.plans ?? [];
  const chosen = plans.find((p) => p.id === selected);

  const mutation = useMutation({
    mutationFn: () => requestPortalUpgrade(id, selected!),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-hosting-detail', id] });
      qc.invalidateQueries({ queryKey: ['portal-subscriptions'] });
      notifications.show({ title: 'Plan change', message: res?.data?.message, color: 'green', autoClose: 9000 });
      setSelected(null);
      onClose();
      if (res?.data?.data?.document_id) onInvoiced();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Plan change failed.', color: 'red',
    }),
  });

  return (
    <Modal opened={opened} onClose={onClose} title="Upgrade/Downgrade" centered size="lg">
      <Stack gap="sm" pos="relative">
        <LoadingOverlay visible={isLoading} />
        {!isLoading && (error || !options) && (
          <Alert color="orange" variant="light">
            {errMsg ?? 'Upgrade/downgrade is not available for this service right now.'}
          </Alert>
        )}
        {options && (
          <Text size="sm" c="dimmed">
            Current plan: <Text span fw={600}>{options.current_plan}</Text>
            {options.next_due && <> · paid through {options.next_due}</>}
          </Text>
        )}
        {options && (
        <Radio.Group value={selected} onChange={setSelected}>
          <Stack gap="xs">
            {plans.map((p) => (
              <Paper key={p.id} withBorder p="sm" radius="md"
                style={{ opacity: p.is_current ? 0.55 : 1 }}>
                <Group justify="space-between" wrap="nowrap">
                  <Radio value={p.id} disabled={p.is_current}
                    label={<Text fw={600}>{p.name}{p.is_current ? ' (current)' : ''}</Text>} />
                  <Stack gap={0} align="flex-end">
                    <Text size="sm" fw={600}>Tsh.{fmt(p.price)}/yr</Text>
                    {!p.is_current && (
                      <Text size="xs" c={p.due_now > 0 ? 'orange' : p.credit > 0 ? 'teal' : 'green'}>
                        {p.due_now > 0
                          ? `Due today: Tsh.${fmt(p.due_now)} (prorated)`
                          : p.credit > 0
                            ? `Credit: Tsh.${fmt(p.credit)} to your wallet`
                            : 'No charge — applies immediately'}
                      </Text>
                    )}
                  </Stack>
                </Group>
              </Paper>
            ))}
          </Stack>
        </Radio.Group>
        )}
        {options && chosen && chosen.due_now === 0 && chosen.price < (plans.find((p) => p.is_current)?.price ?? 0) && (
          <Text size="xs" c="dimmed">
            {chosen.credit > 0
              ? `This downgrade applies immediately and Tsh.${fmt(chosen.credit)} for the unused term is credited to your wallet.`
              : 'Downgrades apply immediately.'}
          </Text>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>{options ? 'Cancel' : 'Close'}</Button>
          {options && (
            <Button disabled={!selected || chosen?.is_current} loading={mutation.isPending}
              onClick={() => mutation.mutate()}>
              {chosen && chosen.due_now > 0 ? `Upgrade — Pay Tsh.${fmt(chosen.due_now)}` : 'Change Plan'}
            </Button>
          )}
        </Group>
      </Stack>
    </Modal>
  );
}

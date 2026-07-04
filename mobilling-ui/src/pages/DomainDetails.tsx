import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Button, Grid, Anchor, Code,
  CopyButton, Modal, NumberInput, Center, Loader, Switch, Tooltip, Timeline,
  ActionIcon, TextInput, Alert,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useParams } from 'react-router-dom';
import {
  IconWorld, IconRefresh, IconKey, IconCopy, IconLock, IconLockOpen,
  IconShieldCheck, IconArrowLeft, IconHistory, IconServer,
} from '@tabler/icons-react';
import {
  getDomain, getDomainLogs, renewDomain, getDomainAuthInfo, setDomainAutoRenew,
  getDomainNameservers, updateDomainNameservers, describeDomainAction,
  DomainRecord, DomainLogRow, DOMAIN_STATUS_COLORS,
} from '../api/domains';
import { usePermissions } from '../hooks/usePermissions';
import dayjs from 'dayjs';

const fmtDate = (d: string | null | undefined) => (d ? dayjs(d).format('dddd, D MMMM YYYY') : '—');

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <Text size="sm" fw={700}>{label}</Text>
      <Text size="sm" mt={2} component="div">{children}</Text>
    </div>
  );
}

export default function DomainDetails() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [renewOpen, setRenewOpen] = useState(false);
  const [authCode, setAuthCode] = useState<string | null>(null);
  const [authLoading, setAuthLoading] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['domain', id],
    queryFn: () => getDomain(id!),
    enabled: !!id,
  });
  const d = data?.data?.data as (DomainRecord & { subscription?: { id: string; label: string | null; expire_date: string | null } | null }) | undefined;

  const { data: logsData } = useQuery({
    queryKey: ['domain-logs', id],
    queryFn: () => getDomainLogs(id!),
    enabled: !!id,
  });
  const logs: DomainLogRow[] = logsData?.data?.data ?? [];

  const autoRenewMutation = useMutation({
    mutationFn: (enabled: boolean) => setDomainAutoRenew(id!, enabled),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['domain', id] });
      qc.invalidateQueries({ queryKey: ['domains'] });
      qc.invalidateQueries({ queryKey: ['domain-stats'] });
      notifications.show({ message: res.data.message, color: 'teal' });
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not change auto-renew.', color: 'red' }),
  });

  const revealAuth = async () => {
    setAuthLoading(true);
    try {
      const res = await getDomainAuthInfo(id!);
      setAuthCode(res.data.auth_info ?? '');
      qc.invalidateQueries({ queryKey: ['domain-logs', id] });
    } catch {
      notifications.show({ message: 'Could not fetch the transfer code.', color: 'red' });
    } finally {
      setAuthLoading(false);
    }
  };

  if (isLoading || !d) {
    return <Center py="xl"><Loader /></Center>;
  }

  const meta = d.meta ?? {};
  const isOurs = !!meta.sponsoring_registrar && meta.sponsoring_registrar === 'REG-MOINFOTECH';

  return (
    <Stack>
      <Group justify="space-between" wrap="wrap">
        <Group gap="xs">
          <ActionIcon variant="subtle" onClick={() => navigate('/domains')}><IconArrowLeft size={18} /></ActionIcon>
          <IconWorld size={22} />
          <Title order={3}>{d.name}</Title>
          <Badge color={DOMAIN_STATUS_COLORS[d.status]} variant="light">{d.status}</Badge>
          {isOurs && (
            <Tooltip label="Registry-confirmed on REG-MOINFOTECH">
              <IconShieldCheck size={18} color="var(--mantine-color-teal-6)" />
            </Tooltip>
          )}
          {meta.sponsoring_registrar && !isOurs && (
            <Badge size="sm" color="gray" variant="light">{meta.sponsoring_registrar}</Badge>
          )}
        </Group>
        <Group gap="xs">
          {can('domains.renew') && ['active', 'expired'].includes(d.status) && (
            <Button size="xs" variant="light" color="green" leftSection={<IconRefresh size={14} />}
              onClick={() => setRenewOpen(true)}>
              Renew (creates invoice)
            </Button>
          )}
        </Group>
      </Group>

      <Grid gutter="md">
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder radius="md" p="lg" h="100%">
            <Title order={5} mb="md">Overview</Title>
            <Stack gap="md">
              <Field label="Client:">
                {d.client
                  ? <Anchor size="sm" onClick={() => navigate(`/clients/${d.client!.id}`)}>{d.client.name}</Anchor>
                  : '—'}
              </Field>
              <Field label="Registration Date:">{fmtDate(d.registered_at)}</Field>
              <Field label="Next Due Date:">{fmtDate(d.expires_at)}</Field>
              {d.subscription && (
                <Field label="Billing Subscription:">
                  {d.subscription.label ?? 'domain subscription'}
                  {d.subscription.expire_date ? ` — next due ${dayjs(d.subscription.expire_date).format('D MMM YYYY')}` : ''}
                </Field>
              )}
              <Field label="Auto Renew:">
                {can('domains.renew') && !meta.unmanaged && ['active', 'expired'].includes(d.status) ? (
                  <Switch size="sm" checked={d.auto_renew}
                    disabled={autoRenewMutation.isPending}
                    label={d.auto_renew ? 'On — paid from client wallet' : 'Off'}
                    onChange={(e) => autoRenewMutation.mutate(e.currentTarget.checked)} />
                ) : (d.auto_renew ? 'On — paid from client wallet' : 'Off')}
              </Field>
              <Field label="Registrar Account:">{d.registrar_account?.name ?? '—'}</Field>
            </Stack>
          </Paper>
        </Grid.Col>

        <Grid.Col span={{ base: 12, md: 6 }}>
          <Stack gap="md" h="100%">
            <Paper withBorder radius="md" p="lg">
              <Title order={5} mb="md">SSL Monitor</Title>
              <Grid>
                <Grid.Col span={6}>
                  <Stack gap="md">
                    <Field label="SSL Status:">
                      <Group gap={6}>
                        {meta.ssl_valid
                          ? <IconLock size={15} color="var(--mantine-color-green-6)" />
                          : <IconLockOpen size={15} color="var(--mantine-color-gray-5)" />}
                        {meta.ssl_valid ? 'Valid SSL Detected' : 'No SSL Detected'}
                      </Group>
                    </Field>
                    <Field label="Issuer:">{meta.ssl_issuer ?? '—'}</Field>
                  </Stack>
                </Grid.Col>
                <Grid.Col span={6}>
                  <Stack gap="md">
                    <Field label="Start Date:">{meta.ssl_starts_at ? dayjs(meta.ssl_starts_at).format('D MMM YYYY') : '—'}</Field>
                    <Field label="Expiry Date:">{meta.ssl_expires_at ? dayjs(meta.ssl_expires_at).format('D MMM YYYY') : '—'}</Field>
                  </Stack>
                </Grid.Col>
              </Grid>
              {meta.last_synced_at && (
                <Text size="xs" c="dimmed" mt="sm">Last registry sync: {dayjs(meta.last_synced_at).format('D MMM YYYY HH:mm')}</Text>
              )}
            </Paper>

            <Paper withBorder radius="md" p="lg">
              <Title order={5} mb="md">Registry</Title>
              <Stack gap="md">
                <Group grow>
                  <Field label="Registrant:">{d as any && (d as any).registrant_handle ? <Code>{(d as any).registrant_handle}</Code> : '—'}</Field>
                  <Field label="NSset:">{(d as any).nsset_handle ? <Code>{(d as any).nsset_handle}</Code> : '—'}</Field>
                </Group>
                {can('domains.transfer') && (
                  authCode !== null ? (
                    authCode ? (
                      <Group>
                        <Code fz="md">{authCode}</Code>
                        <CopyButton value={authCode}>
                          {({ copied, copy }) => (
                            <Button size="xs" variant="light" color={copied ? 'green' : 'blue'}
                              leftSection={<IconCopy size={13} />} onClick={copy}>
                              {copied ? 'Copied' : 'Copy'}
                            </Button>
                          )}
                        </CopyButton>
                      </Group>
                    ) : <Text size="sm" c="dimmed">No transfer code stored for this domain.</Text>
                  ) : (
                    <Button size="xs" variant="light" color="orange" w="fit-content"
                      leftSection={<IconKey size={13} />} loading={authLoading} onClick={revealAuth}>
                      Reveal transfer code (logged)
                    </Button>
                  )
                )}
              </Stack>
            </Paper>
          </Stack>
        </Grid.Col>

        {!meta.unmanaged && d.name.endsWith('.tz') && (
          <Grid.Col span={12}>
            <NameserversCard domainId={d.id} domainStatus={d.status} />
          </Grid.Col>
        )}

        <Grid.Col span={12}>
          <Paper withBorder radius="md" p="lg">
            <Group gap="xs" mb="md"><IconHistory size={18} /><Title order={5}>Activity</Title></Group>
            {logs.length === 0 ? (
              <Text size="sm" c="dimmed">No activity recorded yet.</Text>
            ) : (
              <Timeline bulletSize={18} lineWidth={2} active={logs.length}>
                {logs.map((l) => (
                  <Timeline.Item key={l.id}
                    color={l.status === 'success' ? 'teal' : 'red'}
                    title={
                      <Group gap="xs">
                        <Text size="sm" fw={500}>{describeDomainAction(l.action)}</Text>
                        <Badge size="xs" variant="light" color={l.status === 'success' ? 'green' : 'red'}>{l.status}</Badge>
                      </Group>
                    }>
                    <Text size="xs" c="dimmed">{dayjs(l.created_at).format('D MMM YYYY HH:mm')}</Text>
                    {l.error && <Text size="xs" c="red" mt={2}>{l.error}</Text>}
                  </Timeline.Item>
                ))}
              </Timeline>
            )}
          </Paper>
        </Grid.Col>
      </Grid>

      <Modal opened={renewOpen} onClose={() => setRenewOpen(false)} title={`Renew ${d.name}`} centered>
        <StaffRenewForm domainId={d.id} onDone={() => setRenewOpen(false)} />
      </Modal>
    </Stack>
  );
}

function NameserversCard({ domainId, domainStatus }: { domainId: string; domainStatus: string }) {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [editing, setEditing] = useState(false);
  const [values, setValues] = useState<string[]>([]);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['domain-nameservers', domainId],
    queryFn: () => getDomainNameservers(domainId),
  });
  const ns = data?.data?.data;

  const saveMutation = useMutation({
    mutationFn: () => updateDomainNameservers(domainId, values.map((v) => v.trim()).filter(Boolean)),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['domain-nameservers', domainId] });
      qc.invalidateQueries({ queryKey: ['domain', domainId] });
      qc.invalidateQueries({ queryKey: ['domain-logs', domainId] });
      notifications.show({ title: 'Nameservers updated', message: res.data.message, color: 'green', autoClose: 9000 });
      setEditing(false);
    },
    onError: (e: any) => notifications.show({
      title: 'Update failed',
      message: e?.response?.data?.message ?? Object.values(e?.response?.data?.errors ?? {}).flat().join(' ') ?? 'Registry error.',
      color: 'red',
    }),
  });

  const startEdit = () => {
    const current = ns?.nameservers ?? [];
    setValues([...current, ...Array(Math.max(0, Math.max(2, current.length) - current.length)).fill('')]);
    setEditing(true);
  };

  const filled = values.map((v) => v.trim()).filter(Boolean);
  const canSave = filled.length >= 2 && new Set(filled).size === filled.length;
  const canEdit = can('domains.manage_dns') && ['active', 'expired'].includes(domainStatus) && !!ns?.nsset;

  return (
    <Paper withBorder radius="md" p="lg">
      <Group justify="space-between" mb="md">
        <Group gap="xs"><IconServer size={18} /><Title order={5}>Nameservers (DNS)</Title></Group>
        {!editing && canEdit && (
          <Button size="xs" variant="light" onClick={startEdit}>Change Nameservers</Button>
        )}
      </Group>

      {isLoading ? (
        <Group gap="xs"><Loader size="xs" /><Text size="sm" c="dimmed">Fetching live from the registry…</Text></Group>
      ) : isError || !ns ? (
        <Text size="sm" c="dimmed">Could not reach the registry — try again shortly.</Text>
      ) : !ns.nsset ? (
        <Text size="sm" c="dimmed">This domain has no nameserver set at the registry.</Text>
      ) : !editing ? (
        <Stack gap={6}>
          {ns.nameservers.map((n, i) => (
            <Group key={n} gap="xs">
              <Text size="sm" c="dimmed" w={40}>NS{i + 1}</Text>
              <Code fz="sm">{n}</Code>
            </Group>
          ))}
          <Text size="xs" c="dimmed" mt={4}>
            Registry set: <Code fz="xs">{ns.nsset}</Code>
            {ns.shared_with > 0 && ` — shared with ${ns.shared_with} other domain(s); changes here are applied safely to this domain only`}
          </Text>
        </Stack>
      ) : (
        <Stack gap="xs">
          {values.map((v, i) => (
            <TextInput key={i} size="sm" label={`NS${i + 1}`} placeholder={i < 2 ? 'required' : 'optional'}
              value={v}
              onChange={(e) => setValues(values.map((x, j) => (j === i ? e.currentTarget.value.toLowerCase() : x)))} />
          ))}
          {values.length < 5 && (
            <Button size="compact-xs" variant="subtle" w="fit-content" onClick={() => setValues([...values, ''])}>
              + add another
            </Button>
          )}
          {(ns.shared_with ?? 0) > 0 && (
            <Alert color="blue" variant="light" p="xs">
              This nameserver set is shared with {ns.shared_with} other domain(s). Saving creates a new set
              for this domain only — the others are not affected.
            </Alert>
          )}
          <Group justify="flex-end" mt="xs">
            <Button size="xs" variant="default" onClick={() => setEditing(false)}>Cancel</Button>
            <Button size="xs" color="green" disabled={!canSave} loading={saveMutation.isPending}
              onClick={() => saveMutation.mutate()}>
              Save to Registry
            </Button>
          </Group>
        </Stack>
      )}
    </Paper>
  );
}

function StaffRenewForm({ domainId, onDone }: { domainId: string; onDone: () => void }) {
  const qc = useQueryClient();
  const [years, setYears] = useState(1);

  const mutation = useMutation({
    mutationFn: () => renewDomain(domainId, years),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['domain', domainId] });
      qc.invalidateQueries({ queryKey: ['domains'] });
      notifications.show({ title: 'Renewal invoice created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      onDone();
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Renewal failed.', color: 'red' }),
  });

  return (
    <Stack>
      <NumberInput label="Years" min={1} max={10} value={years} onChange={(v) => setYears(Number(v) || 1)} />
      <Text size="xs" c="dimmed">Creates a renewal invoice; the registry renewal runs automatically once it is paid.</Text>
      <Group justify="flex-end">
        <Button color="green" loading={mutation.isPending} onClick={() => mutation.mutate()}>
          Create Renewal Invoice
        </Button>
      </Group>
    </Stack>
  );
}

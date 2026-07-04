import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, LoadingOverlay, Button, Grid,
  UnstyledButton, Collapse, Anchor, Switch, Alert, Code, CopyButton, Modal,
  NumberInput, Divider, Timeline, Center, Loader, TextInput,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useParams } from 'react-router-dom';
import {
  IconSettings, IconPlus, IconChevronDown, IconChevronUp, IconRefresh, IconWorld,
  IconArrowRight, IconLock, IconLockOpen, IconKey, IconCopy, IconServer,
  IconAddressBook, IconRepeat, IconLayoutDashboard, IconPuzzle, IconHistory,
  IconCheck, IconX,
} from '@tabler/icons-react';
import {
  getPortalDomainDetail, portalRenewDomain, portalSetAutoRenew, portalGetEppCode,
  getPortalDomainNameservers, updatePortalDomainNameservers, PortalDomainDetail,
} from '../../api/portal';
import { useAuth } from '../../context/AuthContext';

const fmtFull = (d: string | null | undefined) =>
  d ? new Date(d).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '—';
const fmtMoney = (n: number | null | undefined) =>
  n === null || n === undefined ? '—' : `Tsh.${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`;

const statusColor: Record<string, string> = {
  active: 'green', expired: 'red', pending: 'blue', failed: 'red', cancelled: 'gray',
};

type Section = 'overview' | 'autorenew' | 'nameservers' | 'addons' | 'contacts' | 'epp';

const SECTIONS: { key: Section; label: string; icon: React.ReactNode }[] = [
  { key: 'overview',    label: 'Overview',            icon: <IconLayoutDashboard size={16} /> },
  { key: 'autorenew',   label: 'Auto Renew',          icon: <IconRepeat size={16} /> },
  { key: 'nameservers', label: 'Nameservers',         icon: <IconServer size={16} /> },
  { key: 'addons',      label: 'Addons',              icon: <IconPuzzle size={16} /> },
  { key: 'contacts',    label: 'Contact Information', icon: <IconAddressBook size={16} /> },
  { key: 'epp',         label: 'Get EPP Code',        icon: <IconKey size={16} /> },
];

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <Text size="sm" fw={700}>{label}</Text>
      <Text size="sm" mt={2}>{children}</Text>
    </div>
  );
}

export default function PortalDomainDetails() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { user } = useAuth();
  const isPortalAdmin = (user as any)?.role === 'admin';

  const [section, setSection] = useState<Section>('overview');
  const [manageOpen, setManageOpen] = useState(true);
  const [actionsOpen, setActionsOpen] = useState(true);
  const [renewOpen, setRenewOpen] = useState(false);
  const [eppCode, setEppCode] = useState<string | null>(null);
  const [eppLoading, setEppLoading] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-domain', id],
    queryFn: () => getPortalDomainDetail(id!),
    enabled: !!id,
  });
  const d: PortalDomainDetail | undefined = data?.data?.data;

  const autoRenewMutation = useMutation({
    mutationFn: (enabled: boolean) => portalSetAutoRenew(id!, enabled),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['portal-domain', id] });
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
      notifications.show({ message: res.data.message, color: 'teal', autoClose: 9000 });
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Could not change auto-renew.', color: 'red',
    }),
  });

  const revealEpp = async () => {
    setEppLoading(true);
    try {
      const res = await portalGetEppCode(id!);
      setEppCode(res.data.auth_info);
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not fetch the transfer code.', color: 'red' });
    } finally {
      setEppLoading(false);
    }
  };

  if (isLoading || !d) {
    return <Center py="xl"><Loader /></Center>;
  }

  const sslKnown = d.ssl.valid !== null;

  return (
    <Stack pos="relative">
      <LoadingOverlay visible={isLoading} />

      <Group gap="xs">
        <IconWorld size={22} />
        <Title order={3}>{d.name}</Title>
        <Badge color={statusColor[d.status] ?? 'gray'} variant="light">{d.status}</Badge>
      </Group>

      <Grid gutter="md">
        {/* ── Sidebar ─────────────────────────────────────────── */}
        <Grid.Col span={{ base: 12, md: 3.5, lg: 3 }}>
          <Stack gap="md">
            <Paper withBorder radius="md">
              <UnstyledButton w="100%" p="sm" onClick={() => setManageOpen((v) => !v)}>
                <Group justify="space-between">
                  <Group gap="xs"><IconSettings size={16} /><Text fw={600} size="sm">Manage</Text></Group>
                  {manageOpen ? <IconChevronUp size={14} /> : <IconChevronDown size={14} />}
                </Group>
              </UnstyledButton>
              <Collapse in={manageOpen}>
                <Stack gap={4} p="xs" pt={0}>
                  {SECTIONS.map((s) => (
                    <UnstyledButton key={s.key} px="sm" py={8}
                      style={{
                        borderRadius: 8,
                        background: section === s.key ? 'var(--mantine-color-blue-6)' : undefined,
                        color: section === s.key ? 'white' : undefined,
                      }}
                      onClick={() => { setSection(s.key); setEppCode(null); }}>
                      <Group gap="xs">{s.icon}<Text size="sm" fw={section === s.key ? 600 : 400}>{s.label}</Text></Group>
                    </UnstyledButton>
                  ))}
                </Stack>
              </Collapse>
            </Paper>

            <Paper withBorder radius="md">
              <UnstyledButton w="100%" p="sm" onClick={() => setActionsOpen((v) => !v)}>
                <Group justify="space-between">
                  <Group gap="xs"><IconPlus size={16} /><Text fw={600} size="sm">Actions</Text></Group>
                  {actionsOpen ? <IconChevronUp size={14} /> : <IconChevronDown size={14} />}
                </Group>
              </UnstyledButton>
              <Collapse in={actionsOpen}>
                <Stack gap={4} p="xs" pt={0}>
                  {!d.unmanaged && ['active', 'expired'].includes(d.status) && (
                    <UnstyledButton px="sm" py={8} onClick={() => setRenewOpen(true)}>
                      <Group gap="xs"><IconRefresh size={16} color="var(--mantine-color-blue-6)" /><Text size="sm" c="blue">Renew Domain</Text></Group>
                    </UnstyledButton>
                  )}
                  <UnstyledButton px="sm" py={8} onClick={() => navigate('/portal/domains?order=register')}>
                    <Group gap="xs"><IconWorld size={16} color="var(--mantine-color-blue-6)" /><Text size="sm" c="blue">Register a New Domain</Text></Group>
                  </UnstyledButton>
                  <UnstyledButton px="sm" py={8} onClick={() => navigate('/portal/domains?order=transfer')}>
                    <Group gap="xs"><IconArrowRight size={16} color="var(--mantine-color-blue-6)" /><Text size="sm" c="blue">Transfer in a Domain</Text></Group>
                  </UnstyledButton>
                </Stack>
              </Collapse>
            </Paper>
          </Stack>
        </Grid.Col>

        {/* ── Main card ───────────────────────────────────────── */}
        <Grid.Col span={{ base: 12, md: 8.5, lg: 9 }}>
          <Paper withBorder radius="md" p="lg">
            {section === 'overview' && (
              <Stack gap="lg">
                <Title order={4}>Overview</Title>

                <Grid>
                  <Grid.Col span={{ base: 12, sm: 6 }}>
                    <Stack gap="md">
                      <Field label="Domain:">
                        <Anchor href={`https://${d.name}`} target="_blank" size="sm">{d.name}</Anchor>
                      </Field>
                      <Field label="Registration Date:">{fmtFull(d.registered_at)}</Field>
                      <Field label="Next Due Date:">{fmtFull(d.expires_at)}</Field>
                      <Field label="Status:">
                        <Badge color={statusColor[d.status] ?? 'gray'} variant="light">{d.status}</Badge>
                      </Field>
                    </Stack>
                  </Grid.Col>
                  <Grid.Col span={{ base: 12, sm: 6 }}>
                    <Stack gap="md">
                      <Field label="First Payment Amount:">{fmtMoney(d.billing.first_payment)}</Field>
                      <Field label="Recurring Amount:">
                        {fmtMoney(d.billing.recurring)} {d.billing.recurring !== null && d.billing.cycle}
                      </Field>
                      <Field label="Payment Method:">{d.billing.payment_method ?? '—'}</Field>
                      <Field label="Auto Renew:">
                        <Badge variant="light" color={d.auto_renew ? 'teal' : 'gray'}
                          leftSection={d.auto_renew ? <IconCheck size={10} /> : <IconX size={10} />}>
                          {d.auto_renew ? 'Enabled' : 'Disabled'}
                        </Badge>
                      </Field>
                    </Stack>
                  </Grid.Col>
                </Grid>

                <Divider />

                <Grid>
                  <Grid.Col span={{ base: 12, sm: 6 }}>
                    <Stack gap="md">
                      <Field label="SSL Status:">
                        <Group gap={6}>
                          {d.ssl.valid
                            ? <IconLock size={16} color="var(--mantine-color-green-6)" />
                            : <IconLockOpen size={16} color="var(--mantine-color-gray-5)" />}
                          {sslKnown ? (d.ssl.valid ? 'Valid SSL Detected' : 'No SSL Detected') : 'Not checked yet'}
                        </Group>
                      </Field>
                      <Field label="SSL Issuer Name:">{d.ssl.issuer ?? '—'}</Field>
                    </Stack>
                  </Grid.Col>
                  <Grid.Col span={{ base: 12, sm: 6 }}>
                    <Stack gap="md">
                      <Field label="SSL Start Date:">{fmtFull(d.ssl.starts_at)}</Field>
                      <Field label="SSL Expiry Date:">{fmtFull(d.ssl.expires_at)}</Field>
                    </Stack>
                  </Grid.Col>
                </Grid>

                <Divider />

                <div>
                  <Text fw={700} mb="xs">What would you like to do today?</Text>
                  <Stack gap={6} pl="sm">
                    <Anchor size="sm" onClick={() => setSection('nameservers')}>
                      • Change the nameservers your domain points to
                    </Anchor>
                    <Anchor size="sm" onClick={() => setSection('contacts')}>
                      • Update the WHOIS contact information for your domain
                    </Anchor>
                    {!d.unmanaged && ['active', 'expired'].includes(d.status) && (
                      <Anchor size="sm" onClick={() => setRenewOpen(true)}>• Renew Domain</Anchor>
                    )}
                  </Stack>
                </div>

                {d.activity.length > 0 && (
                  <>
                    <Divider />
                    <div>
                      <Group gap="xs" mb="sm"><IconHistory size={16} /><Text fw={700}>Recent Activity</Text></Group>
                      <Timeline bulletSize={18} lineWidth={2} active={d.activity.length}>
                        {d.activity.map((a, i) => (
                          <Timeline.Item key={i}
                            color={a.status === 'success' ? 'teal' : 'red'}
                            title={<Text size="sm">{a.action}</Text>}>
                            <Text size="xs" c="dimmed">
                              {new Date(a.created_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
                              {a.status !== 'success' && ' — failed'}
                            </Text>
                          </Timeline.Item>
                        ))}
                      </Timeline>
                    </div>
                  </>
                )}
              </Stack>
            )}

            {section === 'autorenew' && (
              <Stack gap="md">
                <Title order={4}>Auto Renew</Title>
                <Text size="sm" c="dimmed">
                  When auto renew is on, we automatically renew this domain before it expires and pay the
                  renewal from your account credit. Keep enough balance in your wallet — the renewal only
                  completes while your credit covers it.
                </Text>
                {isPortalAdmin ? (
                  <Switch size="md" checked={d.auto_renew}
                    disabled={autoRenewMutation.isPending || (d.unmanaged && !d.auto_renew)}
                    label={d.auto_renew ? 'Auto renew is ON' : 'Auto renew is OFF'}
                    onChange={(e) => autoRenewMutation.mutate(e.currentTarget.checked)} />
                ) : (
                  <Alert color="gray" variant="light">Only portal administrators can change auto-renew.</Alert>
                )}
                {d.unmanaged && (
                  <Alert color="orange" variant="light">This domain is renewed manually — please contact us.</Alert>
                )}
                <Button variant="light" w="fit-content" onClick={() => navigate('/portal/dashboard')}>
                  Add Funds to Wallet
                </Button>
              </Stack>
            )}

            {section === 'nameservers' && (
              <NameserversSection domainId={d.id} isPortalAdmin={isPortalAdmin} />
            )}

            {section === 'addons' && (
              <Stack gap="md">
                <Title order={4}>Addons</Title>
                <Alert color="gray" variant="light">
                  No purchasable addons are available for this domain. DNS management and registrar-lock
                  are included with every domain we manage — contact us if you need changes.
                </Alert>
              </Stack>
            )}

            {section === 'contacts' && (
              <Stack gap="md">
                <Title order={4}>Contact Information</Title>
                <Grid>
                  <Grid.Col span={{ base: 12, sm: 6 }}>
                    <Field label="Registrant Contact (registry handle):">
                      {d.registry.registrant_handle ? <Code>{d.registry.registrant_handle}</Code> : '—'}
                    </Field>
                  </Grid.Col>
                  <Grid.Col span={{ base: 12, sm: 6 }}>
                    <Field label="Admin Contact (registry handle):">
                      {d.registry.admin_handle ? <Code>{d.registry.admin_handle}</Code> : '—'}
                    </Field>
                  </Grid.Col>
                </Grid>
                <Alert color="blue" variant="light">
                  WHOIS contact details are held at the .tz registry. To update the registrant or admin
                  information, open a support ticket and we will submit the change to the registry.
                </Alert>
                <Button variant="light" w="fit-content" onClick={() => navigate('/portal/tickets')}>
                  Open a Support Ticket
                </Button>
              </Stack>
            )}

            {section === 'epp' && (
              <Stack gap="md">
                <Title order={4}>Get EPP Code</Title>
                <Text size="sm" c="dimmed">
                  The EPP (auth-info) code is required to transfer your domain to another registrar.
                  Keep it secret — anyone with this code can move your domain.
                </Text>
                {!isPortalAdmin ? (
                  <Alert color="gray" variant="light">Only portal administrators can view the transfer code.</Alert>
                ) : !d.has_epp_code ? (
                  <Alert color="orange" variant="light">No transfer code is stored for this domain — please contact us.</Alert>
                ) : eppCode ? (
                  <Group>
                    <Code fz="md">{eppCode}</Code>
                    <CopyButton value={eppCode}>
                      {({ copied, copy }) => (
                        <Button size="xs" variant="light" color={copied ? 'green' : 'blue'}
                          leftSection={<IconCopy size={13} />} onClick={copy}>
                          {copied ? 'Copied' : 'Copy'}
                        </Button>
                      )}
                    </CopyButton>
                  </Group>
                ) : (
                  <Button w="fit-content" leftSection={<IconKey size={15} />} loading={eppLoading} onClick={revealEpp}>
                    Reveal EPP Code
                  </Button>
                )}
                <Text size="xs" c="dimmed">Every access to this code is recorded in the domain's activity log.</Text>
              </Stack>
            )}
          </Paper>

          <Text size="xs" c="dimmed" ta="center" mt="md">Powered by MoBilling</Text>
        </Grid.Col>
      </Grid>

      <Modal opened={renewOpen} onClose={() => setRenewOpen(false)} title={`Renew ${d.name}`} centered>
        <RenewForm domainId={d.id} onDone={() => { setRenewOpen(false); navigate('/portal/invoices'); }} />
      </Modal>
    </Stack>
  );
}

function NameserversSection({ domainId, isPortalAdmin }: { domainId: string; isPortalAdmin: boolean }) {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [values, setValues] = useState<string[]>([]);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['portal-domain-ns', domainId],
    queryFn: () => getPortalDomainNameservers(domainId),
  });
  const ns = data?.data?.data;

  const saveMutation = useMutation({
    mutationFn: () => updatePortalDomainNameservers(domainId, values.map((v) => v.trim()).filter(Boolean)),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['portal-domain-ns', domainId] });
      notifications.show({ title: 'Nameservers updated', message: res.data.message, color: 'green', autoClose: 9000 });
      setEditing(false);
    },
    onError: (e: any) => notifications.show({
      title: 'Update failed',
      message: e?.response?.data?.message
        ?? Object.values(e?.response?.data?.errors ?? {}).flat().join(' ')
        ?? 'Please check the hostnames and try again.',
      color: 'red',
    }),
  });

  const startEdit = () => {
    const current = ns?.nameservers ?? [];
    setValues(current.length >= 2 ? [...current] : [...current, ...Array(2 - current.length).fill('')]);
    setEditing(true);
  };

  const filled = values.map((v) => v.trim()).filter(Boolean);
  const canSave = filled.length >= 2 && new Set(filled).size === filled.length;

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={4}>Nameservers</Title>
        {!editing && isPortalAdmin && ns?.editable && (
          <Button size="xs" variant="light" onClick={startEdit}>Change Nameservers</Button>
        )}
      </Group>
      <Text size="sm" c="dimmed">
        Nameservers control where your domain points — your website and email follow them.
        Only change these if you know the nameservers of your new hosting provider.
      </Text>

      {isLoading ? (
        <Group gap="xs"><Loader size="xs" /><Text size="sm" c="dimmed">Fetching live from the registry…</Text></Group>
      ) : isError ? (
        <Alert color="orange" variant="light">Could not reach the registry — please try again shortly.</Alert>
      ) : !ns || ns.nameservers.length === 0 ? (
        <Alert color="blue" variant="light">
          No nameservers are recorded for this domain — please contact us if your website is not working.
        </Alert>
      ) : !editing ? (
        <Stack gap={6}>
          {ns.nameservers.map((n, i) => (
            <Group key={n} gap="xs">
              <Text size="sm" c="dimmed" w={40}>NS{i + 1}</Text>
              <Code fz="sm">{n}</Code>
            </Group>
          ))}
          {!isPortalAdmin && (
            <Text size="xs" c="dimmed" mt={4}>Only portal administrators can change nameservers.</Text>
          )}
        </Stack>
      ) : (
        <Stack gap="xs" maw={420}>
          {values.map((v, i) => (
            <TextInput key={i} size="sm" label={`NS${i + 1}`} placeholder={i < 2 ? 'required — e.g. ns1.example.com' : 'optional'}
              value={v}
              onChange={(e) => setValues(values.map((x, j) => (j === i ? e.currentTarget.value.toLowerCase() : x)))} />
          ))}
          {values.length < 5 && (
            <Button size="compact-xs" variant="subtle" w="fit-content" onClick={() => setValues([...values, ''])}>
              + add another
            </Button>
          )}
          <Alert color="orange" variant="light" p="xs">
            Wrong nameservers will take your website and email offline. Changes can take a few hours to propagate.
          </Alert>
          <Group justify="flex-end" mt="xs">
            <Button size="xs" variant="default" onClick={() => setEditing(false)}>Cancel</Button>
            <Button size="xs" color="green" disabled={!canSave} loading={saveMutation.isPending}
              onClick={() => saveMutation.mutate()}>
              Save Nameservers
            </Button>
          </Group>
        </Stack>
      )}
    </Stack>
  );
}

function RenewForm({ domainId, onDone }: { domainId: string; onDone: () => void }) {
  const qc = useQueryClient();
  const [years, setYears] = useState(1);

  const mutation = useMutation({
    mutationFn: () => portalRenewDomain(domainId, years),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-domain', domainId] });
      qc.invalidateQueries({ queryKey: ['portal-domains'] });
      notifications.show({ title: 'Renewal invoice created', message: res?.data?.message, color: 'green', autoClose: 8000 });
      onDone();
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Renewal failed — please contact us.', color: 'red',
    }),
  });

  return (
    <Stack>
      <NumberInput label="Years" min={1} max={10} value={years} onChange={(v) => setYears(Number(v) || 1)} />
      <Text size="xs" c="dimmed">
        An invoice is created now — your domain renews automatically the moment it is paid.
      </Text>
      <Group justify="flex-end">
        <Button color="green" loading={mutation.isPending} onClick={() => mutation.mutate()}>
          Create Invoice & Pay
        </Button>
      </Group>
    </Stack>
  );
}

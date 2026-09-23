import { useMemo, useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, Stack, Tabs, Loader, Center,
  SimpleGrid, ThemeIcon, ActionIcon, Tooltip, Anchor, Drawer, Progress,
} from '@mantine/core';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { notifications } from '@mantine/notifications';
import { IconPhoneCall, IconAlertTriangle, IconPlayerPlay, IconCoin, IconFileInvoice, IconTarget } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getFollowupDashboard, getFollowups, getCollectionAssignments, FollowupEntry } from '../api/followups';
import { getTargets, getCommissionSummary, StaffTarget } from '../api/staffTargets';
import { getDocument, Document } from '../api/documents';
import { useAuth } from '../context/AuthContext';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import LogCallModal from '../components/Collections/LogCallModal';
import CollectionsProgressPanel from '../components/Collections/CollectionsProgressPanel';
import DocumentView from '../components/Billing/DocumentView';

const ACTIVE = ['pending', 'open', 'broken'];

export default function MyCollections() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [logging, setLogging] = useState<FollowupEntry | null>(null);
  const [viewDoc, setViewDoc] = useState<Document | null>(null);

  const dash = useQuery({ queryKey: ['followup-dashboard'], queryFn: getFollowupDashboard });
  const mine = useQuery({
    queryKey: ['my-followups', user?.id],
    queryFn: () => getFollowups({ user_id: String(user?.id), per_page: '100' }),
    enabled: !!user?.id,
  });
  const assignQ = useQuery({
    queryKey: ['collection-assignments-mine', user?.id],
    queryFn: () => getCollectionAssignments({ mine: '1' }),
    enabled: !!user?.id,
  });
  const assignByDoc = useMemo(() => {
    const m = new Map<string, NonNullable<typeof assignQ.data>['data']['data'][number]>();
    (assignQ.data?.data?.data ?? []).forEach((a) => { const c = m.get(a.document_id); if (!c || a.status === 'active') m.set(a.document_id, a); });
    return m;
  }, [assignQ.data]);
  const aSum = assignQ.data?.data?.summary;
  const targetsQ = useQuery({ queryKey: ['staff-targets-mine'], queryFn: () => getTargets() });
  const summaryQ = useQuery({
    queryKey: ['staff-targets-summary-mine', user?.id],
    queryFn: () => getCommissionSummary({ user_id: String(user?.id) }),
    enabled: !!user?.id,
  });

  const dueToday = (dash.data?.data?.data?.due_today ?? []).filter((f) => f.user_id === user?.id);
  const overdue = (dash.data?.data?.data?.overdue_followups ?? []).filter((f) => f.user_id === user?.id);

  // Unpaid invoices with an active follow-up for me — one row per invoice.
  const assigned = useMemo(() => {
    const rows: FollowupEntry[] = mine.data?.data?.data ?? [];
    const byDoc = new Map<string, FollowupEntry>();
    rows.forEach((f) => {
      if (!ACTIVE.includes(f.status) && f.status !== 'escalated') return;
      if (!(f.invoice_balance > 0)) return;
      const cur = byDoc.get(f.document_id);
      // prefer the row that still has a scheduled next follow-up
      if (!cur || (!cur.next_followup && f.next_followup)) byDoc.set(f.document_id, f);
    });
    return Array.from(byDoc.values());
  }, [mine.data]);
  const totalAssigned = assigned.reduce((s, f) => s + Number(f.invoice_balance || 0), 0);

  const targets: StaffTarget[] = (targetsQ.data?.data?.data ?? [])
    .filter((t) => t.user.id === user?.id && t.status !== 'cancelled');
  const commission = (summaryQ.data?.data?.data ?? []).find((e) => e.user.id === user?.id);

  const openPreview = async (id: string) => {
    try {
      setViewDoc((await getDocument(id)).data.data);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to load invoice.', color: 'red' });
    }
  };
  const refreshAll = () => {
    ['followup-dashboard', 'my-followups'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
  };

  const followupTable = (rows: FollowupEntry[], overdueList: boolean) => (
    <Table.ScrollContainer minWidth={700}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Client</Table.Th>
            <Table.Th>Invoice</Table.Th>
            <Table.Th>Balance</Table.Th>
            <Table.Th>Follow-up date</Table.Th>
            <Table.Th>Calls</Table.Th>
            <Table.Th>Action</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {rows.map((f) => (
            <Table.Tr key={f.id}>
              <Table.Td>
                <Anchor size="sm" fw={500} tt="uppercase" onClick={() => navigate(`/clients/${f.client_id}`)}>{f.client_name}</Anchor>
                <Text size="xs" c="dimmed">{f.client_phone || ''}</Text>
              </Table.Td>
              <Table.Td><Anchor size="sm" onClick={() => openPreview(f.document_id)}>{f.document_number}</Anchor></Table.Td>
              <Table.Td fw={600} c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
              <Table.Td>
                <Badge color={overdueList ? 'red' : 'blue'} variant="light" size="sm">
                  {f.next_followup ? formatDate(f.next_followup) : '—'}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Badge color={(f.call_count ?? 0) >= 3 ? 'red' : 'gray'} variant="light" size="sm">{f.call_count ?? 0}/3</Badge>
              </Table.Td>
              <Table.Td>
                <Tooltip label="Log Call">
                  <ActionIcon color="green" variant="light" onClick={() => setLogging(f)}>
                    <IconPlayerPlay size={16} />
                  </ActionIcon>
                </Tooltip>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );

  if (dash.isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack gap="lg">
      <div>
        <Title order={2}>My Collections</Title>
        <Text size="sm" c="dimmed">Madeni uliyopewa kufuatilia, simu za leo, lengo lako na commission.</Text>
      </div>

      <SimpleGrid cols={{ base: 1, xs: 3 }}>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md"><IconPhoneCall size={20} /></ThemeIcon>
            <div><Text size="xs" c="dimmed" tt="uppercase" fw={600}>Due today</Text><Text size="xl" fw={700}>{dueToday.length}</Text></div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="red" size="lg" radius="md"><IconAlertTriangle size={20} /></ThemeIcon>
            <div><Text size="xs" c="dimmed" tt="uppercase" fw={600}>Overdue</Text><Text size="xl" fw={700}>{overdue.length}</Text></div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="teal" size="lg" radius="md"><IconFileInvoice size={20} /></ThemeIcon>
            <div><Text size="xs" c="dimmed" tt="uppercase" fw={600}>Assigned balance</Text><Text size="xl" fw={700}>{formatCurrency(totalAssigned)}</Text></div>
          </Group>
        </Paper>
      </SimpleGrid>

      <Tabs defaultValue="followups">
        <Tabs.List>
          <Tabs.Tab value="followups" leftSection={<IconPhoneCall size={16} />}>My follow-ups</Tabs.Tab>
          <Tabs.Tab value="invoices" leftSection={<IconFileInvoice size={16} />}>My assigned invoices</Tabs.Tab>
          <Tabs.Tab value="target" leftSection={<IconTarget size={16} />}>My target &amp; commission</Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="followups" pt="md">
          <Stack gap="md">
            <Paper withBorder p="md" radius="md">
              <Group gap="sm" mb="sm"><Title order={4}>Due today</Title><Badge color="blue" variant="light">{dueToday.length}</Badge></Group>
              {dueToday.length ? followupTable(dueToday, false) : <Text c="dimmed" size="sm">No calls scheduled for you today.</Text>}
            </Paper>
            <Paper withBorder p="md" radius="md">
              <Group gap="sm" mb="sm"><Title order={4}>Overdue</Title><Badge color="red" variant="light">{overdue.length}</Badge></Group>
              {overdue.length ? followupTable(overdue, true) : <Text c="dimmed" size="sm">Nothing overdue. Good job!</Text>}
            </Paper>
          </Stack>
        </Tabs.Panel>

        <Tabs.Panel value="invoices" pt="md">
          {aSum && aSum.count > 0 && (
            <SimpleGrid cols={{ base: 2, sm: 4 }} mb="md">
              {([['Total target', aSum.target, undefined], ['Collected', aSum.collected, undefined], ['Commission earned', aSum.commission_earned, 'green'], ['Commission unpaid', aSum.commission_unpaid, 'orange']] as [string, number, string | undefined][]).map(([l, v, c]) => (
                <Paper key={l} withBorder p="md" radius="md"><Text size="xs" c="dimmed" tt="uppercase" fw={600}>{l}</Text><Text size="lg" fw={700} c={c}>{formatCurrency(v)}</Text></Paper>
              ))}
            </SimpleGrid>
          )}
          <Paper withBorder p="md" radius="md">
            {mine.isLoading ? <Center py="md"><Loader size="sm" /></Center> : mine.isError ? (
              <Text c="red" size="sm">Failed to load your assigned invoices.</Text>
            ) : !assigned.length ? (
              <Text c="dimmed" size="sm">No unpaid invoices are assigned to you.</Text>
            ) : (
              <Table.ScrollContainer minWidth={900}>
                <Table striped highlightOnHover>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Client</Table.Th><Table.Th>Invoice</Table.Th><Table.Th>Total</Table.Th>
                      <Table.Th>Balance</Table.Th><Table.Th>Target</Table.Th><Table.Th>Collected</Table.Th>
                      <Table.Th>Remaining</Table.Th><Table.Th>Commission</Table.Th><Table.Th>Next follow-up</Table.Th><Table.Th>Status</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {assigned.map((f) => (
                      <Table.Tr key={f.document_id}>
                        <Table.Td fw={500} tt="uppercase">{f.client_name}</Table.Td>
                        <Table.Td><Anchor size="sm" onClick={() => openPreview(f.document_id)}>{f.document_number}</Anchor></Table.Td>
                        <Table.Td>{formatCurrency(f.invoice_total)}</Table.Td>
                        <Table.Td fw={600} c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                        {(() => {
                          const a = assignByDoc.get(f.document_id);
                          return a ? (
                            <>
                              <Table.Td>{formatCurrency(a.target)}</Table.Td>
                              <Table.Td>{formatCurrency(a.collected)}</Table.Td>
                              <Table.Td>{formatCurrency(a.remaining)}</Table.Td>
                              <Table.Td>
                                {a.commission_type === 'none' ? '—' : (
                                  <>
                                    <Text size="sm" fw={600} c="green">{formatCurrency(a.commission_earned)}</Text>
                                    <Text size="xs" c="dimmed">{a.commission_type === 'percentage' ? `${a.commission_value}%` : `${formatCurrency(a.commission_value)} fixed`}{a.commission_earned > 0 ? (a.paid_out_at ? ' · paid' : ' · unpaid') : ''}</Text>
                                  </>
                                )}
                              </Table.Td>
                            </>
                          ) : <Table.Td colSpan={4}><Text size="xs" c="dimmed">No target set</Text></Table.Td>;
                        })()}
                        <Table.Td>{f.next_followup ? formatDate(f.next_followup) : '—'}</Table.Td>
                        <Table.Td><Badge size="sm" variant="light" color={f.status === 'escalated' ? 'orange' : 'blue'}>{f.status}</Badge></Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            )}
          </Paper>
        </Tabs.Panel>

        <Tabs.Panel value="target" pt="md">
          <Stack gap="md">
            <Paper withBorder p="md" radius="md">
              <Group gap="sm">
                <ThemeIcon variant="light" color="green" size="lg" radius="md"><IconCoin size={20} /></ThemeIcon>
                <div>
                  <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Commission earned (verified targets)</Text>
                  <Text size="xl" fw={700}>{formatCurrency(commission?.total_commission ?? 0)}</Text>
                </div>
              </Group>
            </Paper>
            {targetsQ.isLoading ? <Center py="md"><Loader size="sm" /></Center> : !targets.length ? (
              <Text c="dimmed" size="sm">No targets assigned to you yet.</Text>
            ) : targets.map((t) => (
              <Paper key={t.id} withBorder p="md" radius="md">
                <Group justify="space-between" mb="xs">
                  <Text fw={600}>{t.title}</Text>
                  <Group gap="xs">
                    <Text size="xs" c="dimmed">{dayjs(t.period_start).format('D MMM')} – {dayjs(t.period_end).format('D MMM YYYY')}</Text>
                    <Badge size="sm" variant="light" color={t.status === 'verified' ? 'green' : 'blue'}>{t.status.replace('_', ' ')}</Badge>
                  </Group>
                </Group>
                <Stack gap="sm">
                  {t.criteria.some((c) => c.type === 'collections') && <CollectionsProgressPanel target={t} />}
                  {t.criteria.filter((c) => c.type !== 'collections').map((c) => {
                    const achieved = Number(c.verified_value ?? c.achieved_value ?? 0);
                    const pct = c.goal_value > 0 ? Math.min(100, (achieved / c.goal_value) * 100) : 0;
                    return (
                      <div key={c.id}>
                        <Group justify="space-between" mb={3}>
                          <Text size="xs" fw={500}>{c.label}</Text>
                          <Text size="xs" c="dimmed">{achieved.toLocaleString()} / {Number(c.goal_value).toLocaleString()} {c.unit}</Text>
                        </Group>
                        <Progress size="sm" value={pct} color={pct >= 100 ? 'green' : 'blue'} />
                      </div>
                    );
                  })}
                  {t.status === 'verified' && (
                    <Text size="sm" fw={600}>Total commission: {formatCurrency(t.total_commission)}</Text>
                  )}
                </Stack>
              </Paper>
            ))}
          </Stack>
        </Tabs.Panel>
      </Tabs>

      <LogCallModal followup={logging} onClose={() => setLogging(null)} onLogged={refreshAll} />

      <Drawer opened={!!viewDoc} onClose={() => setViewDoc(null)} title="Invoice Preview" size="xl" position="right">
        {viewDoc && (
          <DocumentView
            document={viewDoc}
            onRefresh={async () => { setViewDoc((await getDocument(viewDoc.id)).data.data); refreshAll(); }}
            onClose={() => setViewDoc(null)}
          />
        )}
      </Drawer>
    </Stack>
  );
}

import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, Stack, Select,
  Loader, Center, Modal, Button,
  SimpleGrid, ThemeIcon, ActionIcon, Tooltip, Pagination, Anchor, Drawer, Tabs,
} from '@mantine/core';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPhone, IconPhoneCall, IconAlertTriangle,
  IconX, IconPlayerPlay, IconScript,
} from '@tabler/icons-react';
import {
  getFollowupDashboard, getFollowups, cancelFollowup,
  FollowupEntry,
} from '../api/followups';
import { getDocument, getDocuments, Document } from '../api/documents';
import { usePermissions } from '../hooks/usePermissions';
import LogCallModal from '../components/Collections/LogCallModal';
import AssignFollowupModal from '../components/Collections/AssignFollowupModal';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { useAuth } from '../context/AuthContext';
import CallScriptDrawer from '../components/CallScriptDrawer';
import UnassignedInvoicesPanel from '../components/Collections/UnassignedInvoicesPanel';
import CommissionsPanel from '../components/Collections/CommissionsPanel';
import DocumentView from '../components/Billing/DocumentView';

const outcomeColors: Record<string, string> = {
  promised: 'blue',
  declined: 'red',
  no_answer: 'gray',
  disputed: 'orange',
  partial_payment: 'yellow',
};

const statusColors: Record<string, string> = {
  pending: 'blue',
  open: 'cyan',
  fulfilled: 'green',
  broken: 'red',
  escalated: 'orange',
  cancelled: 'gray',
};

export default function Followups() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { user } = useAuth();
  const agentName = user?.name || 'Agent';
  const [scriptDrawerOpen, setScriptDrawerOpen] = useState(false);
  const { can } = usePermissions();
  const [viewDoc, setViewDoc] = useState<Document | null>(null);
  const [assignPickerOpen, setAssignPickerOpen] = useState(false);
  const [pickSearch, setPickSearch] = useState('');
  const [pickDoc, setPickDoc] = useState<Document | null>(null);
  const [selectedFollowup, setSelectedFollowup] = useState<FollowupEntry | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterOutcome, setFilterOutcome] = useState<string>('all');
  const [page, setPage] = useState(1);

  const { data: dashData, isLoading: dashLoading } = useQuery({
    queryKey: ['followup-dashboard'],
    queryFn: getFollowupDashboard,
  });

  const { data: historyData, isLoading: histLoading, isError: histError } = useQuery({
    queryKey: ['followups', filterStatus, filterOutcome, page],
    queryFn: () => getFollowups({
      status: filterStatus,
      outcome: filterOutcome,
      page: String(page),
      per_page: '15',
    }),
  });

  const { data: pickData } = useQuery({
    queryKey: ['assign-invoice-picker', pickSearch],
    queryFn: () => getDocuments({ type: 'invoice', search: pickSearch || undefined, per_page: 50 }),
    enabled: assignPickerOpen,
  });
  const pickable: Document[] = ((pickData?.data?.data ?? []) as Document[])
    .filter((d) => ['sent', 'overdue', 'partial'].includes(d.status));

  const cancelMutation = useMutation({
    mutationFn: cancelFollowup,
    onSuccess: () => {
      notifications.show({ title: 'Cancelled', message: 'Follow-up cancelled.', color: 'gray' });
      queryClient.invalidateQueries({ queryKey: ['followup-dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['followups'] });
    },
  });

  const openLogModal = (f: FollowupEntry) => setSelectedFollowup(f);

  const openPreview = async (docId: string) => {
    try {
      const res = await getDocument(docId);
      setViewDoc(res.data.data);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to load invoice.', color: 'red' });
    }
  };

  const handleDocRefresh = async () => {
    try {
      if (viewDoc) {
        const res = await getDocument(viewDoc.id);
        setViewDoc(res.data.data);
      }
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to refresh invoice.', color: 'red' });
    }
    queryClient.invalidateQueries({ queryKey: ['followup-dashboard'] });
    queryClient.invalidateQueries({ queryKey: ['followups'] });
    queryClient.invalidateQueries({ queryKey: ['unassigned-invoices'] });
  };

  const dashboard = dashData?.data?.data;
  const history = historyData?.data;

  if (dashLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Stack gap="lg">
      <Group justify="space-between">
        <Title order={2}>Follow-ups</Title>
        <Group gap="sm">
          {can('menu.followups') && (
            <Button variant="filled" onClick={() => { setPickDoc(null); setPickSearch(''); setAssignPickerOpen(true); }}>
              Assign invoice to staff
            </Button>
          )}
          <Button
            variant="light"
            color="teal"
            leftSection={<IconScript size={18} />}
            onClick={() => setScriptDrawerOpen(true)}
          >
            Call Script
          </Button>
        </Group>
      </Group>

      <Tabs defaultValue="active" keepMounted={false}>
        <Tabs.List mb="md">
          <Tabs.Tab value="active">Follow-ups</Tabs.Tab>
          <Tabs.Tab value="unassigned">Unassigned (Hazijapangiwa)</Tabs.Tab>
          {(can('staff_targets.manage') || can('staff_targets.verify')) && <Tabs.Tab value="commissions">Commissions</Tabs.Tab>}
        </Tabs.List>
        <Tabs.Panel value="commissions">
          <CommissionsPanel onOpenInvoice={openPreview} />
        </Tabs.Panel>
        <Tabs.Panel value="unassigned">
          <UnassignedInvoicesPanel onOpenInvoice={openPreview} />
        </Tabs.Panel>
        <Tabs.Panel value="active">
          <Stack gap="lg">
      {/* Stats */}
      <SimpleGrid cols={{ base: 1, xs: 3 }}>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md">
              <IconPhoneCall size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Calls Due Today</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.due_today ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="red" size="lg" radius="md">
              <IconAlertTriangle size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Overdue Follow-ups</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.overdue ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="cyan" size="lg" radius="md">
              <IconPhone size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Total Active</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.total_active ?? 0}</Text>
            </div>
          </Group>
        </Paper>
      </SimpleGrid>

      {/* Calls Due Today */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconPhoneCall size={20} />
          <Title order={4}>Calls Due Today</Title>
          <Badge color="blue" variant="light" size="sm">{dashboard?.due_today.length ?? 0}</Badge>
        </Group>
        {!dashboard?.due_today.length ? (
          <Text c="dimmed" size="sm">No calls scheduled for today.</Text>
        ) : (
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Balance</Table.Th>
                  <Table.Th>Assigned To</Table.Th>
                  <Table.Th>Calls Made</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.due_today.map((f) => (
                  <Table.Tr key={f.id}>
                    <Table.Td fw={500}>
                      <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${f.client_id}`)} style={{ textTransform: 'uppercase' }}>
                        {f.client_name}
                      </Anchor>
                    </Table.Td>
                    <Table.Td>{f.client_phone || '—'}</Table.Td>
                    <Table.Td>
                      <Anchor size="sm" onClick={() => openPreview(f.document_id)}>
                        {f.document_number}
                      </Anchor>
                    </Table.Td>
                    <Table.Td fw={600} c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                    <Table.Td>{f.assigned_to || '—'}</Table.Td>
                    <Table.Td>
                      <Badge color={f.call_count! >= 3 ? 'red' : 'gray'} variant="light" size="sm">
                        {f.call_count}/3
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={statusColors[f.status]} size="sm">{f.status}</Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <Tooltip label="Log Call">
                          <ActionIcon color="green" variant="light" onClick={() => openLogModal(f)}>
                            <IconPlayerPlay size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Cancel">
                          <ActionIcon color="gray" variant="light" onClick={() => cancelMutation.mutate(f.id)}>
                            <IconX size={16} />
                          </ActionIcon>
                        </Tooltip>
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Overdue Follow-ups */}
      {(dashboard?.overdue_followups.length ?? 0) > 0 && (
        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="sm">
            <IconAlertTriangle size={20} color="var(--mantine-color-red-6)" />
            <Title order={4}>Overdue Follow-ups</Title>
            <Badge color="red" variant="light" size="sm">{dashboard!.overdue_followups.length}</Badge>
          </Group>
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Balance</Table.Th>
                  <Table.Th>Assigned To</Table.Th>
                  <Table.Th>Scheduled</Table.Th>
                  <Table.Th>Calls</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard!.overdue_followups.map((f) => (
                  <Table.Tr key={f.id}>
                    <Table.Td fw={500}>
                      <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${f.client_id}`)} style={{ textTransform: 'uppercase' }}>
                        {f.client_name}
                      </Anchor>
                    </Table.Td>
                    <Table.Td>{f.client_phone || '—'}</Table.Td>
                    <Table.Td>
                      <Anchor size="sm" onClick={() => openPreview(f.document_id)}>
                        {f.document_number}
                      </Anchor>
                    </Table.Td>
                    <Table.Td fw={600} c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                    <Table.Td>{f.assigned_to || '—'}</Table.Td>
                    <Table.Td>
                      <Badge color="red" variant="light" size="sm">
                        {f.next_followup ? formatDate(f.next_followup) : '—'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={f.call_count! >= 3 ? 'red' : 'gray'} variant="light" size="sm">
                        {f.call_count}/3
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label="Log Call">
                        <ActionIcon color="green" variant="light" onClick={() => openLogModal(f)}>
                          <IconPlayerPlay size={16} />
                        </ActionIcon>
                      </Tooltip>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {/* Full History */}
      <Paper withBorder p="md" radius="md">
        <Group justify="space-between" mb="sm">
          <Title order={4}>Follow-up History</Title>
          <Group gap="sm">
            <Select
              size="xs"
              w={130}
              value={filterStatus}
              onChange={(v) => { setFilterStatus(v || 'all'); setPage(1); }}
              data={[
                { value: 'all', label: 'All Status' },
                { value: 'pending', label: 'Pending' },
                { value: 'open', label: 'Open' },
                { value: 'fulfilled', label: 'Fulfilled' },
                { value: 'broken', label: 'Broken' },
                { value: 'escalated', label: 'Escalated' },
                { value: 'cancelled', label: 'Cancelled' },
              ]}
            />
            <Select
              size="xs"
              w={140}
              value={filterOutcome}
              onChange={(v) => { setFilterOutcome(v || 'all'); setPage(1); }}
              data={[
                { value: 'all', label: 'All Outcomes' },
                { value: 'promised', label: 'Promised' },
                { value: 'declined', label: 'Declined' },
                { value: 'no_answer', label: 'No Answer' },
                { value: 'disputed', label: 'Disputed' },
                { value: 'partial_payment', label: 'Partial Payment' },
              ]}
            />
          </Group>
        </Group>

        {histLoading ? (
          <Center py="md"><Loader size="sm" /></Center>
        ) : histError ? (
          <Text c="red" size="sm">Failed to load follow-up history. Please try again.</Text>
        ) : !history?.data?.length ? (
          <Text c="dimmed" size="sm">No follow-up records yet.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Invoice</Table.Th>
                    <Table.Th>Balance</Table.Th>
                    <Table.Th>Assigned / Called By</Table.Th>
                    <Table.Th>Target / Commission</Table.Th>
                    <Table.Th>Outcome</Table.Th>
                    <Table.Th>Promise</Table.Th>
                    <Table.Th>Notes</Table.Th>
                    <Table.Th>Status</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {history.data.map((f: FollowupEntry) => (
                    <Table.Tr key={f.id}>
                      <Table.Td>{f.call_date ? new Date(f.call_date).toLocaleDateString() : '—'}</Table.Td>
                      <Table.Td fw={500}>
                        <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${f.client_id}`)} style={{ textTransform: 'uppercase' }}>
                          {f.client_name}
                        </Anchor>
                      </Table.Td>
                      <Table.Td>
                        <Anchor size="sm" onClick={() => openPreview(f.document_id)}>
                          {f.document_number}
                        </Anchor>
                      </Table.Td>
                      <Table.Td c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                      <Table.Td>{f.assigned_to || '—'}</Table.Td>
                      <Table.Td>
                        {f.assignment ? (
                          <Text size="xs">
                            {formatCurrency(f.assignment.collected)} / {formatCurrency(f.assignment.target)}
                            {f.assignment.commission_type !== 'none' && ` · comm ${formatCurrency(f.assignment.commission_earned)}`}
                          </Text>
                        ) : '—'}
                      </Table.Td>
                      <Table.Td>
                        {f.outcome ? (
                          <Badge color={outcomeColors[f.outcome] || 'gray'} size="sm" variant="light">
                            {f.outcome.replace('_', ' ')}
                          </Badge>
                        ) : '—'}
                      </Table.Td>
                      <Table.Td>
                        {f.promise_date ? (
                          <Text size="xs">
                            {formatDate(f.promise_date)}
                            {f.promise_amount ? ` (${formatCurrency(f.promise_amount)})` : ''}
                          </Text>
                        ) : '—'}
                      </Table.Td>
                      <Table.Td>
                        <Text size="xs" truncate maw={200}>{f.notes || '—'}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Badge color={statusColors[f.status]} size="sm">{f.status}</Badge>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {history.last_page > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={page} onChange={setPage} total={history.last_page} size="sm" />
              </Group>
            )}
          </>
        )}
      </Paper>

          </Stack>
        </Tabs.Panel>
      </Tabs>

      <LogCallModal followup={selectedFollowup} onClose={() => setSelectedFollowup(null)} />

      <Modal opened={assignPickerOpen && !pickDoc} onClose={() => setAssignPickerOpen(false)}
        title="Assign an unpaid invoice to staff" size="md" centered>
        <Stack>
          <Select
            label="Invoice" placeholder="Search invoice number or client" searchable required
            data={pickable.map((d) => ({
              value: d.id,
              label: `${d.document_number} — ${d.client?.name ?? ''} (${formatCurrency(d.balance_due)})`,
            }))}
            onSearchChange={setPickSearch}
            filter={({ options }) => options}
            onChange={(v) => setPickDoc(pickable.find((d) => d.id === v) ?? null)}
            nothingFoundMessage="No unpaid invoices found"
          />
          <Text size="xs" c="dimmed">Only sent, overdue or partially paid invoices can be assigned.</Text>
        </Stack>
      </Modal>
      {pickDoc && (
        <AssignFollowupModal
          opened
          onClose={() => { setPickDoc(null); setAssignPickerOpen(false); }}
          documentId={pickDoc.id}
          documentNumber={pickDoc.document_number}
          clientName={pickDoc.client?.name}
          balance={Number(pickDoc.balance_due)}
        />
      )}

      <CallScriptDrawer
        opened={scriptDrawerOpen}
        onClose={() => setScriptDrawerOpen(false)}
        agentName={agentName}
        defaultSection="section3"
      />

      <Drawer
        opened={!!viewDoc}
        onClose={() => setViewDoc(null)}
        title="Invoice Preview"
        size="xl"
        position="right"
      >
        {viewDoc && (
          <DocumentView
            document={viewDoc}
            onRefresh={handleDocRefresh}
            onClose={() => setViewDoc(null)}
          />
        )}
      </Drawer>
    </Stack>
  );
}

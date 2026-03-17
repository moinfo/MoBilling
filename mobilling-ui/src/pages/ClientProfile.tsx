import { useParams, useNavigate } from 'react-router-dom';
import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, SimpleGrid, Stack,
  Anchor, Loader, Center, ThemeIcon, Modal, Button, TextInput,
  PasswordInput, Select, Switch, ActionIcon, Tooltip,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import {
  IconArrowLeft, IconMail, IconPhone, IconMapPin, IconId,
  IconFileInvoice, IconCash, IconCalendarDue, IconRepeat, IconSend, IconPhoneCall,
  IconHeartHandshake, IconUserPlus, IconEdit, IconTrash, IconShieldLock,
} from '@tabler/icons-react';
import { Rating } from '@mantine/core';
import {
  getClientProfile, ClientProfile as ClientProfileType, ClientCommunicationLog,
  getClientPortalUsers, createClientPortalUser, updateClientPortalUser, deleteClientPortalUser,
  ClientPortalUser,
} from '../api/clients';
import { getClientFollowups, FollowupEntry } from '../api/followups';
import { getClientSatisfactionHistory, SatisfactionCallEntry } from '../api/satisfactionCalls';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

const cycleLabels: Record<string, string> = {
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Semi-Annual',
  yearly: 'Annually',
};

const statusColors: Record<string, string> = {
  active: 'green',
  pending: 'blue',
  cancelled: 'red',
  suspended: 'yellow',
  sent: 'blue',
  paid: 'green',
  overdue: 'red',
  draft: 'gray',
  partially_paid: 'yellow',
  scheduled: 'blue',
  completed: 'green',
  missed: 'red',
};

const outcomeColors: Record<string, string> = {
  satisfied: 'green',
  needs_improvement: 'orange',
  complaint: 'red',
  suggestion: 'blue',
  no_answer: 'gray',
  unreachable: 'dark',
};

const outcomeLabels: Record<string, string> = {
  satisfied: 'Satisfied',
  needs_improvement: 'Needs Improvement',
  complaint: 'Complaint',
  suggestion: 'Suggestion',
  no_answer: 'No Answer',
  unreachable: 'Unreachable',
};

export default function ClientProfile() {
  const { clientId } = useParams<{ clientId: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();

  const { data, isLoading } = useQuery({
    queryKey: ['client-profile', clientId],
    queryFn: () => getClientProfile(clientId!),
    enabled: !!clientId,
  });

  const { data: followupData } = useQuery({
    queryKey: ['client-followups', clientId],
    queryFn: () => getClientFollowups(clientId!),
    enabled: !!clientId,
  });

  const { data: satisfactionData } = useQuery({
    queryKey: ['client-satisfaction-history', clientId],
    queryFn: () => getClientSatisfactionHistory(clientId!),
    enabled: !!clientId,
  });

  const clientFollowups: FollowupEntry[] = followupData?.data?.data ?? [];
  const clientSatisfaction: SatisfactionCallEntry[] = satisfactionData?.data?.data ?? [];
  const [selectedLog, setSelectedLog] = useState<ClientCommunicationLog | null>(null);

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  const profile: ClientProfileType | undefined = data?.data?.data;
  if (!profile) {
    return <Text c="dimmed" ta="center" py="xl">Client not found.</Text>;
  }

  const { client, summary, subscriptions, invoices, payments, communication_logs } = profile;

  return (
    <Stack gap="lg">
      {/* Header */}
      <Group>
        <Anchor onClick={() => navigate('/clients')} c="dimmed" size="sm" style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <IconArrowLeft size={14} /> Back to Clients
        </Anchor>
      </Group>

      <Group justify="space-between" align="flex-start" wrap="wrap">
        <div>
          <Title order={2}>{client.name}</Title>
          <Group gap="md" mt={4}>
            {client.email && (
              <Group gap={4}><IconMail size={14} color="gray" /><Text size="sm" c="dimmed">{client.email}</Text></Group>
            )}
            {client.phone && (
              <Group gap={4}><IconPhone size={14} color="gray" /><Text size="sm" c="dimmed">{client.phone}</Text></Group>
            )}
            {client.tax_id && (
              <Group gap={4}><IconId size={14} color="gray" /><Text size="sm" c="dimmed">{client.tax_id}</Text></Group>
            )}
          </Group>
          {client.address && (
            <Group gap={4} mt={2}><IconMapPin size={14} color="gray" /><Text size="sm" c="dimmed">{client.address}</Text></Group>
          )}
        </div>
      </Group>

      {/* Summary Cards */}
      <SimpleGrid cols={{ base: 2, sm: 5 }}>
        {can('client_profile.total_invoiced') && (
          <SummaryCard icon={<IconFileInvoice size={20} />} label="Total Invoiced" value={formatCurrency(summary.total_invoiced)} color="blue" />
        )}
        {can('client_profile.total_paid') && (
          <SummaryCard icon={<IconCash size={20} />} label="Total Paid" value={formatCurrency(summary.total_paid)} color="green" />
        )}
        {can('client_profile.balance_due') && (
          <SummaryCard icon={<IconCalendarDue size={20} />} label="Balance Due" value={formatCurrency(summary.balance)} color={summary.balance > 0 ? 'red' : 'green'} />
        )}
        {can('client_profile.active_subscriptions') && (
          <SummaryCard icon={<IconRepeat size={20} />} label="Active Subscriptions" value={String(summary.active_subscriptions)} color="violet" />
        )}
        {can('client_profile.subscription_value') && (
          <SummaryCard icon={<IconRepeat size={20} />} label="Subscription Value" value={formatCurrency(summary.total_subscription_value)} color="cyan" />
        )}
      </SimpleGrid>

      {/* Subscriptions */}
      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Subscriptions</Title>
        {subscriptions.length === 0 ? (
          <Text c="dimmed" size="sm">No subscriptions.</Text>
        ) : (
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Product / Service</Table.Th>
                  <Table.Th>Cycle</Table.Th>
                  <Table.Th>Qty</Table.Th>
                  {can('client_profile.subscription_price') && <Table.Th>Price</Table.Th>}
                  <Table.Th>Start</Table.Th>
                  <Table.Th>Next Due</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {subscriptions.map((sub) => (
                  <Table.Tr key={sub.id}>
                    <Table.Td>
                      <Text size="sm" fw={500}>{sub.product_service_name}</Text>
                      {sub.label && <Text size="xs" c="dimmed">{sub.label}</Text>}
                    </Table.Td>
                    <Table.Td>
                      <Badge variant="light" size="sm">{cycleLabels[sub.billing_cycle] || sub.billing_cycle}</Badge>
                    </Table.Td>
                    <Table.Td>{sub.quantity}</Table.Td>
                    {can('client_profile.subscription_price') && <Table.Td>{formatCurrency(sub.price)}</Table.Td>}
                    <Table.Td>{formatDate(sub.start_date)}</Table.Td>
                    <Table.Td fw={500}>{sub.next_bill ? formatDate(sub.next_bill) : '—'}</Table.Td>
                    <Table.Td>
                      <Badge color={statusColors[sub.status] || 'gray'} size="sm">{sub.status}</Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Invoices */}
      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Invoices</Title>
        {invoices.length === 0 ? (
          <Text c="dimmed" size="sm">No invoices yet.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Invoice #</Table.Th>
                  <Table.Th>Description</Table.Th>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Due Date</Table.Th>
                  {can('client_profile.total_invoiced') && <Table.Th>Total</Table.Th>}
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {invoices.map((inv) => (
                  <Table.Tr key={inv.id} style={{ cursor: 'pointer' }} onClick={() => navigate(`/invoices?preview=${inv.id}`)}>
                    <Table.Td fw={500} c="blue">{inv.document_number}</Table.Td>
                    <Table.Td c="dimmed" maw={200} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {inv.description || '—'}
                    </Table.Td>
                    <Table.Td>{formatDate(inv.date)}</Table.Td>
                    <Table.Td>{inv.due_date ? formatDate(inv.due_date) : '—'}</Table.Td>
                    {can('client_profile.total_invoiced') && <Table.Td>{formatCurrency(inv.total)}</Table.Td>}
                    <Table.Td>
                      <Badge color={statusColors[inv.status] || 'gray'} size="sm">{inv.status}</Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Payments */}
      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Payments</Title>
        {payments.length === 0 ? (
          <Text c="dimmed" size="sm">No payments recorded.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Amount</Table.Th>
                  <Table.Th>Method</Table.Th>
                  <Table.Th>Reference</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {payments.map((p) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                    <Table.Td fw={500}>{formatCurrency(p.amount)}</Table.Td>
                    <Table.Td>{p.payment_method || '—'}</Table.Td>
                    <Table.Td>{p.reference || '—'}</Table.Td>
                    <Table.Td>{p.document_number || '—'}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Follow-up History */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconPhoneCall size={20} />
          <Title order={4}>Follow-up Calls</Title>
          {clientFollowups.length > 0 && (
            <Badge variant="light" size="sm">{clientFollowups.length}</Badge>
          )}
        </Group>
        {clientFollowups.length === 0 ? (
          <Text c="dimmed" size="sm">No follow-up calls recorded for this client.</Text>
        ) : (
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Called By</Table.Th>
                  <Table.Th>Outcome</Table.Th>
                  <Table.Th>Promise</Table.Th>
                  <Table.Th>Notes</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {clientFollowups.map((f) => (
                  <Table.Tr key={f.id}>
                    <Table.Td>{f.call_date ? new Date(f.call_date).toLocaleDateString() : '—'}</Table.Td>
                    <Table.Td fw={500}>{f.document_number || '—'}</Table.Td>
                    <Table.Td>{f.assigned_to || '—'}</Table.Td>
                    <Table.Td>
                      {f.outcome ? (
                        <Badge
                          color={f.outcome === 'promised' ? 'blue' : f.outcome === 'declined' ? 'red' : f.outcome === 'no_answer' ? 'gray' : 'orange'}
                          size="sm"
                          variant="light"
                        >
                          {f.outcome.replace('_', ' ')}
                        </Badge>
                      ) : '—'}
                    </Table.Td>
                    <Table.Td>
                      {f.promise_date ? (
                        <Text size="xs">{formatDate(f.promise_date)}</Text>
                      ) : '—'}
                    </Table.Td>
                    <Table.Td>
                      <Text size="xs" truncate maw={200}>{f.notes || '—'}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge
                        color={f.status === 'fulfilled' ? 'green' : f.status === 'broken' ? 'red' : f.status === 'escalated' ? 'orange' : 'gray'}
                        size="sm"
                      >
                        {f.status}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Satisfaction Calls */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconHeartHandshake size={20} />
          <Title order={4}>Satisfaction Calls</Title>
          {clientSatisfaction.length > 0 && (
            <Badge variant="light" size="sm">{clientSatisfaction.length}</Badge>
          )}
        </Group>
        {clientSatisfaction.length === 0 ? (
          <Text c="dimmed" size="sm">No satisfaction calls recorded for this client.</Text>
        ) : (
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Month</Table.Th>
                  <Table.Th>Outcome</Table.Th>
                  <Table.Th>Rating</Table.Th>
                  <Table.Th>Feedback</Table.Th>
                  <Table.Th>Called By</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {clientSatisfaction.map((s) => (
                  <Table.Tr key={s.id}>
                    <Table.Td fw={500}>{s.month_key}</Table.Td>
                    <Table.Td>
                      {s.outcome ? (
                        <Badge color={outcomeColors[s.outcome] || 'gray'} size="sm" variant="light">
                          {outcomeLabels[s.outcome] || s.outcome}
                        </Badge>
                      ) : '—'}
                    </Table.Td>
                    <Table.Td>
                      {s.rating ? <Rating value={s.rating} readOnly size="xs" /> : '—'}
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label={s.feedback} disabled={!s.feedback} multiline maw={400} withArrow>
                        <Text size="xs" truncate maw={200}>{s.feedback || '—'}</Text>
                      </Tooltip>
                    </Table.Td>
                    <Table.Td>{s.assigned_to || '—'}</Table.Td>
                    <Table.Td>
                      <Badge color={statusColors[s.status] || 'gray'} size="sm">{s.status}</Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Communication Log */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconSend size={20} />
          <Title order={4}>Communications</Title>
        </Group>
        {communication_logs.length === 0 ? (
          <Text c="dimmed" size="sm">No communications sent to this client.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Channel</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Recipient</Table.Th>
                  <Table.Th>Subject / Message</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {communication_logs.map((log) => (
                  <Table.Tr key={log.id} onClick={() => setSelectedLog(log)} style={{ cursor: 'pointer' }}>
                    <Table.Td>{formatDate(log.created_at)}</Table.Td>
                    <Table.Td>
                      <Badge variant="light" color={log.channel === 'email' ? 'blue' : 'green'} size="sm">
                        {log.channel}
                      </Badge>
                    </Table.Td>
                    <Table.Td>{log.type.replace(/_/g, ' ')}</Table.Td>
                    <Table.Td>{log.recipient}</Table.Td>
                    <Table.Td>
                      <Text size="sm" truncate maw={200}>{log.subject || log.message || '—'}</Text>
                      {log.error && <Text size="xs" c="red">{log.error}</Text>}
                    </Table.Td>
                    <Table.Td>
                      <Badge color={log.status === 'sent' ? 'green' : 'red'} size="sm">
                        {log.status}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Portal Users */}
      <PortalUsersSection clientId={clientId!} />

      {/* Communication Detail Modal */}
      <Modal
        opened={!!selectedLog}
        onClose={() => setSelectedLog(null)}
        title={
          <Group gap="sm">
            <Badge variant="light" color={selectedLog?.channel === 'email' ? 'blue' : 'green'}>
              {selectedLog?.channel}
            </Badge>
            <Text fw={600}>{selectedLog?.type.replace(/_/g, ' ')}</Text>
            <Badge color={selectedLog?.status === 'sent' ? 'green' : 'red'} size="sm">
              {selectedLog?.status}
            </Badge>
          </Group>
        }
        size="lg"
      >
        {selectedLog && (
          <Stack gap="md">
            <Group gap="lg">
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Recipient</Text>
                <Text size="sm">{selectedLog.recipient}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Date</Text>
                <Text size="sm">{new Date(selectedLog.created_at).toLocaleString()}</Text>
              </div>
            </Group>

            {selectedLog.subject && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Subject</Text>
                <Paper p="sm" radius="sm" bg="var(--mantine-color-default)">
                  <Text size="sm">{selectedLog.subject}</Text>
                </Paper>
              </div>
            )}

            {selectedLog.message && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Message</Text>
                <Paper p="sm" radius="sm" bg="var(--mantine-color-default)">
                  <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{selectedLog.message}</Text>
                </Paper>
              </div>
            )}

            {selectedLog.error && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Error</Text>
                <Paper p="sm" radius="sm" bg="var(--mantine-color-red-light)">
                  <Text size="sm" c="red">{selectedLog.error}</Text>
                </Paper>
              </div>
            )}
          </Stack>
        )}
      </Modal>
    </Stack>
  );
}

function PortalUsersSection({ clientId }: { clientId: string }) {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<ClientPortalUser | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['client-portal-users', clientId],
    queryFn: () => getClientPortalUsers(clientId),
  });

  const users = data?.data?.data || [];

  const form = useForm({
    initialValues: { name: '', email: '', password: '', phone: '', role: 'viewer' },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Invalid email'),
      password: (v) => {
        if (editing) return null;
        return v.length >= 8 ? null : 'Min 8 characters';
      },
    },
  });

  const createMut = useMutation({
    mutationFn: (data: any) => createClientPortalUser(clientId, data),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Portal user created', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['client-portal-users', clientId] });
      closeModal();
    },
    onError: (err: any) => {
      notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed', color: 'red' });
    },
  });

  const updateMut = useMutation({
    mutationFn: ({ id, data }: { id: string; data: any }) => updateClientPortalUser(clientId, id, data),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Portal user updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['client-portal-users', clientId] });
      closeModal();
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => deleteClientPortalUser(clientId, id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Portal user deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['client-portal-users', clientId] });
    },
  });

  const openCreate = () => {
    setEditing(null);
    form.reset();
    setModalOpen(true);
  };

  const openEdit = (u: ClientPortalUser) => {
    setEditing(u);
    form.setValues({ name: u.name, email: u.email, password: '', phone: u.phone || '', role: u.role });
    setModalOpen(true);
  };

  const closeModal = () => {
    setModalOpen(false);
    setEditing(null);
    form.reset();
  };

  const handleSubmit = (values: typeof form.values) => {
    if (editing) {
      const payload: any = { name: values.name, phone: values.phone, role: values.role };
      if (values.password) payload.password = values.password;
      updateMut.mutate({ id: editing.id, data: payload });
    } else {
      createMut.mutate(values);
    }
  };

  const confirmDelete = (u: ClientPortalUser) => {
    modals.openConfirmModal({
      title: 'Delete Portal User',
      children: <Text size="sm">Delete {u.name} ({u.email})?</Text>,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMut.mutate(u.id),
    });
  };

  const toggleActive = (u: ClientPortalUser) => {
    updateMut.mutate({ id: u.id, data: { is_active: !u.is_active } });
  };

  return (
    <>
      <Paper withBorder p="md" radius="md">
        <Group justify="space-between" mb="sm">
          <Group gap="sm">
            <IconShieldLock size={20} />
            <Title order={4}>Portal Users</Title>
            {users.length > 0 && <Badge variant="light" size="sm">{users.length}</Badge>}
          </Group>
          <Button leftSection={<IconUserPlus size={16} />} size="xs" onClick={openCreate}>
            Add Portal User
          </Button>
        </Group>
        {isLoading ? (
          <Center py="md"><Loader size="sm" /></Center>
        ) : users.length === 0 ? (
          <Text c="dimmed" size="sm">No portal users. Add one to give this client access to the client portal.</Text>
        ) : (
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Email</Table.Th>
                <Table.Th>Role</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Last Login</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {users.map((u) => (
                <Table.Tr key={u.id}>
                  <Table.Td fw={500}>{u.name}</Table.Td>
                  <Table.Td>{u.email}</Table.Td>
                  <Table.Td>
                    <Badge color={u.role === 'admin' ? 'blue' : 'gray'} variant="light" size="sm">{u.role}</Badge>
                  </Table.Td>
                  <Table.Td>
                    <Switch checked={u.is_active} onChange={() => toggleActive(u)} size="xs" label={u.is_active ? 'Active' : 'Inactive'} />
                  </Table.Td>
                  <Table.Td>{u.last_login_at ? formatDate(u.last_login_at) : 'Never'}</Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      <ActionIcon variant="subtle" size="sm" onClick={() => openEdit(u)}><IconEdit size={14} /></ActionIcon>
                      <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmDelete(u)}><IconTrash size={14} /></ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Paper>

      <Modal opened={modalOpen} onClose={closeModal} title={editing ? 'Edit Portal User' : 'Add Portal User'}>
        <form onSubmit={form.onSubmit(handleSubmit)}>
          <Stack gap="sm">
            <TextInput label="Name" required {...form.getInputProps('name')} />
            <TextInput label="Email" required disabled={!!editing} {...form.getInputProps('email')} />
            <PasswordInput
              label={editing ? 'New Password (leave blank to keep)' : 'Password'}
              required={!editing}
              {...form.getInputProps('password')}
            />
            <TextInput label="Phone" {...form.getInputProps('phone')} />
            <Select
              label="Role"
              data={[
                { value: 'admin', label: 'Admin (can manage portal users)' },
                { value: 'viewer', label: 'Viewer (view only)' },
              ]}
              {...form.getInputProps('role')}
            />
            <Button type="submit" loading={createMut.isPending || updateMut.isPending}>
              {editing ? 'Update' : 'Create'}
            </Button>
          </Stack>
        </form>
      </Modal>
    </>
  );
}

function SummaryCard({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: string; color: string }) {
  return (
    <Paper withBorder p="md" radius="md">
      <Group gap="sm">
        <ThemeIcon variant="light" color={color} size="lg" radius="md">
          {icon}
        </ThemeIcon>
        <div>
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>{label}</Text>
          <Text size="lg" fw={700}>{value}</Text>
        </div>
      </Group>
    </Paper>
  );
}

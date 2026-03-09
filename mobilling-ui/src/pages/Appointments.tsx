import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, Stack, Select,
  Loader, Center, SimpleGrid, ThemeIcon, ActionIcon, Tooltip,
  Pagination, Anchor, Menu, Modal, Button, Textarea,
} from '@mantine/core';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconMapPin, IconCalendarEvent, IconClock, IconCheck,
  IconX, IconAlertTriangle, IconDots, IconPhone,
} from '@tabler/icons-react';
import {
  getAppointments, updateAppointment, AppointmentEntry,
} from '../api/satisfactionCalls';
import { formatDate } from '../utils/formatDate';

const statusColors: Record<string, string> = {
  pending: 'orange',
  confirmed: 'blue',
  completed: 'green',
  cancelled: 'gray',
};

const statusLabels: Record<string, string> = {
  pending: 'Pending',
  confirmed: 'Confirmed',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

export default function Appointments() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [updateModal, setUpdateModal] = useState(false);
  const [selectedAppt, setSelectedAppt] = useState<AppointmentEntry | null>(null);
  const [newStatus, setNewStatus] = useState<string>('');
  const [notes, setNotes] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['appointments', filterStatus, page],
    queryFn: () => getAppointments({
      status: filterStatus,
      page: String(page),
      per_page: '20',
    }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data: d }: { id: string; data: { appointment_status: string; appointment_notes?: string } }) =>
      updateAppointment(id, d),
    onSuccess: (res) => {
      notifications.show({ title: 'Updated', message: res.data.message, color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['appointments'] });
      queryClient.invalidateQueries({ queryKey: ['satisfaction-dashboard'] });
      closeModal();
    },
    onError: () => {
      notifications.show({ title: 'Error', message: 'Failed to update appointment.', color: 'red' });
    },
  });

  const openUpdateModal = (appt: AppointmentEntry, status: string) => {
    setSelectedAppt(appt);
    setNewStatus(status);
    setNotes(appt.appointment_notes || '');
    setUpdateModal(true);
  };

  const closeModal = () => {
    setUpdateModal(false);
    setSelectedAppt(null);
    setNewStatus('');
    setNotes('');
  };

  const handleUpdate = () => {
    if (!selectedAppt || !newStatus) return;
    updateMutation.mutate({
      id: selectedAppt.id,
      data: { appointment_status: newStatus, appointment_notes: notes || undefined },
    });
  };

  const result = data?.data;
  const appointments: AppointmentEntry[] = result?.data ?? [];
  const meta = result?.meta;
  const stats = result?.stats;

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  const today = new Date().toISOString().split('T')[0];

  return (
    <Stack gap="lg">
      <Title order={2}>Client Appointments</Title>

      {/* Stats */}
      <SimpleGrid cols={{ base: 2, xs: 3, sm: 6 }}>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md">
              <IconCalendarEvent size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Today</Text>
              <Text size="xl" fw={700}>{stats?.today ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="cyan" size="lg" radius="md">
              <IconClock size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Upcoming</Text>
              <Text size="xl" fw={700}>{stats?.upcoming ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="red" size="lg" radius="md">
              <IconAlertTriangle size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Overdue</Text>
              <Text size="xl" fw={700} c={stats?.overdue ? 'red' : undefined}>{stats?.overdue ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="orange" size="lg" radius="md">
              <IconMapPin size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Pending</Text>
              <Text size="xl" fw={700}>{stats?.pending ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md">
              <IconCheck size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Confirmed</Text>
              <Text size="xl" fw={700}>{stats?.confirmed ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="green" size="lg" radius="md">
              <IconCheck size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Completed</Text>
              <Text size="xl" fw={700}>{stats?.completed ?? 0}</Text>
            </div>
          </Group>
        </Paper>
      </SimpleGrid>

      {/* Appointments List */}
      <Paper withBorder p="md" radius="md">
        <Group justify="space-between" mb="sm">
          <Group gap="sm">
            <IconMapPin size={20} />
            <Title order={4}>Visit Schedule</Title>
          </Group>
          <Select
            size="xs"
            w={140}
            value={filterStatus}
            onChange={(v) => { setFilterStatus(v || 'all'); setPage(1); }}
            data={[
              { value: 'all', label: 'All Status' },
              { value: 'pending', label: 'Pending' },
              { value: 'confirmed', label: 'Confirmed' },
              { value: 'completed', label: 'Completed' },
              { value: 'cancelled', label: 'Cancelled' },
            ]}
          />
        </Group>

        {appointments.length === 0 ? (
          <Text c="dimmed" size="sm">No appointments found.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Phone</Table.Th>
                    <Table.Th>Address</Table.Th>
                    <Table.Th>Assigned To</Table.Th>
                    <Table.Th>Notes</Table.Th>
                    <Table.Th>Call Outcome</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Action</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {appointments.map((a) => {
                    const isOverdue = a.appointment_date && a.appointment_date < today
                      && (a.appointment_status === 'pending' || a.appointment_status === 'confirmed');
                    const isToday = a.appointment_date === today;
                    return (
                      <Table.Tr key={a.id} bg={isOverdue ? 'var(--mantine-color-red-light)' : isToday ? 'var(--mantine-color-blue-light)' : undefined}>
                        <Table.Td>
                          <Group gap={6} wrap="nowrap">
                            <Text size="sm" fw={500}>
                              {a.appointment_date ? formatDate(a.appointment_date) : 'TBD'}
                            </Text>
                            {isToday && <Badge size="xs" color="blue" variant="filled">Today</Badge>}
                            {isOverdue && <Badge size="xs" color="red" variant="filled">Overdue</Badge>}
                          </Group>
                        </Table.Td>
                        <Table.Td>
                          <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${a.client_id}`)} style={{ textTransform: 'uppercase' }}>
                            {a.client_name}
                          </Anchor>
                        </Table.Td>
                        <Table.Td>
                          {a.client_phone ? (
                            <Anchor size="sm" href={`tel:${a.client_phone}`}>
                              <Group gap={4} wrap="nowrap">
                                <IconPhone size={14} />
                                {a.client_phone}
                              </Group>
                            </Anchor>
                          ) : '—'}
                        </Table.Td>
                        <Table.Td>
                          <Text size="xs" maw={180} truncate>{a.client_address || '—'}</Text>
                        </Table.Td>
                        <Table.Td>{a.assigned_to || '—'}</Table.Td>
                        <Table.Td>
                          <Text size="xs" maw={200} truncate>{a.appointment_notes || '—'}</Text>
                        </Table.Td>
                        <Table.Td>
                          {a.outcome ? (
                            <Badge size="sm" variant="light" color={a.outcome === 'satisfied' ? 'green' : a.outcome === 'complaint' ? 'red' : 'gray'}>
                              {a.outcome.replace('_', ' ')}
                            </Badge>
                          ) : '—'}
                        </Table.Td>
                        <Table.Td>
                          <Badge color={statusColors[a.appointment_status || ''] || 'gray'} size="sm">
                            {statusLabels[a.appointment_status || ''] || a.appointment_status || '—'}
                          </Badge>
                        </Table.Td>
                        <Table.Td>
                          {a.appointment_status !== 'completed' && a.appointment_status !== 'cancelled' && (
                            <Menu shadow="md" width={160}>
                              <Menu.Target>
                                <ActionIcon variant="light" color="gray">
                                  <IconDots size={16} />
                                </ActionIcon>
                              </Menu.Target>
                              <Menu.Dropdown>
                                {a.appointment_status === 'pending' && (
                                  <Menu.Item leftSection={<IconCheck size={14} />} onClick={() => openUpdateModal(a, 'confirmed')}>
                                    Confirm
                                  </Menu.Item>
                                )}
                                <Menu.Item leftSection={<IconCheck size={14} />} color="green" onClick={() => openUpdateModal(a, 'completed')}>
                                  Mark Completed
                                </Menu.Item>
                                <Menu.Item leftSection={<IconX size={14} />} color="red" onClick={() => openUpdateModal(a, 'cancelled')}>
                                  Cancel
                                </Menu.Item>
                              </Menu.Dropdown>
                            </Menu>
                          )}
                        </Table.Td>
                      </Table.Tr>
                    );
                  })}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {meta && meta.last_page > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={page} onChange={setPage} total={meta.last_page} size="sm" />
              </Group>
            )}
          </>
        )}
      </Paper>

      {/* Update Status Modal */}
      <Modal opened={updateModal} onClose={closeModal} title="Update Appointment" size="md">
        {selectedAppt && (
          <Stack gap="md">
            <Paper p="sm" radius="sm" bg="var(--mantine-color-default)">
              <Group justify="space-between">
                <div>
                  <Text size="xs" c="dimmed">Client</Text>
                  <Text fw={600}>{selectedAppt.client_name}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Date</Text>
                  <Text fw={600}>{selectedAppt.appointment_date ? formatDate(selectedAppt.appointment_date) : 'TBD'}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">New Status</Text>
                  <Badge color={statusColors[newStatus] || 'gray'} size="lg">
                    {statusLabels[newStatus] || newStatus}
                  </Badge>
                </div>
              </Group>
            </Paper>
            <Textarea
              label="Notes"
              placeholder="Visit notes, observations, next steps..."
              value={notes}
              onChange={(e) => setNotes(e.currentTarget.value)}
              minRows={3}
            />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeModal}>Cancel</Button>
              <Button
                color={newStatus === 'cancelled' ? 'red' : 'green'}
                onClick={handleUpdate}
                loading={updateMutation.isPending}
              >
                {newStatus === 'cancelled' ? 'Cancel Appointment' : newStatus === 'completed' ? 'Mark Completed' : 'Confirm'}
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>
    </Stack>
  );
}

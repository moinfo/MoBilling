import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Table, Badge, LoadingOverlay, Button, Group, Text,
  SegmentedControl, TextInput,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { IconMessageCircle, IconPlus, IconSearch } from '@tabler/icons-react';
import { getPortalTickets, PortalTicket } from '../../api/portal';
import dayjs from 'dayjs';

export const TICKET_STATUS_META: Record<string, { label: string; color: string }> = {
  open:           { label: 'Open',           color: 'green' },
  answered:       { label: 'Answered',       color: 'blue' },
  customer_reply: { label: 'Customer-Reply', color: 'orange' },
  closed:         { label: 'Closed',         color: 'gray' },
};

export const TICKET_DEPARTMENTS = [
  { value: 'support', label: 'Technical Support' },
  { value: 'billing', label: 'Billing' },
  { value: 'sales', label: 'Sales' },
];

export const departmentLabel = (v: string | null | undefined) =>
  TICKET_DEPARTMENTS.find((d) => d.value === v)?.label ?? 'Technical Support';

const priorityColor: Record<string, string> = { low: 'gray', medium: 'blue', high: 'red' };

export default function PortalTickets() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [statusFilter, setStatusFilter] = useState('active');
  const [search, setSearch] = useState('');

  // Deep link: /portal/tickets?new=1 → the open-ticket page
  useEffect(() => {
    if (searchParams.get('new')) {
      setSearchParams({}, { replace: true });
      navigate('/portal/tickets/new');
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const { data, isLoading } = useQuery({ queryKey: ['portal-tickets'], queryFn: getPortalTickets });
  const tickets: PortalTicket[] = data?.data?.data ?? [];

  const counts = {
    active: tickets.filter((t) => t.status !== 'closed').length,
    awaiting: tickets.filter((t) => t.status === 'answered').length,
    closed: tickets.filter((t) => t.status === 'closed').length,
  };

  const filtered = tickets.filter((t) => {
    if (statusFilter === 'active' && t.status === 'closed') return false;
    if (statusFilter === 'awaiting' && t.status !== 'answered') return false;
    if (statusFilter === 'closed' && t.status !== 'closed') return false;
    if (search && !`${t.ticket_number} ${t.subject}`.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Group gap="xs">
          <IconMessageCircle size={22} />
          <Title order={3}>Support Tickets</Title>
        </Group>
        <Button leftSection={<IconPlus size={16} />} onClick={() => navigate('/portal/tickets/new')}>
          Open New Ticket
        </Button>
      </Group>

      <Group gap="sm" wrap="wrap">
        <SegmentedControl size="xs" value={statusFilter} onChange={setStatusFilter}
          data={[
            { label: `Active (${counts.active})`, value: 'active' },
            { label: `Awaiting Your Reply (${counts.awaiting})`, value: 'awaiting' },
            { label: `Closed (${counts.closed})`, value: 'closed' },
            { label: 'All', value: 'all' },
          ]} />
        <TextInput size="xs" placeholder="Search tickets…" leftSection={<IconSearch size={13} />}
          value={search} onChange={(e) => setSearch(e.currentTarget.value)} w={220} />
      </Group>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={720}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>#</Table.Th>
                <Table.Th>Subject</Table.Th>
                <Table.Th>Department</Table.Th>
                <Table.Th>Priority</Table.Th>
                <Table.Th>Last Updated</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.length === 0 && (
                <Table.Tr><Table.Td colSpan={6}>
                  <Text c="dimmed" ta="center" py="md" size="sm">
                    {tickets.length === 0 ? 'No tickets yet — open one if you need help.' : 'No tickets match this filter.'}
                  </Text>
                </Table.Td></Table.Tr>
              )}
              {filtered.map((t) => (
                <Table.Tr key={t.id} style={{ cursor: 'pointer' }} onClick={() => navigate(`/portal/tickets/${t.id}`)}>
                  <Table.Td><Text size="sm" fw={600}>{t.ticket_number}</Text></Table.Td>
                  <Table.Td>
                    <Text size="sm" fw={500}>{t.subject}</Text>
                    {t.related_service && <Text size="xs" c="dimmed">{t.related_service}</Text>}
                  </Table.Td>
                  <Table.Td><Text size="sm">{departmentLabel(t.department)}</Text></Table.Td>
                  <Table.Td>
                    <Badge size="xs" variant="light" color={priorityColor[t.priority] ?? 'gray'}>{t.priority}</Badge>
                  </Table.Td>
                  <Table.Td>
                    <Text size="xs" c="dimmed">
                      {t.last_reply_at ? dayjs(t.last_reply_at).format('ddd, D MMM YYYY HH:mm') : '—'}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge size="sm" color={TICKET_STATUS_META[t.status]?.color ?? 'gray'} variant="filled" radius="xl">
                      {TICKET_STATUS_META[t.status]?.label ?? t.status}
                    </Badge>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}

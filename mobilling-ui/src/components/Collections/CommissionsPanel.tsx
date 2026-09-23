import { useState } from 'react';
import { Paper, Group, Stack, Text, Table, Badge, Select, Button, Checkbox, SimpleGrid, Loader, Center, Anchor } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import dayjs from 'dayjs';
import { getCollectionAssignments, markCommissionPaid } from '../../api/followups';
import { getAssignableUsers } from '../../api/users';
import { usePermissions } from '../../hooks/usePermissions';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

const statusColor: Record<string, string> = { active: 'blue', completed: 'green', cancelled: 'gray' };

export default function CommissionsPanel({ onOpenInvoice }: { onOpenInvoice: (id: string) => void }) {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const canPay = can('staff_targets.manage');
  const [userId, setUserId] = useState<string | null>(null);
  const [status, setStatus] = useState<string>('all');
  const [payout, setPayout] = useState<string>('all');
  const [from, setFrom] = useState<string | null>(null);
  const [to, setTo] = useState<string | null>(null);
  const [selected, setSelected] = useState<string[]>([]);

  const params: Record<string, string> = { status, payout };
  if (userId) params.user_id = userId;
  if (from) params.date_from = dayjs(from).format('YYYY-MM-DD');
  if (to) params.date_to = dayjs(to).format('YYYY-MM-DD');

  const { data: usersRes } = useQuery({ queryKey: ['assignable-users'], queryFn: getAssignableUsers });
  const staffOptions = (usersRes?.data?.data ?? []).map((u) => ({ value: u.id, label: u.name }));
  const q = useQuery({ queryKey: ['collection-assignments', params], queryFn: () => getCollectionAssignments(params) });
  const rows = q.data?.data?.data ?? [];
  const sum = q.data?.data?.summary;

  const payMut = useMutation({
    mutationFn: (ids: string[]) => markCommissionPaid(ids),
    onSuccess: (res) => {
      notifications.show({ title: 'Done', message: res.data.message, color: 'green' });
      setSelected([]);
      qc.invalidateQueries({ queryKey: ['collection-assignments'] });
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed.', color: 'red' }),
  });

  const payable = rows.filter((r) => !r.paid_out_at && r.status !== 'cancelled' && r.commission_earned > 0);
  const allSelected = payable.length > 0 && payable.every((r) => selected.includes(r.id));

  const stat = (label: string, v: number, color?: string) => (
    <Paper withBorder p="md" radius="md"><Text size="xs" c="dimmed" tt="uppercase" fw={600}>{label}</Text><Text size="xl" fw={700} c={color}>{formatCurrency(v)}</Text></Paper>
  );

  return (
    <Stack gap="md">
      <SimpleGrid cols={{ base: 2, sm: 4 }}>
        {stat('Total target', sum?.target ?? 0)}
        {stat('Collected', sum?.collected ?? 0)}
        {stat('Commission earned', sum?.commission_earned ?? 0, 'green')}
        {stat('Commission unpaid', sum?.commission_unpaid ?? 0, 'orange')}
      </SimpleGrid>
      <Paper withBorder p="md" radius="md">
        <Group mb="sm" align="flex-end">
          <Select label="Staff" placeholder="All" clearable searchable data={staffOptions} value={userId} onChange={setUserId} w={180} />
          <Select label="Status" value={status} onChange={(v) => setStatus(v || 'all')} w={130} allowDeselect={false}
            data={[{ value: 'all', label: 'All' }, { value: 'active', label: 'Active' }, { value: 'completed', label: 'Completed' }, { value: 'cancelled', label: 'Cancelled' }]} />
          <Select label="Payout" value={payout} onChange={(v) => setPayout(v || 'all')} w={120} allowDeselect={false}
            data={[{ value: 'all', label: 'All' }, { value: 'unpaid', label: 'Unpaid' }, { value: 'paid', label: 'Paid' }]} />
          <DateInput label="From" clearable value={from} onChange={setFrom} w={140} />
          <DateInput label="To" clearable value={to} onChange={setTo} w={140} />
          {canPay && (
            <Button color="green" disabled={!selected.length} loading={payMut.isPending} onClick={() => payMut.mutate(selected)}>
              Mark commission paid ({selected.length})
            </Button>
          )}
        </Group>
        {q.isLoading ? <Center py="md"><Loader size="sm" /></Center> : !rows.length ? (
          <Text c="dimmed" size="sm">No collection assignments found.</Text>
        ) : (
          <Table.ScrollContainer minWidth={900}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  {canPay && <Table.Th w={30}><Checkbox size="xs" checked={allSelected} onChange={(e) => setSelected(e.currentTarget.checked ? payable.map((r) => r.id) : [])} /></Table.Th>}
                  <Table.Th>Staff</Table.Th><Table.Th>Invoice</Table.Th><Table.Th>Target</Table.Th><Table.Th>Collected</Table.Th>
                  <Table.Th>Remaining</Table.Th><Table.Th>Commission</Table.Th><Table.Th>Earned</Table.Th><Table.Th>Status</Table.Th><Table.Th>Payout</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r) => (
                  <Table.Tr key={r.id}>
                    {canPay && <Table.Td><Checkbox size="xs" disabled={!payable.includes(r)} checked={selected.includes(r.id)}
                      onChange={(e) => setSelected((s) => e.currentTarget.checked ? [...s, r.id] : s.filter((x) => x !== r.id))} /></Table.Td>}
                    <Table.Td>{r.user_name}</Table.Td>
                    <Table.Td><Anchor size="sm" onClick={() => onOpenInvoice(r.document_id)}>{r.document_number}</Anchor><Text size="xs" c="dimmed">{r.client_name}</Text></Table.Td>
                    <Table.Td>{formatCurrency(r.target)}</Table.Td>
                    <Table.Td>{formatCurrency(r.collected)}</Table.Td>
                    <Table.Td>{formatCurrency(r.remaining)}</Table.Td>
                    <Table.Td>{r.commission_type === 'none' ? '—' : r.commission_type === 'percentage' ? `${r.commission_value}%` : `${formatCurrency(r.commission_value)} fixed`}</Table.Td>
                    <Table.Td fw={600} c="green">{formatCurrency(r.commission_earned)}</Table.Td>
                    <Table.Td><Badge size="sm" variant="light" color={statusColor[r.status]}>{r.status}</Badge></Table.Td>
                    <Table.Td>{r.commission_earned <= 0 ? '—' : r.paid_out_at ? <Badge size="sm" color="green">Paid {formatDate(r.paid_out_at)}</Badge> : <Badge size="sm" color="orange" variant="light">Unpaid</Badge>}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
        <Text size="xs" c="dimmed" mt="xs">Commission is an accrual calculated from payments received after assignment; the actual payout is done outside the system.</Text>
      </Paper>
    </Stack>
  );
}

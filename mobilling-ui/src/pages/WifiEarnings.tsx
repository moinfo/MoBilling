import { useState } from 'react';
import {
  Title, Text, Paper, Stack, Group, Table, Badge, Button, Select, SimpleGrid, Pagination,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation } from '@tanstack/react-query';
import { IconCash, IconCheck } from '@tabler/icons-react';
import { getWifiEarnings, getWifiEarningsSummary, requestWifiPayout, WifiEarningRow } from '../api/wifiEarnings';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

export default function WifiEarnings() {
  const [page, setPage] = useState(1);
  const [filterSettled, setFilterSettled] = useState<string | null>(null);

  const { data: summaryData } = useQuery({
    queryKey: ['wifi-earnings-summary'],
    queryFn: getWifiEarningsSummary,
  });
  const summary = summaryData?.data?.data;

  const { data } = useQuery({
    queryKey: ['wifi-earnings', page, filterSettled],
    queryFn: () => getWifiEarnings({
      page,
      settled: filterSettled === null ? undefined : filterSettled === 'true',
    }),
  });
  const items: WifiEarningRow[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const payoutMutation = useMutation({
    mutationFn: requestWifiPayout,
    onSuccess: (res) => {
      notifications.show({ title: 'Sent', message: res.data.message, color: 'green', icon: <IconCheck size={16} /> });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to send request', color: 'red' }),
  });

  return (
    <Stack gap="lg">
      <div>
        <Title order={2} mb={4}>WiFi Earnings</Title>
        <Text c="dimmed">Money MoBilling collected on your behalf for platform-collected WiFi voucher sales.</Text>
      </div>

      <SimpleGrid cols={{ base: 1, sm: 2 }}>
        <Paper withBorder p="md" radius="md">
          <Text size="sm" c="dimmed">Owed to you</Text>
          <Text size="xl" fw={800} c="orange">{formatCurrency(summary?.owed ?? 0)}</Text>
          <Text size="xs" c="dimmed">{summary?.unsettled_count ?? 0} unsettled sale{(summary?.unsettled_count ?? 0) === 1 ? '' : 's'}</Text>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group justify="space-between" align="center" h="100%">
            <div>
              <Text size="sm" c="dimmed">Already paid out</Text>
              <Text size="xl" fw={800} c="green">{formatCurrency(summary?.total_settled ?? 0)}</Text>
            </div>
            <Button leftSection={<IconCash size={16} />} loading={payoutMutation.isPending}
              disabled={!summary?.owed} onClick={() => payoutMutation.mutate()}>
              Request Payout
            </Button>
          </Group>
        </Paper>
      </SimpleGrid>

      <Group>
        <Select placeholder="All" data={[{ value: 'false', label: 'Unsettled' }, { value: 'true', label: 'Settled' }]}
          clearable value={filterSettled} onChange={(v) => { setFilterSettled(v); setPage(1); }} maw={160} />
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No platform-collected voucher sales yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Router</Table.Th>
                <Table.Th>Phone</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Commission</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Owed</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((r) => (
                <Table.Tr key={r.id}>
                  <Table.Td>{r.completed_at ? formatDate(r.completed_at) : '—'}</Table.Td>
                  <Table.Td>{r.router?.name || '—'}</Table.Td>
                  <Table.Td>{r.customer_phone}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(r.amount)}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }} c="dimmed">−{formatCurrency(r.commission_amount ?? 0)}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }} fw={600}>{formatCurrency(r.net_amount ?? 0)}</Table.Td>
                  <Table.Td>
                    {r.settled_at ? (
                      <Badge size="sm" variant="light" color="green" leftSection={<IconCheck size={10} />}>Paid</Badge>
                    ) : (
                      <Badge size="sm" variant="light" color="orange">Owed</Badge>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}
    </Stack>
  );
}

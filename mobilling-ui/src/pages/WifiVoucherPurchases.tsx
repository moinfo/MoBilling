import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, TextInput, Select, Code } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { useDebouncedValue } from '@mantine/hooks';
import { IconSearch } from '@tabler/icons-react';
import { getWifiVoucherPurchases, WifiVoucherPurchase } from '../api/wifiVoucherPurchases';
import { getMikrotikRouters, MikrotikRouter } from '../api/mikrotikRouters';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const STATUS_COLOR: Record<string, string> = { pending: 'blue', completed: 'green', failed: 'red' };

const STATUS_OPTIONS = [
  { value: 'pending', label: 'Pending' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
];

export default function WifiVoucherPurchases() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [filterRouter, setFilterRouter] = useState<string | null>(null);
  const [filterStatus, setFilterStatus] = useState<string | null>(null);

  const { data: routersData } = useQuery({
    queryKey: ['mikrotik-routers-all'],
    queryFn: () => getMikrotikRouters({ per_page: 200 }),
  });
  const routers: MikrotikRouter[] = routersData?.data?.data || [];
  const routerOptions = routers.map((r) => ({ value: r.id, label: r.name }));

  const { data } = useQuery({
    queryKey: ['wifi-voucher-purchases', page, debouncedSearch, filterRouter, filterStatus],
    queryFn: () => getWifiVoucherPurchases({
      page,
      search: debouncedSearch || undefined,
      mikrotik_router_id: filterRouter || undefined,
      status: filterStatus || undefined,
    }),
  });
  const items: WifiVoucherPurchase[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>WiFi Voucher Sales</Title>
        <Group wrap="wrap">
          <TextInput placeholder="Search by phone..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={220} />
          <Select placeholder="All routers" data={routerOptions} clearable searchable
            value={filterRouter} onChange={(v) => { setFilterRouter(v); setPage(1); }} maw={200} />
          <Select placeholder="All statuses" data={STATUS_OPTIONS} clearable
            value={filterStatus} onChange={(v) => { setFilterStatus(v); setPage(1); }} maw={160} />
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No voucher sales yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Phone</Table.Th>
                <Table.Th>Router</Table.Th>
                <Table.Th>Plan</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th>Voucher Code</Table.Th>
                <Table.Th>Expires</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((p) => (
                <Table.Tr key={p.id}>
                  <Table.Td>{formatDate(p.created_at)}</Table.Td>
                  <Table.Td>{p.customer_phone}</Table.Td>
                  <Table.Td>{p.router?.name || '—'}</Table.Td>
                  <Table.Td>{p.plan?.name || '—'}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(p.amount)}</Table.Td>
                  <Table.Td>{p.hotspot_username ? <Code fz="sm">{p.hotspot_username}</Code> : '—'}</Table.Td>
                  <Table.Td>{p.voucher_expires_at ? formatDate(p.voucher_expires_at) : '—'}</Table.Td>
                  <Table.Td>
                    <Badge size="sm" variant="light" color={STATUS_COLOR[p.status] ?? 'gray'} tt="capitalize">
                      {p.status}
                    </Badge>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}
    </>
  );
}

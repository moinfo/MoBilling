import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, TextInput, Select } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { useDebouncedValue } from '@mantine/hooks';
import { IconSearch } from '@tabler/icons-react';
import { getRetainerBillings, RetainerBilling as RetainerBillingRow } from '../api/clientSubscriptions';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const STATUS_COLOR: Record<string, string> = { active: 'green', suspended: 'orange', cancelled: 'red' };
const INVOICE_STATUS_COLOR: Record<string, string> = { paid: 'green', sent: 'blue', partial: 'yellow', overdue: 'red', cancelled: 'gray' };

const STATUS_OPTIONS = [
  { value: 'active', label: 'Active' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'cancelled', label: 'Cancelled' },
];

export default function RetainerBilling() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [filterStatus, setFilterStatus] = useState<string | null>(null);

  const { data } = useQuery({
    queryKey: ['retainer-billings', page, debouncedSearch, filterStatus],
    queryFn: () => getRetainerBillings({
      page,
      search: debouncedSearch || undefined,
      status: filterStatus || undefined,
    }),
  });
  const items: RetainerBillingRow[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>Client Billed (Retainer Fees)</Title>
          <Text c="dimmed" size="sm">Contracts invoiced automatically on a fixed calendar day each month — e.g. maintenance & development retainers.</Text>
        </div>
        <Group wrap="wrap">
          <TextInput placeholder="Search client or service..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={240} />
          <Select placeholder="All statuses" data={STATUS_OPTIONS} clearable
            value={filterStatus} onChange={(v) => { setFilterStatus(v); setPage(1); }} maw={160} />
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">
          No retainer contracts yet — set "Fixed Invoice Day of Month" on a Service (Billing → Products & Services) and assign it to a client (Billing → Subscriptions).
        </Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Client</Table.Th>
                <Table.Th>Service</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th>Invoice Day</Table.Th>
                <Table.Th>Last Invoiced</Table.Th>
                <Table.Th>Last Invoice</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((r) => (
                <Table.Tr key={r.id}>
                  <Table.Td fw={500}>{r.client_name || '—'}</Table.Td>
                  <Table.Td>{r.product_service_name || '—'}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }}>{r.price ? formatCurrency(r.price) : '—'}</Table.Td>
                  <Table.Td>Day {r.invoice_day_of_month}</Table.Td>
                  <Table.Td>{r.last_invoiced_at ? formatDate(r.last_invoiced_at) : 'Not yet'}</Table.Td>
                  <Table.Td>
                    {r.last_invoice_status ? (
                      <Group gap={4} wrap="nowrap">
                        <Badge size="sm" variant="light" color={INVOICE_STATUS_COLOR[r.last_invoice_status] ?? 'gray'} tt="capitalize">
                          {r.last_invoice_status}
                        </Badge>
                        {r.last_invoice_due_date && (
                          <Text size="xs" c="dimmed">due {formatDate(r.last_invoice_due_date)}</Text>
                        )}
                      </Group>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </Table.Td>
                  <Table.Td>
                    <Badge size="sm" variant="light" color={STATUS_COLOR[r.status] ?? 'gray'} tt="capitalize">
                      {r.status}
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

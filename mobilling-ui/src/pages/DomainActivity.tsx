import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, Text, Paper, Select,
  TextInput, Loader, Center, Pagination, SimpleGrid, ThemeIcon,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconSearch, IconHistory, IconReceipt2, IconRepeat, IconCoin, IconCurrencyDollar } from '@tabler/icons-react';
import { DateInput } from '@mantine/dates';
import dayjs from 'dayjs';
import { getDomainActivityLog, DomainActivityRow } from '../api/domains';
import { formatCurrency } from '../utils/formatCurrency';

function SummaryCard({ icon, color, label, value }: {
  icon: React.ReactNode; color: string; label: string; value: string | number;
}) {
  return (
    <Paper withBorder radius="md" p="sm">
      <Group gap="xs" wrap="nowrap">
        <ThemeIcon variant="light" color={color} size={36} radius="md">{icon}</ThemeIcon>
        <div>
          <Text size="xs" c="dimmed">{label}</Text>
          <Text fw={700}>{value}</Text>
        </div>
      </Group>
    </Paper>
  );
}

export default function DomainActivity() {
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<'' | 'register' | 'renew'>('');
  const [page, setPage] = useState(1);

  const params: { date_from?: string; date_to?: string; search?: string; type?: 'register' | 'renew'; page: number } = { page };
  if (dateFrom) params.date_from = dateFrom;
  if (dateTo) params.date_to = dateTo;
  if (search) params.search = search;
  if (typeFilter) params.type = typeFilter;

  const { data, isLoading } = useQuery({
    queryKey: ['domain-activity-log', params],
    queryFn: () => getDomainActivityLog(params),
  });
  const rows: DomainActivityRow[] = data?.data?.data?.data ?? [];
  const lastPage: number = data?.data?.data?.last_page ?? 1;
  const summary = data?.data?.summary;

  return (
    <Stack gap="md">
      <Group gap="xs">
        <IconHistory size={22} />
        <Title order={2}>Domain Activity</Title>
      </Group>
      <Text c="dimmed" size="sm" mt={-8}>
        Every domain registered or renewed, by date — cross-check against your registrar topups.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="sm">
        <SummaryCard icon={<IconReceipt2 size={18} />} color="blue" label="Registered"
          value={summary?.count_register ?? '—'} />
        <SummaryCard icon={<IconRepeat size={18} />} color="teal" label="Renewed"
          value={summary?.count_renew ?? '—'} />
        <SummaryCard icon={<IconCoin size={18} />} color="grape" label="Total Billed"
          value={summary ? formatCurrency(summary.total_price) : '—'} />
        <SummaryCard icon={<IconCurrencyDollar size={18} />} color="orange" label="Name.com Paid (USD)"
          value={summary ? `$${summary.total_paid_usd.toLocaleString()}` : '—'} />
      </SimpleGrid>

      <Paper withBorder radius="md" p="md">
        <Group gap="xs" mb="md" wrap="wrap">
          <TextInput size="xs" placeholder="Search domain or client…" leftSection={<IconSearch size={13} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} w={240} />
          <Select size="xs" placeholder="All types" clearable w={160}
            value={typeFilter || null}
            onChange={(v) => { setTypeFilter((v as 'register' | 'renew') ?? ''); setPage(1); }}
            data={[{ value: 'register', label: 'Registered' }, { value: 'renew', label: 'Renewed' }]} />
          <DateInput label="From" size="xs" maw={140} clearable
            value={dateFrom ? new Date(dateFrom) : null}
            onChange={(v) => { setDateFrom(v ? dayjs(v).format('YYYY-MM-DD') : ''); setPage(1); }} />
          <DateInput label="To" size="xs" maw={140} clearable
            value={dateTo ? new Date(dateTo) : null}
            onChange={(v) => { setDateTo(v ? dayjs(v).format('YYYY-MM-DD') : ''); setPage(1); }} />
        </Group>

        {isLoading ? (
          <Center py="md"><Loader size="sm" /></Center>
        ) : rows.length === 0 ? (
          <Text c="dimmed" size="sm">No registrations or renewals in this period.</Text>
        ) : (
          <>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Action</Table.Th>
                  <Table.Th>Years</Table.Th>
                  <Table.Th>Price</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r) => (
                  <Table.Tr key={r.id}>
                    <Table.Td>{dayjs(r.created_at).format('D MMM YYYY HH:mm')}</Table.Td>
                    <Table.Td>{r.domain ?? '—'}</Table.Td>
                    <Table.Td>{r.client ?? '—'}</Table.Td>
                    <Table.Td>
                      <Badge size="xs" color={r.type === 'register' ? 'blue' : 'teal'} variant="light">
                        {r.type === 'register' ? 'Registered' : 'Renewed'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>{r.years ?? '—'}</Table.Td>
                    <Table.Td>
                      {r.price != null ? formatCurrency(r.price) : r.paid_usd != null ? `$${r.paid_usd}` : '—'}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
            {lastPage > 1 && (
              <Group justify="center" mt="sm">
                <Pagination value={page} onChange={setPage} total={lastPage} size="sm" />
              </Group>
            )}
          </>
        )}
      </Paper>
    </Stack>
  );
}

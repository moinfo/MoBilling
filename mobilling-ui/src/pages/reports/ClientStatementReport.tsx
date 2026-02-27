import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, Select, LoadingOverlay, Alert } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconCash, IconReceipt, IconScale, IconInfoCircle } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getClientStatement } from '../../api/reports';
import { getClients } from '../../api/clients';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function ClientStatementReport() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('year').toDate(),
    dayjs().endOf('month').toDate(),
  ]);
  const [clientId, setClientId] = useState<string | null>(null);

  const { data: clientsData } = useQuery({
    queryKey: ['clients-list'],
    queryFn: () => getClients(),
  });

  const clients = clientsData?.data?.data || clientsData?.data || [];

  const params = {
    client_id: clientId || '',
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('year').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-client-statement', params.client_id, params.start_date, params.end_date],
    queryFn: () => getClientStatement(params),
    enabled: !!clientId,
  });

  const r = data?.data;

  const clientOptions = Array.isArray(clients)
    ? clients.map((c: { id: string; name: string }) => ({ value: c.id, label: c.name }))
    : [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Client Statement"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.entries as Record<string, unknown>[] | undefined}
        exportFilename={`statement-${r?.client?.name || 'client'}`}
        extra={
          <Select
            placeholder="Select client"
            data={clientOptions}
            value={clientId}
            onChange={setClientId}
            searchable
            clearable
            size="sm"
            style={{ minWidth: 200 }}
          />
        }
      />

      {!clientId && (
        <Alert icon={<IconInfoCircle size={18} />} color="blue">
          Select a client to view their statement.
        </Alert>
      )}

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 3 }}>
            <StatCard label="Total Debits" value={fmt(r.total_debit)} icon={<IconCash size={24} />} color="red" />
            <StatCard label="Total Credits" value={fmt(r.total_credit)} icon={<IconReceipt size={24} />} color="green" />
            <StatCard
              label="Closing Balance"
              value={fmt(r.closing_balance)}
              icon={<IconScale size={24} />}
              color={r.closing_balance > 0 ? 'orange' : 'green'}
            />
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Statement: {r.client.name}</Text>
            <Table.ScrollContainer minWidth={600}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th>Reference</Table.Th>
                    <Table.Th ta="right">Debit</Table.Th>
                    <Table.Th ta="right">Credit</Table.Th>
                    <Table.Th ta="right">Balance</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.entries.map((e, i) => (
                    <Table.Tr key={i}>
                      <Table.Td>{e.date}</Table.Td>
                      <Table.Td tt="capitalize">{e.type}</Table.Td>
                      <Table.Td>{e.reference}</Table.Td>
                      <Table.Td ta="right" c={e.debit > 0 ? 'red' : undefined}>{e.debit > 0 ? fmt(e.debit) : '-'}</Table.Td>
                      <Table.Td ta="right" c={e.credit > 0 ? 'green' : undefined}>{e.credit > 0 ? fmt(e.credit) : '-'}</Table.Td>
                      <Table.Td ta="right" fw={600}>{fmt(e.balance)}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
                <Table.Tfoot>
                  <Table.Tr fw={700}>
                    <Table.Td colSpan={3}>Total</Table.Td>
                    <Table.Td ta="right">{fmt(r.total_debit)}</Table.Td>
                    <Table.Td ta="right">{fmt(r.total_credit)}</Table.Td>
                    <Table.Td ta="right">{fmt(r.closing_balance)}</Table.Td>
                  </Table.Tr>
                </Table.Tfoot>
              </Table>
            </Table.ScrollContainer>
          </Paper>
        </>
      )}
    </Stack>
  );
}

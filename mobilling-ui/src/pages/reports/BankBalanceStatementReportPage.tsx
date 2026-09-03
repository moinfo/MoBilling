import { useState, useMemo } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, LoadingOverlay, Group, Box, Badge, Select } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconWallet, IconArrowDownRight, IconArrowUpRight, IconReceipt2, IconBuildingBank } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getBankBalanceStatement } from '../../api/reports';
import { getBankAccounts, BankAccount } from '../../api/bankAccounts';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';
import { formatCurrency } from '../../utils/formatCurrency';

const fmtDate = (iso: string) => dayjs(iso).format('ddd, DD MMM YYYY');

const TYPE_COLOR: Record<string, string> = { deposit: 'green', withdraw: 'red', charge: 'orange' };

export default function BankBalanceStatementReportPage() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);
  const [bankAccountId, setBankAccountId] = useState<string | null>(null);

  const { data: banksData } = useQuery({
    queryKey: ['bank-accounts-all'],
    queryFn: () => getBankAccounts({ per_page: 200 }),
  });
  const banks: BankAccount[] = banksData?.data?.data || [];
  const bankOptions = banks.filter((b) => b.is_active).map((b) => ({
    value: b.id,
    label: `${b.bank_name} · ${b.account_number}`,
  }));

  const params = {
    bank_account_id: bankAccountId || '',
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['report-bank-balance-statement', bankAccountId, params.start_date, params.end_date],
    queryFn: () => getBankBalanceStatement(params),
    enabled: !!bankAccountId,
  });

  const r = data?.data;

  const exportRows = useMemo(() => {
    if (!r) return [];
    return r.rows.map((row) => ({
      date: row.record_date,
      type: row.type,
      system: row.system_name,
      system_property: row.system_property_name,
      amount: row.signed_amount,
      running_balance: row.running_balance,
      notes: row.notes,
    }));
  }, [r]);

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading || isFetching} />
      <ReportHeader
        title="Bank Balance Statement"
        dateRange={range}
        onDateChange={setRange}
        exportData={exportRows}
        exportFilename="bank-balance-statement"
        extra={
          <Select
            placeholder="Choose a bank account"
            data={bankOptions}
            value={bankAccountId}
            onChange={setBankAccountId}
            searchable
            w={240}
            leftSection={<IconBuildingBank size={16} />}
          />
        }
      />

      {!bankAccountId ? (
        <Paper withBorder p="xl" radius="md">
          <Text c="dimmed" ta="center">Choose a bank account above to see its statement.</Text>
        </Paper>
      ) : r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 5 }}>
            <StatCard
              label="Opening Balance"
              value={formatCurrency(r.opening_balance)}
              icon={<IconWallet size={24} />}
              color="gray"
            />
            <StatCard
              label="Deposits"
              value={formatCurrency(r.total_deposits)}
              icon={<IconArrowDownRight size={24} />}
              color="green"
            />
            <StatCard
              label="Withdrawals"
              value={formatCurrency(r.total_withdrawals)}
              icon={<IconArrowUpRight size={24} />}
              color="red"
            />
            <StatCard
              label="Charges"
              value={formatCurrency(r.total_charges)}
              icon={<IconReceipt2 size={24} />}
              color="orange"
            />
            <StatCard
              label="Closing Balance"
              value={formatCurrency(r.closing_balance)}
              icon={<IconWallet size={24} />}
              color="blue"
            />
          </SimpleGrid>

          <Paper withBorder p="md" radius="md">
            <Group justify="space-between" mb="md">
              <Text fw={700}>{r.bank_account.bank_name} · {r.bank_account.account_number}</Text>
              <Text size="xs" c="dimmed">{fmtDate(r.period_start)} — {fmtDate(r.period_end)}</Text>
            </Group>

            {r.rows.length === 0 ? (
              <Box ta="center" py="xl">
                <Text c="dimmed" size="sm">No transactions in this period.</Text>
              </Box>
            ) : (
              <Table.ScrollContainer minWidth={720}>
                <Table striped highlightOnHover withRowBorders={false}>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Date</Table.Th>
                      <Table.Th>Type</Table.Th>
                      <Table.Th>System</Table.Th>
                      <Table.Th>Property</Table.Th>
                      <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                      <Table.Th style={{ textAlign: 'right' }}>Balance</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    <Table.Tr>
                      <Table.Td colSpan={5}><Text size="sm" fw={600}>Opening balance</Text></Table.Td>
                      <Table.Td style={{ textAlign: 'right' }} fw={700}>{formatCurrency(r.opening_balance)}</Table.Td>
                    </Table.Tr>
                    {r.rows.map((row) => (
                      <Table.Tr key={row.id}>
                        <Table.Td>{fmtDate(row.record_date)}</Table.Td>
                        <Table.Td>
                          <Badge size="sm" variant="light" color={TYPE_COLOR[row.type]} tt="capitalize">{row.type}</Badge>
                        </Table.Td>
                        <Table.Td>{row.system_name}</Table.Td>
                        <Table.Td>{row.system_property_name}</Table.Td>
                        <Table.Td style={{ textAlign: 'right' }} c={row.signed_amount < 0 ? 'red' : undefined} fw={600}>
                          {row.signed_amount < 0 ? '−' : '+'}{formatCurrency(Math.abs(row.signed_amount))}
                        </Table.Td>
                        <Table.Td style={{ textAlign: 'right' }} fw={600}>{formatCurrency(row.running_balance)}</Table.Td>
                      </Table.Tr>
                    ))}
                    <Table.Tr>
                      <Table.Td colSpan={5}><Text size="sm" fw={700}>Closing balance</Text></Table.Td>
                      <Table.Td style={{ textAlign: 'right' }} fw={800} c="blue.7">{formatCurrency(r.closing_balance)}</Table.Td>
                    </Table.Tr>
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            )}
          </Paper>
        </>
      )}
    </Stack>
  );
}

import { useState } from 'react';
import { Stack, Paper, Title, Table, TextInput, Group, Pagination, LoadingOverlay, Badge, Text, Tooltip, ActionIcon } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery } from '@tanstack/react-query';
import { IconSearch, IconDownload } from '@tabler/icons-react';
import { getPortalPayments, downloadPortalReceipt } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

export default function PortalPayments() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [downloading, setDownloading] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-payments', page, search],
    queryFn: () => getPortalPayments({ page, search: search || undefined }),
  });

  const payments = data?.data?.data || [];
  const lastPage = data?.data?.last_page || 1;

  const handleDownloadReceipt = async (paymentId: string) => {
    setDownloading(paymentId);
    try {
      const res = await downloadPortalReceipt(paymentId);
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.download = `receipt-${paymentId.slice(0, 8)}.pdf`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to download receipt', color: 'red' });
    } finally {
      setDownloading(null);
    }
  };

  const totalPaid = payments.reduce((s: number, p: any) => s + (parseFloat(p.amount) || 0), 0);

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Title order={3}>Payments</Title>
        <TextInput
          placeholder="Search..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          w={250}
        />
      </Group>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={600}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th w={40}>#</Table.Th>
                <Table.Th>Date</Table.Th>
                <Table.Th>Invoice</Table.Th>
                <Table.Th ta="right">Amount</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Reference</Table.Th>
                <Table.Th w={60}>Receipt</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {payments.map((p: any, index: number) => (
                <Table.Tr key={p.id}>
                  <Table.Td><Text size="sm" c="dimmed">{index + 1}</Text></Table.Td>
                  <Table.Td>{fmtDate(p.payment_date)}</Table.Td>
                  <Table.Td fw={500}>{p.document?.document_number || '-'}</Table.Td>
                  <Table.Td ta="right" fw={600} c="green">{fmt(parseFloat(p.amount) || 0)}</Table.Td>
                  <Table.Td>
                    <Badge variant="light" size="sm">{(p.payment_method || '-').replace('_', ' ')}</Badge>
                  </Table.Td>
                  <Table.Td>{p.reference || '-'}</Table.Td>
                  <Table.Td>
                    <Tooltip label="Download Receipt">
                      <ActionIcon
                        variant="light"
                        color="blue"
                        size="sm"
                        loading={downloading === p.id}
                        onClick={() => handleDownloadReceipt(p.id)}
                      >
                        <IconDownload size={16} />
                      </ActionIcon>
                    </Tooltip>
                  </Table.Td>
                </Table.Tr>
              ))}
              {payments.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={7} ta="center" c="dimmed">No payments found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
            {payments.length > 0 && (
              <Table.Tfoot>
                <Table.Tr style={{ borderTop: '2px solid var(--mantine-color-dark-4)' }}>
                  <Table.Td colSpan={3} ta="right">
                    <Text fw={700} size="sm">Total ({payments.length} payments)</Text>
                  </Table.Td>
                  <Table.Td ta="right">
                    <Text fw={700} size="sm" c="green">{fmt(totalPaid)}</Text>
                  </Table.Td>
                  <Table.Td colSpan={3} />
                </Table.Tr>
              </Table.Tfoot>
            )}
          </Table>
        </Table.ScrollContainer>
        {lastPage > 1 && (
          <Group justify="center" mt="md">
            <Pagination value={page} onChange={setPage} total={lastPage} />
          </Group>
        )}
      </Paper>
    </Stack>
  );
}

import { useState } from 'react';
import { Stack, Paper, Title, Table, Badge, TextInput, Group, Pagination, LoadingOverlay, Drawer, Text } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconSearch } from '@tabler/icons-react';
import { getPortalDocuments, getPortalDocument } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  sent: 'blue', viewed: 'cyan', partial: 'orange', paid: 'green', overdue: 'red',
};

export default function PortalDocuments({ type = 'invoice' }: { type?: string }) {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [viewId, setViewId] = useState<string | null>(null);

  const title = type === 'invoice' ? 'Invoices' : 'Quotations';

  const { data, isLoading } = useQuery({
    queryKey: ['portal-documents', type, page, search],
    queryFn: () => getPortalDocuments({ type, page, search: search || undefined }),
  });

  const { data: docDetail } = useQuery({
    queryKey: ['portal-document', viewId],
    queryFn: () => getPortalDocument(viewId!),
    enabled: !!viewId,
  });

  const docs = data?.data?.data || [];
  const lastPage = data?.data?.last_page || 1;
  const detail = docDetail?.data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Title order={3}>{title}</Title>
        <TextInput
          placeholder="Search by number..."
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
                <Table.Th>Number</Table.Th>
                <Table.Th>Date</Table.Th>
                <Table.Th>Due Date</Table.Th>
                <Table.Th ta="right">Total</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {docs.map((doc: any) => (
                <Table.Tr key={doc.id} onClick={() => setViewId(doc.id)} style={{ cursor: 'pointer' }}>
                  <Table.Td fw={600}>{doc.document_number}</Table.Td>
                  <Table.Td>{fmtDate(doc.date)}</Table.Td>
                  <Table.Td>{fmtDate(doc.due_date)}</Table.Td>
                  <Table.Td ta="right">{fmt(doc.total)}</Table.Td>
                  <Table.Td>
                    <Badge color={statusColor[doc.status] || 'gray'} variant="light" size="sm">
                      {doc.status}
                    </Badge>
                  </Table.Td>
                </Table.Tr>
              ))}
              {docs.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={5} ta="center" c="dimmed">No {title.toLowerCase()} found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
        {lastPage > 1 && (
          <Group justify="center" mt="md">
            <Pagination value={page} onChange={setPage} total={lastPage} />
          </Group>
        )}
      </Paper>

      <Drawer opened={!!viewId} onClose={() => setViewId(null)} title="Document Details" size="lg" position="right">
        {detail && (
          <Stack gap="md">
            <Group justify="space-between">
              <Text fw={700} size="lg">{detail.document_number}</Text>
              <Badge color={statusColor[detail.status] || 'gray'} variant="light">{detail.status}</Badge>
            </Group>
            <Group>
              <Text size="sm" c="dimmed">Date: {fmtDate(detail.date)}</Text>
              {detail.due_date && <Text size="sm" c="dimmed">Due: {fmtDate(detail.due_date)}</Text>}
            </Group>

            <Table striped>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Description</Table.Th>
                  <Table.Th ta="right">Qty</Table.Th>
                  <Table.Th ta="right">Price</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {detail.items?.map((item) => (
                  <Table.Tr key={item.id}>
                    <Table.Td>{item.description}</Table.Td>
                    <Table.Td ta="right">{item.quantity}</Table.Td>
                    <Table.Td ta="right">{fmt(item.unit_price)}</Table.Td>
                    <Table.Td ta="right">{fmt(item.amount)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>

            <Paper withBorder p="sm">
              <Group justify="space-between">
                <Text>Total</Text>
                <Text fw={700}>{fmt(detail.total)}</Text>
              </Group>
              {detail.paid_amount !== undefined && (
                <>
                  <Group justify="space-between">
                    <Text>Paid</Text>
                    <Text fw={600} c="green">{fmt(detail.paid_amount)}</Text>
                  </Group>
                  <Group justify="space-between">
                    <Text>Balance Due</Text>
                    <Text fw={700} c={detail.balance_due && detail.balance_due > 0 ? 'red' : undefined}>
                      {fmt(detail.balance_due || 0)}
                    </Text>
                  </Group>
                </>
              )}
            </Paper>

            {detail.notes && (
              <Paper withBorder p="sm">
                <Text size="sm" fw={600} mb={4}>Notes</Text>
                <Text size="sm" c="dimmed">{detail.notes}</Text>
              </Paper>
            )}
          </Stack>
        )}
      </Drawer>
    </Stack>
  );
}

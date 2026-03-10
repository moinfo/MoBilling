import { useState, useEffect } from 'react';
import { Stack, Paper, Title, Table, Badge, TextInput, Group, Pagination, LoadingOverlay, Drawer, Text, Button, Alert } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import { IconSearch, IconCreditCard, IconCheck, IconMail } from '@tabler/icons-react';
import { getPortalDocuments, getPortalDocument, resendPortalDocument } from '../../api/portal';
import { portalCheckoutInvoice, getPaymentStatusByTracking } from '../../api/payment';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  sent: 'blue', viewed: 'cyan', partial: 'orange', paid: 'green', overdue: 'red',
};

export default function PortalDocuments({ type = 'invoice' }: { type?: string }) {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [viewId, setViewId] = useState<string | null>(null);
  const [paying, setPaying] = useState(false);
  const [sending, setSending] = useState(false);
  const [paymentDone, setPaymentDone] = useState(false);
  const [searchParams, setSearchParams] = useSearchParams();
  const queryClient = useQueryClient();

  const title = type === 'invoice' ? 'Invoices' : 'Quotations';

  // Handle Pesapal callback — poll payment status
  const trackingId = searchParams.get('OrderTrackingId');
  useEffect(() => {
    if (!trackingId) return;
    const interval = setInterval(() => {
      getPaymentStatusByTracking(trackingId).then((res) => {
        if (res.data.status === 'completed') {
          setPaymentDone(true);
          clearInterval(interval);
          queryClient.invalidateQueries({ queryKey: ['portal-documents'] });
          // Clear the URL params
          setSearchParams({});
        } else if (res.data.status === 'failed') {
          clearInterval(interval);
          setSearchParams({});
          notifications.show({ title: 'Payment failed', message: 'Please try again.', color: 'red' });
        }
      });
    }, 3000);
    return () => clearInterval(interval);
  }, [trackingId]);

  const handlePay = async (docId: string) => {
    setPaying(true);
    try {
      const res = await portalCheckoutInvoice(docId);
      if (res.data.redirect_url) {
        window.location.href = res.data.redirect_url;
      }
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Payment initiation failed.',
        color: 'red',
      });
    } finally {
      setPaying(false);
    }
  };

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
      {paymentDone && (
        <Alert color="green" icon={<IconCheck size={20} />} title="Payment Successful" withCloseButton onClose={() => setPaymentDone(false)}>
          Your payment has been received. Thank you!
        </Alert>
      )}
      {trackingId && !paymentDone && (
        <Alert color="blue" title="Processing Payment">
          Verifying your payment, please wait...
        </Alert>
      )}
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
                <Table.Th>Description</Table.Th>
                <Table.Th>Date</Table.Th>
                <Table.Th>Due Date</Table.Th>
                <Table.Th ta="right">Total</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {docs.map((doc: any) => {
                const desc = doc.items?.[0]?.description || doc.notes || '-';
                return (
                  <Table.Tr key={doc.id} onClick={() => setViewId(doc.id)} style={{ cursor: 'pointer' }}>
                    <Table.Td fw={600}>{doc.document_number}</Table.Td>
                    <Table.Td c="dimmed" maw={250} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {desc}
                    </Table.Td>
                    <Table.Td>{fmtDate(doc.date)}</Table.Td>
                    <Table.Td>{fmtDate(doc.due_date)}</Table.Td>
                    <Table.Td ta="right">{fmt(doc.total)}</Table.Td>
                    <Table.Td>
                      <Badge color={statusColor[doc.status] || 'gray'} variant="light" size="sm">
                        {doc.status}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
              {docs.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={6} ta="center" c="dimmed">No {title.toLowerCase()} found</Table.Td>
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
                    <Table.Td ta="right">{fmt(item.price)}</Table.Td>
                    <Table.Td ta="right">{fmt(item.total)}</Table.Td>
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

            {type === 'invoice' && (detail.balance_due ?? 0) > 0 && (
              <Button
                fullWidth
                size="md"
                leftSection={<IconCreditCard size={18} />}
                loading={paying}
                onClick={() => handlePay(detail.id)}
              >
                Pay {fmt(detail.balance_due ?? 0)} Online
              </Button>
            )}

            {detail.notes && (
              <Paper withBorder p="sm">
                <Text size="sm" fw={600} mb={4}>Notes</Text>
                <Text size="sm" c="dimmed">{detail.notes}</Text>
              </Paper>
            )}

            <Button
              variant="light"
              fullWidth
              leftSection={<IconMail size={18} />}
              loading={sending}
              onClick={async () => {
                setSending(true);
                try {
                  await resendPortalDocument(detail.id);
                  notifications.show({ title: 'Sent', message: 'Document sent to your email.', color: 'green' });
                } catch {
                  notifications.show({ title: 'Error', message: 'Failed to send document.', color: 'red' });
                } finally {
                  setSending(false);
                }
              }}
            >
              Resend to My Email
            </Button>
          </Stack>
        )}
      </Drawer>
    </Stack>
  );
}

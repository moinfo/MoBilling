import { useState, useEffect } from 'react';
import {
  Box, Paper, Title, Text, Table, Group, Stack, Button, Image,
  LoadingOverlay, Alert, ThemeIcon, Divider, rem,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useParams, useSearchParams } from 'react-router-dom';
import { IconCheck, IconCreditCard, IconBuildingBank } from '@tabler/icons-react';
import { getInvoiceForPayment, checkoutInvoice, getPaymentStatusByTracking, type InvoicePaymentInfo } from '../api/payment';

const fmt = (n: number, currency = 'TZS') =>
  `${currency} ${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fmtDate = (d: string | null) =>
  d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

export default function PayInvoice() {
  const { id } = useParams<{ id: string }>();
  const [searchParams] = useSearchParams();
  const [data, setData] = useState<InvoicePaymentInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const [paymentDone, setPaymentDone] = useState(false);
  const [error, setError] = useState('');

  // Check if returning from Pesapal callback
  const trackingId = searchParams.get('OrderTrackingId');

  useEffect(() => {
    if (!id) return;
    getInvoiceForPayment(id)
      .then((res) => setData(res.data))
      .catch(() => setError('Invoice not found or no longer available.'))
      .finally(() => setLoading(false));
  }, [id]);

  // Poll payment status if returning from Pesapal callback
  useEffect(() => {
    if (!trackingId || !id) return;
    const interval = setInterval(() => {
      getPaymentStatusByTracking(trackingId).then((res) => {
        if (res.data.status === 'completed') {
          setPaymentDone(true);
          clearInterval(interval);
          // Refresh invoice data
          getInvoiceForPayment(id).then((r) => setData(r.data));
        } else if (res.data.status === 'failed') {
          clearInterval(interval);
          notifications.show({ title: 'Payment failed', message: 'Please try again.', color: 'red' });
        }
      });
    }, 3000);
    return () => clearInterval(interval);
  }, [trackingId, id]);

  const handlePay = async () => {
    if (!id) return;
    setPaying(true);
    try {
      const res = await checkoutInvoice(id);
      if (res.data.redirect_url) {
        // Save payment_id for callback
        const url = new URL(res.data.redirect_url);
        window.location.href = res.data.redirect_url;
      }
    } catch (err: any) {
      const msg = err.response?.data?.message || 'Payment initiation failed.';
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    } finally {
      setPaying(false);
    }
  };

  if (loading) return <LoadingOverlay visible />;
  if (error) {
    return (
      <Box style={{ minHeight: '100vh', display: 'flex', justifyContent: 'center', alignItems: 'center', padding: rem(24) }}>
        <Alert color="red" title="Error">{error}</Alert>
      </Box>
    );
  }
  if (!data) return null;

  const { invoice, tenant } = data;
  const isPaid = invoice.status === 'paid' || invoice.balance_due <= 0;

  return (
    <Box style={{ minHeight: '100vh', background: '#f8f9fa', display: 'flex', justifyContent: 'center', padding: rem(24) }}>
      <Box w="100%" maw={700} py="xl">
        {/* Header */}
        <Group justify="center" gap="sm" mb="xl">
          {tenant.logo_url && <Image src={tenant.logo_url} h={40} w="auto" alt={tenant.name} />}
          <Title order={3}>{tenant.name}</Title>
        </Group>

        {paymentDone && (
          <Alert color="green" icon={<IconCheck size={20} />} mb="md" title="Payment Successful">
            Your payment has been received. Thank you!
          </Alert>
        )}

        {/* Invoice Summary */}
        <Paper withBorder shadow="sm" p="xl" radius="md" mb="md">
          <Group justify="space-between" mb="md">
            <div>
              <Text fw={700} size="lg">{invoice.document_number}</Text>
              <Text size="sm" c="dimmed">To: {invoice.client.name}</Text>
            </div>
            <div style={{ textAlign: 'right' }}>
              <Text size="sm" c="dimmed">Date: {fmtDate(invoice.date)}</Text>
              {invoice.due_date && <Text size="sm" c="dimmed">Due: {fmtDate(invoice.due_date)}</Text>}
            </div>
          </Group>

          <Table striped mb="md">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Description</Table.Th>
                <Table.Th ta="right">Qty</Table.Th>
                <Table.Th ta="right">Price</Table.Th>
                <Table.Th ta="right">Amount</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {invoice.items.map((item, i) => (
                <Table.Tr key={i}>
                  <Table.Td>{item.description}</Table.Td>
                  <Table.Td ta="right">{item.quantity}</Table.Td>
                  <Table.Td ta="right">{fmt(item.unit_price, tenant.currency)}</Table.Td>
                  <Table.Td ta="right">{fmt(item.amount, tenant.currency)}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>

          <Stack gap={4}>
            <Group justify="space-between">
              <Text>Total</Text>
              <Text fw={700}>{fmt(invoice.total, tenant.currency)}</Text>
            </Group>
            {invoice.paid_amount > 0 && (
              <Group justify="space-between">
                <Text>Paid</Text>
                <Text fw={600} c="green">{fmt(invoice.paid_amount, tenant.currency)}</Text>
              </Group>
            )}
            <Divider />
            <Group justify="space-between">
              <Text fw={700}>Balance Due</Text>
              <Text fw={700} size="lg" c={isPaid ? 'green' : 'red'}>
                {isPaid ? 'PAID' : fmt(invoice.balance_due, tenant.currency)}
              </Text>
            </Group>
          </Stack>
        </Paper>

        {/* Payment Options */}
        {!isPaid && (
          <Paper withBorder shadow="sm" p="xl" radius="md">
            <Text fw={600} mb="md">Payment Options</Text>

            {tenant.pesapal_enabled && (
              <Button
                fullWidth
                size="lg"
                mb="md"
                leftSection={<IconCreditCard size={20} />}
                loading={paying}
                onClick={handlePay}
              >
                Pay {fmt(invoice.balance_due, tenant.currency)} Online
              </Button>
            )}

            {(tenant.bank_name || tenant.payment_instructions) && (
              <>
                {tenant.pesapal_enabled && <Divider label="or pay via bank transfer" labelPosition="center" mb="md" />}
                <Paper withBorder p="md" bg="gray.0" radius="md">
                  <Group gap="xs" mb="sm">
                    <ThemeIcon variant="light" color="gray" size="sm"><IconBuildingBank size={14} /></ThemeIcon>
                    <Text fw={600} size="sm">Bank Transfer</Text>
                  </Group>
                  {tenant.bank_name && <Text size="sm">Bank: {tenant.bank_name}</Text>}
                  {tenant.bank_account_name && <Text size="sm">Account Name: {tenant.bank_account_name}</Text>}
                  {tenant.bank_account_number && <Text size="sm">Account Number: {tenant.bank_account_number}</Text>}
                  {tenant.bank_branch && <Text size="sm">Branch: {tenant.bank_branch}</Text>}
                  {tenant.payment_instructions && (
                    <Text size="sm" mt="xs" c="dimmed">{tenant.payment_instructions}</Text>
                  )}
                </Paper>
              </>
            )}
          </Paper>
        )}

        {isPaid && !paymentDone && (
          <Paper withBorder shadow="sm" p="xl" radius="md">
            <Stack align="center" gap="md">
              <ThemeIcon size={50} radius="xl" color="green" variant="light">
                <IconCheck size={28} />
              </ThemeIcon>
              <Text fw={600}>This invoice has been fully paid</Text>
            </Stack>
          </Paper>
        )}

        <Text size="xs" c="dimmed" ta="center" mt="xl">
          Powered by MoBilling
        </Text>
      </Box>
    </Box>
  );
}

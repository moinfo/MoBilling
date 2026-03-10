import { useState, useEffect } from 'react';
import {
  Box, Paper, Title, Text, Table, Group, Stack, Button, Image,
  LoadingOverlay, Alert, ThemeIcon, Divider, rem, Badge, useMantineColorScheme,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useParams, useSearchParams } from 'react-router-dom';
import { IconCheck, IconCreditCard, IconBuildingBank, IconReceipt, IconCalendar, IconUser, IconAlertTriangle } from '@tabler/icons-react';
import { getInvoiceForPayment, checkoutInvoice, getPaymentStatusByTracking, type InvoicePaymentInfo } from '../api/payment';

const fmt = (n: number, currency = 'TZS') =>
  `${currency} ${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fmtDate = (d: string | null) =>
  d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

export default function PayInvoice() {
  const { id } = useParams<{ id: string }>();
  const [searchParams] = useSearchParams();
  const { colorScheme } = useMantineColorScheme();
  const isDark = colorScheme === 'dark';
  const [data, setData] = useState<InvoicePaymentInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const [paymentDone, setPaymentDone] = useState(false);
  const [error, setError] = useState('');

  const trackingId = searchParams.get('OrderTrackingId');

  useEffect(() => {
    if (!id) return;
    getInvoiceForPayment(id)
      .then((res) => setData(res.data))
      .catch(() => setError('Invoice not found or no longer available.'))
      .finally(() => setLoading(false));
  }, [id]);

  useEffect(() => {
    if (!trackingId || !id) return;
    const interval = setInterval(() => {
      getPaymentStatusByTracking(trackingId).then((res) => {
        if (res.data.status === 'completed') {
          setPaymentDone(true);
          clearInterval(interval);
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
  const isOverdue = invoice.due_date && new Date(invoice.due_date) < new Date() && !isPaid;

  return (
    <Box
      style={{
        minHeight: '100vh',
        display: 'flex',
        justifyContent: 'center',
        padding: rem(16),
        paddingTop: rem(32),
        background: isDark
          ? 'linear-gradient(180deg, var(--mantine-color-dark-8) 0%, var(--mantine-color-dark-9) 100%)'
          : 'linear-gradient(180deg, #f0f4f8 0%, #e2e8f0 100%)',
      }}
    >
      <Box w="100%" maw={600}>
        {/* Company Header */}
        <Stack align="center" gap={4} mb="xl">
          {tenant.logo_url && (
            <Image src={tenant.logo_url} h={48} w="auto" alt={tenant.name} fit="contain" />
          )}
          <Title order={4} c={isDark ? 'gray.3' : 'gray.7'}>{tenant.name}</Title>
        </Stack>

        {paymentDone && (
          <Alert color="green" icon={<IconCheck size={20} />} mb="md" title="Payment Successful" radius="md">
            Your payment has been received. Thank you!
          </Alert>
        )}

        {/* Invoice Card */}
        <Paper
          withBorder
          shadow="md"
          radius="lg"
          mb="md"
          style={{ overflow: 'hidden' }}
        >
          {/* Invoice header with accent bar */}
          <Box
            p="lg"
            style={{
              background: isPaid
                ? 'var(--mantine-color-green-6)'
                : isOverdue
                  ? 'var(--mantine-color-orange-6)'
                  : 'var(--mantine-color-blue-6)',
            }}
          >
            <Group justify="space-between" align="flex-start">
              <div>
                <Group gap="xs" mb={4}>
                  <IconReceipt size={18} color="white" />
                  <Text fw={700} size="lg" c="white">{invoice.document_number}</Text>
                </Group>
                <Group gap="xs">
                  <IconUser size={14} color="rgba(255,255,255,0.8)" />
                  <Text size="sm" c="rgba(255,255,255,0.85)">{invoice.client.name}</Text>
                </Group>
              </div>
              <Stack gap={2} align="flex-end">
                <Group gap={4}>
                  <IconCalendar size={13} color="rgba(255,255,255,0.7)" />
                  <Text size="xs" c="rgba(255,255,255,0.8)">{fmtDate(invoice.date)}</Text>
                </Group>
                {invoice.due_date && (
                  <Text size="xs" c="rgba(255,255,255,0.8)">Due: {fmtDate(invoice.due_date)}</Text>
                )}
                <Badge
                  size="sm"
                  variant="white"
                  color={isPaid ? 'green' : isOverdue ? 'orange' : 'blue'}
                  mt={4}
                >
                  {isPaid ? 'PAID' : isOverdue ? 'OVERDUE' : 'UNPAID'}
                </Badge>
              </Stack>
            </Group>
          </Box>

          {/* Items */}
          <Box p="lg">
            <Table horizontalSpacing="sm" verticalSpacing="xs" mb="md">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Description</Table.Th>
                  <Table.Th ta="center">Qty</Table.Th>
                  <Table.Th ta="right">Price</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {invoice.items.map((item, i) => (
                  <Table.Tr key={i}>
                    <Table.Td>
                      <Text size="sm">{item.description}</Text>
                    </Table.Td>
                    <Table.Td ta="center">
                      <Text size="sm">{item.quantity}</Text>
                    </Table.Td>
                    <Table.Td ta="right">
                      <Text size="sm">{fmt(item.unit_price, tenant.currency)}</Text>
                    </Table.Td>
                    <Table.Td ta="right">
                      <Text size="sm" fw={500}>{fmt(item.amount, tenant.currency)}</Text>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>

            <Divider mb="sm" />

            <Stack gap={6}>
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Total</Text>
                <Text size="sm" fw={600}>{fmt(invoice.total, tenant.currency)}</Text>
              </Group>
              {invoice.paid_amount > 0 && (
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Paid</Text>
                  <Text size="sm" fw={600} c="green">{fmt(invoice.paid_amount, tenant.currency)}</Text>
                </Group>
              )}
              <Divider />
              <Group justify="space-between">
                <Text fw={700}>Balance Due</Text>
                <Text fw={700} size="xl" c={isPaid ? 'green' : 'red'}>
                  {isPaid ? 'PAID' : fmt(invoice.balance_due, tenant.currency)}
                </Text>
              </Group>
            </Stack>
          </Box>
        </Paper>

        {/* Payment Options */}
        {!isPaid && (
          <Paper withBorder shadow="md" p="lg" radius="lg" mb="md">
            <Text fw={700} size="sm" tt="uppercase" c="dimmed" mb="md" style={{ letterSpacing: 0.5 }}>
              Payment Options
            </Text>

            {tenant.pesapal_enabled && (
              <Button
                fullWidth
                size="lg"
                radius="md"
                mb="md"
                leftSection={<IconCreditCard size={20} />}
                loading={paying}
                onClick={handlePay}
                variant="gradient"
                gradient={{ from: 'blue', to: 'cyan', deg: 135 }}
              >
                Pay {fmt(invoice.balance_due, tenant.currency)} Online
              </Button>
            )}

            {(tenant.bank_name || tenant.payment_instructions) && (
              <>
                {tenant.pesapal_enabled && (
                  <Divider label="or pay via bank transfer" labelPosition="center" mb="md" />
                )}
                <Paper
                  withBorder
                  p="md"
                  radius="md"
                  style={{ borderColor: 'var(--mantine-color-blue-light)' }}
                >
                  <Group gap="xs" mb="sm">
                    <ThemeIcon variant="light" color="blue" size="sm" radius="xl">
                      <IconBuildingBank size={14} />
                    </ThemeIcon>
                    <Text fw={600} size="sm">Bank Transfer</Text>
                  </Group>
                  <Stack gap={2} ml={30}>
                    {tenant.bank_name && (
                      <Text size="sm">
                        <Text span c="dimmed">Bank:</Text> <Text span fw={500}>{tenant.bank_name}</Text>
                      </Text>
                    )}
                    {tenant.bank_account_name && (
                      <Text size="sm">
                        <Text span c="dimmed">Account Name:</Text> <Text span fw={500}>{tenant.bank_account_name}</Text>
                      </Text>
                    )}
                    {tenant.bank_account_number && (
                      <Text size="sm">
                        <Text span c="dimmed">Account Number:</Text> <Text span fw={500}>{tenant.bank_account_number}</Text>
                      </Text>
                    )}
                    {tenant.bank_branch && (
                      <Text size="sm">
                        <Text span c="dimmed">Branch:</Text> <Text span fw={500}>{tenant.bank_branch}</Text>
                      </Text>
                    )}
                  </Stack>
                  {tenant.payment_instructions && (
                    <Text size="xs" c="dimmed" mt="sm" ml={30} style={{ fontStyle: 'italic' }}>
                      {tenant.payment_instructions}
                    </Text>
                  )}
                </Paper>
              </>
            )}
          </Paper>
        )}

        {/* Payment Terms */}
        {!isPaid && (
          <Paper withBorder p="lg" radius="lg" mb="md" style={{ borderColor: 'var(--mantine-color-orange-light)' }}>
            <Group gap="xs" mb="sm">
              <ThemeIcon variant="light" color="orange" size="sm" radius="xl">
                <IconAlertTriangle size={14} />
              </ThemeIcon>
              <Text fw={700} size="sm" c="orange">Payment Terms</Text>
            </Group>
            <Stack gap={4} ml={30}>
              {invoice.due_date && (() => {
                const daysLeft = Math.ceil((new Date(invoice.due_date).getTime() - Date.now()) / 86400000);
                return (
                  <Text size="sm" fw={500} c={daysLeft <= 0 ? 'red' : daysLeft <= 3 ? 'orange' : undefined}>
                    {daysLeft > 0
                      ? `Payment due within ${daysLeft} day(s) (${fmtDate(invoice.due_date)})`
                      : daysLeft === 0
                        ? 'Payment is due today'
                        : `Payment is ${Math.abs(daysLeft)} day(s) overdue`}
                  </Text>
                );
              })()}
              <Text size="xs" c="dimmed">10% late fee applied after due date</Text>
              <Text size="xs" c="dimmed">Overdue reminder sent after 7 days</Text>
              <Text size="xs" c="dimmed">Service termination warning after 14 days</Text>
              <Text size="xs" c="dimmed">Service terminated after 21 days</Text>
            </Stack>
          </Paper>
        )}

        {/* Paid state */}
        {isPaid && !paymentDone && (
          <Paper withBorder shadow="md" p="xl" radius="lg">
            <Stack align="center" gap="md">
              <ThemeIcon size={60} radius="xl" color="green" variant="light">
                <IconCheck size={32} />
              </ThemeIcon>
              <Text fw={600} size="lg">This invoice has been fully paid</Text>
              <Text size="sm" c="dimmed">Thank you for your payment</Text>
            </Stack>
          </Paper>
        )}

        <Text size="xs" c="dimmed" ta="center" mt="xl" mb="md">
          Powered by MoBilling
        </Text>
      </Box>
    </Box>
  );
}

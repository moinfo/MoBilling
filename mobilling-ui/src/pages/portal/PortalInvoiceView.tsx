import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Button, Grid, Table, Divider,
  Alert, Center, Loader, ActionIcon, Accordion,
} from '@mantine/core';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useParams } from 'react-router-dom';
import {
  IconArrowLeft, IconCreditCard, IconDownload, IconMail, IconCash,
  IconAlertTriangle, IconBuildingBank,
} from '@tabler/icons-react';
import {
  getPortalDocument, downloadPortalDocumentPdf, resendPortalDocument,
  portalApplyCredit, getPortalCredit,
} from '../../api/portal';
import { portalCheckoutInvoice } from '../../api/payment';

const fmt = (n: number | string | null | undefined) =>
  (parseFloat(String(n ?? 0)) || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null | undefined) =>
  d ? new Date(d).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '—';

const STAMP: Record<string, { label: string; color: string }> = {
  paid:    { label: 'PAID',    color: 'green' },
  partial: { label: 'PARTIAL', color: 'orange' },
  overdue: { label: 'OVERDUE', color: 'red' },
  sent:    { label: 'UNPAID',  color: 'red' },
  viewed:  { label: 'UNPAID',  color: 'red' },
};

function AddressPanel({ title, info }: { title: string; info: any }) {
  return (
    <Paper withBorder radius="md" p="md" h="100%">
      <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={6}>{title}</Text>
      <Text fw={700}>{info?.name ?? '—'}</Text>
      {info?.address && <Text size="sm">{info.address}</Text>}
      {info?.email && <Text size="sm" c="dimmed">{info.email}</Text>}
      {info?.phone && <Text size="sm" c="dimmed">{info.phone}</Text>}
      {info?.tax_id && <Text size="sm" c="dimmed">TIN: {info.tax_id}</Text>}
    </Paper>
  );
}

export default function PortalInvoiceView() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [paying, setPaying] = useState(false);
  const [applyingCredit, setApplyingCredit] = useState(false);
  const [sending, setSending] = useState(false);
  const [downloading, setDownloading] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-document', id],
    queryFn: () => getPortalDocument(id!),
    enabled: !!id,
  });
  const inv: any = data?.data?.data;

  const { data: creditData } = useQuery({ queryKey: ['portal-credit'], queryFn: getPortalCredit });
  const creditBalance: number = creditData?.data?.data?.balance ?? 0;

  if (isLoading || !inv) {
    return <Center py="xl"><Loader /></Center>;
  }

  const balance = parseFloat(inv.balance_due ?? 0) || 0;
  const stamp = balance <= 0 && inv.status === 'paid'
    ? STAMP.paid
    : STAMP[inv.status] ?? { label: String(inv.status).toUpperCase(), color: 'gray' };

  const handlePay = async () => {
    setPaying(true);
    try {
      const res = await portalCheckoutInvoice(inv.id);
      if (res.data.redirect_url) window.location.href = res.data.redirect_url;
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Payment initiation failed.', color: 'red' });
    } finally {
      setPaying(false);
    }
  };

  const handleCredit = async () => {
    setApplyingCredit(true);
    try {
      const res = await portalApplyCredit(inv.id);
      notifications.show({ title: 'Credit applied', message: res.data?.message, color: 'green' });
      qc.invalidateQueries({ queryKey: ['portal-document', id] });
      qc.invalidateQueries({ queryKey: ['portal-documents'] });
      qc.invalidateQueries({ queryKey: ['portal-credit'] });
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not apply credit.', color: 'red' });
    } finally {
      setApplyingCredit(false);
    }
  };

  const handleDownload = async () => {
    setDownloading(true);
    try {
      const res = await downloadPortalDocumentPdf(inv.id);
      const url = URL.createObjectURL(new Blob([res.data], { type: 'application/pdf' }));
      const a = document.createElement('a');
      a.href = url;
      a.download = `${inv.document_number}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      notifications.show({ message: 'Failed to download PDF.', color: 'red' });
    } finally {
      setDownloading(false);
    }
  };

  const handleResend = async () => {
    setSending(true);
    try {
      await resendPortalDocument(inv.id);
      notifications.show({ title: 'Sent', message: 'Invoice sent to your email.', color: 'green' });
    } catch {
      notifications.show({ message: 'Failed to send.', color: 'red' });
    } finally {
      setSending(false);
    }
  };

  const discount = parseFloat(inv.discount_amount ?? 0) || 0;
  const tax = parseFloat(inv.tax_amount ?? 0) || 0;
  const lateFee = parseFloat(inv.late_fee ?? 0) || 0;
  const isInvoice = inv.type === 'invoice';

  return (
    <Stack gap="lg">
      {/* Header */}
      <Group justify="space-between" wrap="wrap">
        <Group gap="xs">
          <ActionIcon variant="subtle" onClick={() => navigate('/portal/invoices')}><IconArrowLeft size={18} /></ActionIcon>
          <Title order={3}>Invoice {inv.document_number}</Title>
        </Group>
        <Badge size="xl" radius="sm" variant="light" color={stamp.color}
          styles={{ root: { fontSize: 18, padding: '14px 18px', border: `2px solid var(--mantine-color-${stamp.color}-5)` } }}>
          {stamp.label}
        </Badge>
      </Group>

      {inv.status === 'overdue' && balance > 0 && (
        <Alert color="red" variant="light" icon={<IconAlertTriangle size={18} />}>
          This invoice is overdue. Please pay {fmt(balance)} as soon as possible to avoid service interruption.
        </Alert>
      )}

      {/* Actions */}
      <Group gap="xs" wrap="wrap">
        {isInvoice && balance > 0 && (
          <Button color="green" leftSection={<IconCreditCard size={18} />} loading={paying} onClick={handlePay}>
            Pay {fmt(balance)} Now
          </Button>
        )}
        {isInvoice && balance > 0 && creditBalance > 0 && (
          <Button variant="light" color="teal" leftSection={<IconCash size={16} />} loading={applyingCredit} onClick={handleCredit}>
            Use Credit ({fmt(Math.min(creditBalance, balance))})
          </Button>
        )}
        <Button variant="light" leftSection={<IconDownload size={16} />} loading={downloading} onClick={handleDownload}>
          Download PDF
        </Button>
        <Button variant="light" leftSection={<IconMail size={16} />} loading={sending} onClick={handleResend}>
          Email Me a Copy
        </Button>
      </Group>

      <Paper withBorder radius="md" p="lg">
        <Stack gap="lg">
          {/* Parties + dates */}
          <Grid>
            <Grid.Col span={{ base: 12, sm: 6 }}>
              <AddressPanel title="Invoiced To" info={inv.invoiced_to} />
            </Grid.Col>
            <Grid.Col span={{ base: 12, sm: 6 }}>
              <AddressPanel title="Pay To" info={inv.pay_to} />
            </Grid.Col>
          </Grid>

          <Grid>
            <Grid.Col span={{ base: 12, sm: 6 }}>
              <Text size="sm" fw={700}>Invoice Date:</Text>
              <Text size="sm">{fmtDate(inv.date)}</Text>
            </Grid.Col>
            <Grid.Col span={{ base: 12, sm: 6 }}>
              <Text size="sm" fw={700}>Due Date:</Text>
              <Text size="sm" c={inv.status === 'overdue' ? 'red' : undefined}>{fmtDate(inv.due_date)}</Text>
            </Grid.Col>
          </Grid>

          <Divider />

          {/* Items */}
          <Table.ScrollContainer minWidth={520}>
            <Table striped withTableBorder>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Description</Table.Th>
                  <Table.Th ta="right" w={70}>Qty</Table.Th>
                  <Table.Th ta="right" w={130}>Price</Table.Th>
                  <Table.Th ta="right" w={130}>Amount</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {inv.items?.map((item: any) => (
                  <Table.Tr key={item.id}>
                    <Table.Td>
                      <Text size="sm">{item.description}</Text>
                      {item.service_from && item.service_to && (
                        <Text size="xs" c="dimmed">
                          {new Date(item.service_from).toLocaleDateString('en-GB')} — {new Date(item.service_to).toLocaleDateString('en-GB')}
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td ta="right">{item.quantity}</Table.Td>
                    <Table.Td ta="right">{fmt(item.price)}</Table.Td>
                    <Table.Td ta="right" fw={500}>{fmt(item.total)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>

          {/* Totals */}
          <Group justify="flex-end">
            <Stack gap={6} w={320} maw="100%">
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Sub Total</Text>
                <Text size="sm">{fmt(inv.subtotal)}</Text>
              </Group>
              {discount > 0 && (
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Discount</Text>
                  <Text size="sm" c="green">-{fmt(discount)}</Text>
                </Group>
              )}
              {tax > 0 && (
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Tax</Text>
                  <Text size="sm">{fmt(tax)}</Text>
                </Group>
              )}
              {lateFee > 0 && (
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Late Fee</Text>
                  <Text size="sm" c="red">{fmt(lateFee)}</Text>
                </Group>
              )}
              <Divider />
              <Group justify="space-between">
                <Text fw={700}>Total</Text>
                <Text fw={700}>{fmt(inv.total)}</Text>
              </Group>
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Paid</Text>
                <Text size="sm" c="green">{fmt(inv.paid_amount)}</Text>
              </Group>
              <Group justify="space-between">
                <Text fw={700}>Balance Due</Text>
                <Text fw={700} size="lg" c={balance > 0 ? 'red' : 'green'}>{fmt(balance)}</Text>
              </Group>
            </Stack>
          </Group>
        </Stack>
      </Paper>

      {/* Offline payment instructions */}
      {isInvoice && balance > 0 && (inv.payment_methods?.length ?? 0) > 0 && (
        <Paper withBorder radius="md" p="lg">
          <Group gap="xs" mb="sm"><IconBuildingBank size={18} /><Text fw={700}>Other Ways to Pay</Text></Group>
          <Text size="sm" c="dimmed" mb="sm">
            You can also pay by bank transfer or mobile money — use the details below and quote invoice
            {' '}<Text span fw={600}>{inv.document_number}</Text> as the reference.
          </Text>
          <Accordion variant="separated">
            {inv.payment_methods.map((m: any) => (
              <Accordion.Item key={m.value} value={m.value}>
                <Accordion.Control>{m.label}</Accordion.Control>
                <Accordion.Panel>
                  <Stack gap={4}>
                    {m.details.map((d: any) => (
                      <Group key={d.key} justify="space-between">
                        <Text size="sm" c="dimmed">{d.key}</Text>
                        <Text size="sm" fw={600}>{d.value}</Text>
                      </Group>
                    ))}
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
            ))}
          </Accordion>
        </Paper>
      )}

      {/* Transactions */}
      <Paper withBorder radius="md" p="lg">
        <Text fw={700} mb="sm">Transactions</Text>
        {(inv.payments?.length ?? 0) === 0 ? (
          <Text size="sm" c="dimmed">No related transactions found.</Text>
        ) : (
          <Table.ScrollContainer minWidth={480}>
            <Table striped>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Method</Table.Th>
                  <Table.Th>Reference</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {inv.payments.map((p: any) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{new Date(p.payment_date).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}</Table.Td>
                    <Table.Td><Badge variant="light" size="sm">{(p.payment_method || '').replace('_', ' ')}</Badge></Table.Td>
                    <Table.Td><Text size="sm" c="dimmed">{p.reference || '—'}</Text></Table.Td>
                    <Table.Td ta="right" fw={600} c="green">{fmt(p.amount)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {inv.notes && (
        <Paper withBorder radius="md" p="lg">
          <Text fw={700} mb={4}>Notes</Text>
          <Text size="sm" c="dimmed">{inv.notes}</Text>
        </Paper>
      )}

      <Text size="xs" c="dimmed" ta="center">Powered by MoBilling</Text>
    </Stack>
  );
}

import { Card, Group, Text, Badge, Table, Divider, Button, Stack, NumberInput, Select, TextInput, Textarea, Alert } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconFileDownload, IconSend, IconArrowRight, IconCash } from '@tabler/icons-react';
import { useState } from 'react';
import { Document, convertDocument, downloadPdf, sendDocument, createPaymentIn } from '../../api/documents';
import { usePaymentMethods } from '../../hooks/usePaymentMethods';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';
import dayjs from 'dayjs';

interface Props {
  document: Document;
  onRefresh: () => void;
  onClose: () => void;
}

const statusColors: Record<string, string> = {
  draft: 'gray', sent: 'blue', accepted: 'teal', rejected: 'red',
  paid: 'green', overdue: 'orange', partial: 'yellow',
};

export default function DocumentView({ document: doc, onRefresh, onClose: _onClose }: Props) {
  const { methods: paymentMethods, getMethodDetails } = usePaymentMethods();
  const [showPayment, setShowPayment] = useState(false);
  const [loading, setLoading] = useState('');

  const paymentForm = useForm({
    initialValues: {
      amount: doc.balance_due,
      payment_date: new Date(),
      payment_method: 'bank',
      reference: '',
      notes: '',
    },
  });

  const handleConvert = () => {
    const target = doc.type === 'quotation' ? 'proforma' : 'invoice';
    modals.openConfirmModal({
      title: `Convert to ${target}`,
      children: `This will create a new ${target} from this ${doc.type} and mark it as accepted.`,
      labels: { confirm: 'Convert', cancel: 'Cancel' },
      onConfirm: async () => {
        try {
          setLoading('convert');
          await convertDocument(doc.id, target);
          notifications.show({ title: 'Success', message: `Converted to ${target}`, color: 'green' });
          onRefresh();
        } catch {
          notifications.show({ title: 'Error', message: 'Conversion failed', color: 'red' });
        } finally {
          setLoading('');
        }
      },
    });
  };

  const handleDownloadPdf = async () => {
    try {
      setLoading('pdf');
      const res = await downloadPdf(doc.id);
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = window.document.createElement('a');
      link.href = url;
      link.download = `${doc.document_number}.pdf`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'PDF download failed', color: 'red' });
    } finally {
      setLoading('');
    }
  };

  const handleSend = () => {
    modals.openConfirmModal({
      title: 'Send Document',
      children: `Send ${doc.document_number} to ${doc.client?.email || 'client'}?`,
      labels: { confirm: 'Send', cancel: 'Cancel' },
      onConfirm: async () => {
        try {
          setLoading('send');
          await sendDocument(doc.id);
          notifications.show({ title: 'Success', message: 'Document sent', color: 'green' });
          onRefresh();
        } catch (err: any) {
          notifications.show({ title: 'Error', message: err.response?.data?.message || 'Send failed', color: 'red' });
        } finally {
          setLoading('');
        }
      },
    });
  };

  const handlePayment = async (values: any) => {
    try {
      setLoading('payment');
      await createPaymentIn({
        document_id: doc.id,
        amount: values.amount,
        payment_date: dayjs(values.payment_date).format('YYYY-MM-DD'),
        payment_method: values.payment_method,
        reference: values.reference || undefined,
        notes: values.notes || undefined,
      });
      notifications.show({ title: 'Success', message: 'Payment recorded', color: 'green' });
      setShowPayment(false);
      onRefresh();
    } catch {
      notifications.show({ title: 'Error', message: 'Payment failed', color: 'red' });
    } finally {
      setLoading('');
    }
  };

  const canConvert = (doc.type === 'quotation' || doc.type === 'proforma') && doc.status !== 'accepted';
  const isInvoice = doc.type === 'invoice';

  return (
    <Stack>
      <Card withBorder>
        <Group justify="space-between" mb="md">
          <div>
            <Text size="xl" fw={700}>{doc.document_number}</Text>
            <Text c="dimmed" size="sm">{doc.type.charAt(0).toUpperCase() + doc.type.slice(1)}</Text>
          </div>
          <Badge color={statusColors[doc.status]} size="lg">{doc.status}</Badge>
        </Group>

        <Group justify="space-between" mb="md">
          <div>
            <Text size="sm" c="dimmed">Client</Text>
            <Text fw={500}>{doc.client?.name}</Text>
            {doc.client?.email && <Text size="sm" c="dimmed">{doc.client.email}</Text>}
          </div>
          <div style={{ textAlign: 'right' }}>
            <Text size="sm" c="dimmed">Date: {formatDate(doc.date)}</Text>
            {doc.due_date && <Text size="sm" c="dimmed">Due: {formatDate(doc.due_date)}</Text>}
          </div>
        </Group>

        <Divider mb="md" />

        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Description</Table.Th>
              <Table.Th>Qty</Table.Th>
              <Table.Th>Price</Table.Th>
              <Table.Th>Disc %</Table.Th>
              <Table.Th>Tax</Table.Th>
              <Table.Th>Total</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {doc.items?.map((item, i) => (
              <Table.Tr key={i}>
                <Table.Td>
                  <Group gap="xs">
                    <Badge color={item.item_type === 'product' ? 'blue' : 'green'} size="xs">{item.item_type}</Badge>
                    {item.description}
                  </Group>
                </Table.Td>
                <Table.Td>{item.quantity} {item.unit}</Table.Td>
                <Table.Td>{formatCurrency(item.price)}</Table.Td>
                <Table.Td>
                  {item.discount_value > 0
                    ? item.discount_type === 'flat'
                      ? formatCurrency(item.discount_value)
                      : `${item.discount_value}%`
                    : '—'}
                </Table.Td>
                <Table.Td>{item.tax_percent}%</Table.Td>
                <Table.Td fw={500}>{formatCurrency(item.total || 0)}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>

        <Divider my="md" />

        <Group justify="flex-end">
          <Stack gap={4} align="flex-end">
            <Text size="sm">Subtotal: {formatCurrency(doc.subtotal)}</Text>
            {parseFloat(doc.discount_amount) > 0 && (
              <Text size="sm">Discount: -{formatCurrency(doc.discount_amount)}</Text>
            )}
            <Text size="sm">Tax: {formatCurrency(doc.tax_amount)}</Text>
            <Text size="lg" fw={700}>Total: {formatCurrency(doc.total)}</Text>
            {isInvoice && (
              <>
                <Text size="sm" c="green">Paid: {formatCurrency(doc.paid_amount)}</Text>
                <Text size="sm" c="red" fw={600}>Balance: {formatCurrency(doc.balance_due)}</Text>
              </>
            )}
          </Stack>
        </Group>

        {doc.notes && (
          <>
            <Divider my="md" />
            <Text size="sm" c="dimmed">Notes: {doc.notes}</Text>
          </>
        )}

        {/* Payment Information */}
        {paymentMethods.some((m) => m.details?.some((d) => d.value.trim())) && (
          <>
            <Divider my="md" label="Payment Information" labelPosition="left" />
            <Group align="flex-start" gap="xl">
              {paymentMethods
                .filter((m) => m.details?.some((d) => d.value.trim()))
                .map((m) => (
                  <Stack key={m.value} gap={2}>
                    <Text size="sm" fw={600}>{m.label}</Text>
                    {m.details!
                      .filter((d) => d.value.trim())
                      .map((d, i) => (
                        <Text key={i} size="xs" c="dimmed">
                          {d.key}: <Text span fw={500} c="dark">{d.value}</Text>
                        </Text>
                      ))}
                  </Stack>
                ))}
            </Group>
          </>
        )}
      </Card>

      {/* Action Buttons */}
      <Group>
        <Button variant="light" leftSection={<IconFileDownload size={16} />}
          onClick={handleDownloadPdf} loading={loading === 'pdf'}>
          Download PDF
        </Button>
        <Button variant="light" leftSection={<IconSend size={16} />}
          onClick={handleSend} loading={loading === 'send'}>
          Send Email
        </Button>
        {canConvert && (
          <Button leftSection={<IconArrowRight size={16} />}
            onClick={handleConvert} loading={loading === 'convert'}>
            Convert to {doc.type === 'quotation' ? 'Proforma' : 'Invoice'}
          </Button>
        )}
        {isInvoice && doc.balance_due > 0 && (
          <Button color="green" leftSection={<IconCash size={16} />}
            onClick={() => setShowPayment(true)}>
            Record Payment
          </Button>
        )}
      </Group>

      {/* Payment Form */}
      {showPayment && (
        <Card withBorder>
          <Text fw={600} mb="md">Record Payment</Text>
          <form onSubmit={paymentForm.onSubmit(handlePayment)}>
            <Stack>
              <Group grow>
                <NumberInput label="Amount" min={0.01} decimalScale={2} required {...paymentForm.getInputProps('amount')} />
                <DateInput label="Payment Date" required {...paymentForm.getInputProps('payment_date')} />
              </Group>
              <Group grow>
                <Select label="Method" data={paymentMethods} {...paymentForm.getInputProps('payment_method')} />
                <TextInput label="Reference" placeholder="Transaction ref" {...paymentForm.getInputProps('reference')} />
              </Group>
              {getMethodDetails(paymentForm.values.payment_method).length > 0 && (
                <Alert variant="light" color="blue" p="xs">
                  {getMethodDetails(paymentForm.values.payment_method).map((d, i) => (
                    <Text key={i} size="xs"><Text span fw={600}>{d.key}:</Text> {d.value}</Text>
                  ))}
                </Alert>
              )}
              <Textarea label="Notes" {...paymentForm.getInputProps('notes')} />
              <Group justify="flex-end">
                <Button variant="light" onClick={() => setShowPayment(false)}>Cancel</Button>
                <Button type="submit" color="green" loading={loading === 'payment'}>Save Payment</Button>
              </Group>
            </Stack>
          </form>
        </Card>
      )}

      {/* Payment History */}
      {doc.payments && doc.payments.length > 0 && (
        <Card withBorder>
          <Text fw={600} mb="md">Payment History</Text>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Reference</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {doc.payments.map((p) => (
                <Table.Tr key={p.id}>
                  <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                  <Table.Td fw={500}>{formatCurrency(p.amount)}</Table.Td>
                  <Table.Td>{p.payment_method}</Table.Td>
                  <Table.Td>{p.reference || '—'}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Card>
      )}
    </Stack>
  );
}

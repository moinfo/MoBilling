import { Card, Group, Text, Badge, Checkbox, Table, Divider, Button, Stack, NumberInput, Select, TextInput, Textarea, Alert } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconFileDownload, IconSend, IconArrowRight, IconCash, IconX, IconRefresh } from '@tabler/icons-react';
import { useState } from 'react';
import { Document, convertDocument, downloadPdf, sendDocument, createPaymentIn, cancelDocument, uncancelDocument } from '../../api/documents';
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
  paid: 'green', overdue: 'orange', partial: 'yellow', cancelled: 'red',
};

export default function DocumentView({ document: doc, onRefresh, onClose: _onClose }: Props) {
  const { methods: paymentMethods, getMethodDetails } = usePaymentMethods();
  const [showPayment, setShowPayment] = useState(false);
  const [loading, setLoading] = useState('');
  const [selectedItems, setSelectedItems] = useState<string[]>([]);

  const paymentForm = useForm({
    initialValues: {
      amount: doc.balance_due,
      payment_date: new Date(),
      payment_method: paymentMethods[0]?.value || 'bank',
      reference: '',
      notes: '',
    },
  });

  const toggleItem = (itemId: string) => {
    setSelectedItems((prev) => {
      const next = prev.includes(itemId) ? prev.filter((id) => id !== itemId) : [...prev, itemId];
      // Auto-calculate amount from selected items
      const total = (doc.items || [])
        .filter((item) => next.includes(item.id || ''))
        .reduce((sum, item) => sum + parseFloat(String(item.total || 0)), 0);
      paymentForm.setFieldValue('amount', total > 0 ? total : doc.balance_due);
      // Auto-fill notes with selected item descriptions
      if (next.length > 0 && next.length < (doc.items?.length || 0)) {
        const descriptions = (doc.items || [])
          .filter((item) => next.includes(item.id || ''))
          .map((item) => item.description)
          .join(', ');
        paymentForm.setFieldValue('notes', `Payment for: ${descriptions}`);
      } else {
        paymentForm.setFieldValue('notes', '');
      }
      return next;
    });
  };

  const selectAllItems = () => {
    const allIds = (doc.items || []).map((item) => item.id || '').filter(Boolean);
    setSelectedItems(allIds);
    paymentForm.setFieldValue('amount', doc.balance_due);
    paymentForm.setFieldValue('notes', '');
  };

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

  const handleCancel = () => {
    modals.openConfirmModal({
      title: 'Cancel Invoice',
      children: `Cancel ${doc.document_number}? This will stop all reminders and collection actions.`,
      labels: { confirm: 'Cancel Invoice', cancel: 'Keep' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        try {
          setLoading('cancel');
          await cancelDocument(doc.id);
          notifications.show({ title: 'Cancelled', message: `${doc.document_number} has been cancelled`, color: 'green' });
          onRefresh();
        } catch (err: any) {
          notifications.show({ title: 'Error', message: err.response?.data?.message || 'Cancel failed', color: 'red' });
        } finally {
          setLoading('');
        }
      },
    });
  };

  const handleUncancel = () => {
    modals.openConfirmModal({
      title: 'Restore Invoice',
      children: `Restore ${doc.document_number}? This will reactivate the invoice and resume reminders.`,
      labels: { confirm: 'Restore', cancel: 'Keep Cancelled' },
      confirmProps: { color: 'green' },
      onConfirm: async () => {
        try {
          setLoading('uncancel');
          await uncancelDocument(doc.id);
          notifications.show({ title: 'Restored', message: `${doc.document_number} has been restored`, color: 'green' });
          onRefresh();
        } catch (err: any) {
          notifications.show({ title: 'Error', message: err.response?.data?.message || 'Restore failed', color: 'red' });
        } finally {
          setLoading('');
        }
      },
    });
  };

  const canConvert = (doc.type === 'quotation' || doc.type === 'proforma') && doc.status !== 'accepted';
  const isInvoice = doc.type === 'invoice';
  const canCancel = isInvoice && !['paid', 'cancelled', 'draft'].includes(doc.status) && doc.paid_amount <= 0;
  const canUncancel = isInvoice && doc.status === 'cancelled';

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
                    <div>
                      {item.description}
                      {item.service_from && item.service_to && (
                        <Text size="xs" c="dimmed">{formatDate(item.service_from)} — {formatDate(item.service_to)}</Text>
                      )}
                    </div>
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
        {canCancel && (
          <Button variant="light" color="red" leftSection={<IconX size={16} />}
            onClick={handleCancel} loading={loading === 'cancel'}>
            Cancel Invoice
          </Button>
        )}
        {canUncancel && (
          <Button variant="light" color="green" leftSection={<IconRefresh size={16} />}
            onClick={handleUncancel} loading={loading === 'uncancel'}>
            Restore Invoice
          </Button>
        )}
      </Group>

      {/* Payment Form */}
      {showPayment && (
        <Card withBorder>
          <Group justify="space-between" mb="md">
            <Text fw={600}>Record Payment</Text>
            <Button variant="subtle" size="xs" onClick={selectAllItems}>Select All Items</Button>
          </Group>

          {/* Item selection for partial payment */}
          {doc.items && doc.items.length > 1 && (
            <Stack gap="xs" mb="md">
              <Text size="sm" c="dimmed">Select items the client is paying for:</Text>
              {doc.items.map((item) => (
                <Group
                  key={item.id}
                  gap="sm"
                  p="xs"
                  style={{
                    borderRadius: 6,
                    background: selectedItems.includes(item.id || '') ? 'var(--mantine-color-green-light)' : 'var(--mantine-color-gray-light)',
                    cursor: 'pointer',
                  }}
                  onClick={() => toggleItem(item.id || '')}
                >
                  <Checkbox
                    checked={selectedItems.includes(item.id || '')}
                    onChange={() => {}}
                    size="sm"
                  />
                  <div style={{ flex: 1 }}>
                    <Text size="sm">{item.description}</Text>
                    {item.service_from && item.service_to && (
                      <Text size="xs" c="dimmed">{formatDate(item.service_from)} — {formatDate(item.service_to)}</Text>
                    )}
                  </div>
                  <Text size="sm" fw={600}>{formatCurrency(item.total || 0)}</Text>
                </Group>
              ))}
            </Stack>
          )}

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

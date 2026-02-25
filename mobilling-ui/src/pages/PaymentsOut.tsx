import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Stack, NumberInput, Select, TextInput, Textarea, Button, Anchor } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconEdit, IconTrash, IconDownload } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getPaymentsOut, updatePaymentOut, deletePaymentOut, PaymentOut } from '../api/bills';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

export default function PaymentsOut() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<PaymentOut | null>(null);

  const { data } = useQuery({
    queryKey: ['payments-out', page],
    queryFn: () => getPaymentsOut({ page }),
  });

  const payments: PaymentOut[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const updateMutation = useMutation({
    mutationFn: (values: any) => updatePaymentOut(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments-out'] });
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Payment updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update payment', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deletePaymentOut(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments-out'] });
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      notifications.show({ title: 'Success', message: 'Payment deleted', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to delete payment', color: 'red' }),
  });

  const handleDelete = (payment: PaymentOut) => {
    modals.openConfirmModal({
      title: 'Delete Payment',
      children: `Delete ${formatCurrency(payment.amount)} payment for "${payment.bill?.name}"?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(payment.id),
    });
  };

  return (
    <>
      <Title order={2} mb="md">Payment History</Title>

      {payments.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No payment history</Text>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Bill</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Control No.</Table.Th>
                <Table.Th>Reference</Table.Th>
                <Table.Th>Receipt</Table.Th>
                <Table.Th w={100}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {payments.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                <Table.Td fw={500}>{p.bill?.name || '—'}</Table.Td>
                <Table.Td>{formatCurrency(p.amount)}</Table.Td>
                <Table.Td>
                  <Badge variant="light" size="sm">{p.payment_method}</Badge>
                </Table.Td>
                <Table.Td>{p.control_number || '—'}</Table.Td>
                <Table.Td>{p.reference || '—'}</Table.Td>
                <Table.Td>
                  {p.receipt_url ? (
                    <Anchor href={p.receipt_url} target="_blank" size="sm">
                      <IconDownload size={16} />
                    </Anchor>
                  ) : '—'}
                </Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <ActionIcon variant="light" onClick={() => setEditing(p)}>
                      <IconEdit size={16} />
                    </ActionIcon>
                    <ActionIcon variant="light" color="red" onClick={() => handleDelete(p)}>
                      <IconTrash size={16} />
                    </ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      {/* Edit Payment Modal */}
      <Modal opened={!!editing} onClose={() => setEditing(null)} title="Edit Payment">
        {editing && (
          <EditPaymentForm
            payment={editing}
            onSubmit={(values) => updateMutation.mutate(values)}
            loading={updateMutation.isPending}
          />
        )}
      </Modal>
    </>
  );
}

function EditPaymentForm({ payment, onSubmit, loading }: {
  payment: PaymentOut;
  onSubmit: (values: any) => void;
  loading?: boolean;
}) {
  const form = useForm({
    initialValues: {
      amount: parseFloat(payment.amount),
      payment_date: new Date(payment.payment_date),
      payment_method: payment.payment_method,
      control_number: payment.control_number || '',
      reference: payment.reference || '',
      notes: payment.notes || '',
    },
  });

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      payment_date: dayjs(values.payment_date).format('YYYY-MM-DD'),
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <Group grow>
          <NumberInput label="Amount" min={0.01} decimalScale={2} required {...form.getInputProps('amount')} />
          <DateInput label="Payment Date" required {...form.getInputProps('payment_date')} />
        </Group>
        <Group grow>
          <Select label="Method" data={[
            { value: 'bank', label: 'Bank Transfer' },
            { value: 'mpesa', label: 'M-Pesa' },
            { value: 'cash', label: 'Cash' },
            { value: 'card', label: 'Card' },
            { value: 'other', label: 'Other' },
          ]} {...form.getInputProps('payment_method')} />
          <TextInput label="Control Number" placeholder="e.g., 991234567890" {...form.getInputProps('control_number')} />
        </Group>
        <TextInput label="Reference" placeholder="Transaction ref" {...form.getInputProps('reference')} />
        <Textarea label="Notes" {...form.getInputProps('notes')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Update Payment</Button>
        </Group>
      </Stack>
    </form>
  );
}
